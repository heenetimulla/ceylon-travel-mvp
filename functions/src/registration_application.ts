import {DocumentData, FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {isDeepStrictEqual} from "node:util";
import {DriverOperationError, normalizeIdentity, registryKey} from "./driver_administration";
import {EvidenceMetadataReader, readDriverEvidence} from "./driver_evidence";

export const agreementVersion = "1.1";
// Historical accepted versions remain valid for review, never for new submissions.
const reviewableAgreementVersions = ["1.0", agreementVersion];
type Dependencies = {secret: string; evidenceMetadata: EvidenceMetadataReader;
  principal: (uid: string) => Promise<{uid: string; admin: boolean; disabled?: boolean}>};
function requireValue(value: unknown, code: string, message: string): asserts value {
  if (!value) throw new DriverOperationError(code, message);
}
function text(value: unknown, max: number): string {
  requireValue(typeof value === "string" && value.trim().length > 0 && value.trim().length <= max,
    "invalid-input", "Complete the required application fields.");
  return value.trim();
}
function keys(value: DocumentData, allowed: string[]) {
  requireValue(value && typeof value === "object" && !Array.isArray(value) &&
    Object.keys(value).every((key) => allowed.includes(key)), "invalid-input", "Unsupported application fields.");
}
export function applicationProfile(input: DocumentData, driver: boolean): DocumentData {
  const common = ["fullName", "phoneNumber", "city"];
  const fields = driver ? [...common, "vehicleType", "vehicleNumber", "operatingArea", "availableAreas"] : common;
  keys(input, fields);
  const result: DocumentData = {};
  for (const field of fields) result[field] = text(input[field], field === "phoneNumber" ? 40 : 120);
  requireValue(/^\+?[0-9 ()-]{7,40}$/.test(result.phoneNumber) && result.phoneNumber.replace(/\D/g, "").length >= 7 &&
    result.phoneNumber.replace(/\D/g, "").length <= 15, "invalid-phone", "Enter a valid phone number.");
  if (driver) requireValue(["TukTuk", "Small Car", "Sedan Car", "Van - Highroof", "Van - Flatroof", "SUV", "Bus"].includes(result.vehicleType),
    "invalid-vehicle", "Choose a supported vehicle type.");
  return result;
}

export function upgradeDriverProfile(input: DocumentData): DocumentData {
  const fields = ["vehicleType", "vehicleNumber", "vehicleDetails", "operatingArea", "availableAreas"];
  keys(input, fields);
  const result: DocumentData = {};
  for (const field of fields) result[field] = text(input[field], 120);
  requireValue(["Any", "TukTuk", "Small Car", "Sedan Car", "Van - Highroof", "Van - Flatroof", "SUV", "Bus"].includes(result.vehicleType),
    "invalid-vehicle", "Choose a supported default vehicle type.");
  return result;
}

function eligibleTourist(user: DocumentData): boolean {
  return user.accountType === "tourist" && user.status === "active" &&
    (!Object.hasOwn(user, "registrationStatus") || user.registrationStatus === "approved") &&
    (Object.hasOwn(user, "accountStatus") ? user.accountStatus : user.status) === "active";
}

/** Same durable operation pattern and HMAC namespace as Stage 11D. No raw-identity lookup. */
export async function processRegistrationOperation(db: Firestore, uid: string, operationId: string, deps: Dependencies): Promise<void> {
  requireValue(/^[^/]{1,128}$/.test(uid) && /^[A-Za-z0-9_-]{1,128}$/.test(operationId), "invalid-input", "Invalid application.");
  const opRef = db.doc(`users/${uid}/application_operations/${operationId}`);
  const initial = (await opRef.get()).data();
  if (!initial || initial.status !== "pending") return;
  try {
    const actor = await deps.principal(text(initial.actorUid, 128));
    requireValue(!actor.disabled && actor.uid === initial.actorUid, "permission-denied", "Application access denied.");
    const startingUpgrade = initial.action === "start_driver_upgrade";
    const submittingUpgrade = initial.action === "submit_driver_upgrade";
    const submitting = initial.action === "submit_application" || submittingUpgrade;
    requireValue(submitting || startingUpgrade ? actor.uid === uid : actor.admin && ["approve", "reject", "request_correction"].includes(initial.action),
      "permission-denied", "Primary administrator permission is required for application review.");
    requireValue(Number.isSafeInteger(initial.expectedRevision) && initial.expectedRevision >= 0 && initial.expectedRevision < Number.MAX_SAFE_INTEGER,
      "invalid-revision", "Refresh the current application before continuing.");
    let evidence: Awaited<ReturnType<typeof readDriverEvidence>> = [];
    if (submitting) {
      try { evidence = await readDriverEvidence(uid, initial.expectedRevision + 1, initial.payload?.evidence, deps.evidenceMetadata, "registration_evidence"); }
      catch (_) { throw new DriverOperationError("invalid-evidence", "Please upload the required photos for this application revision."); }
    }
    await db.runTransaction(async (tx) => {
      const op = (await tx.get(opRef)).data();
      if (!op || op.status !== "pending") return;
      requireValue(op.actorUid === actor.uid && op.action === initial.action, "permission-denied", "Application operation changed.");
      const userRef = db.doc(`users/${uid}`), appRef = db.doc(`registration_applications/${uid}`);
      const user = (await tx.get(userRef)).data(), previous = (await tx.get(appRef)).data();
      requireValue(user && ["tourist", "driver"].includes(user.accountType) &&
        (user.registrationStatus != null || startingUpgrade || previous?.purpose === "driver_upgrade"),
        "invalid-account", "This account requires operator assistance before applying.");
      const revision = user.applicationRevision ?? 0;
      requireValue(Number.isSafeInteger(revision) && revision >= 0 && op.expectedRevision === revision,
        "stale-state", "Your application changed. Refresh before submitting again.");
      const stamp = FieldValue.serverTimestamp();
      if (startingUpgrade) {
        keys(op.payload, []);
        requireValue(eligibleTourist(user) && user.driverUpgradeStatus == null && previous?.purpose !== "driver_upgrade",
          "upgrade-locked", "An upgrade already exists or this account is not eligible. Refresh your account status.");
        // Reuse only a server-reviewed submission, never a client-supplied NIC/source pointer.
        const sourceRevision = previous?.registrationStatus === "approved" && user.identityVerificationStatus === "verified" &&
          previous.applicationRevision === revision && typeof previous.nicNumber === "string" ? revision : null;
        if (sourceRevision != null) {
          const source = (await tx.get(appRef.collection("submissions").doc(String(sourceRevision)))).data();
          requireValue(source?.uid === uid && source.nicNumber === previous!.nicNumber &&
            source.nicRegistryKey === previous!.nicRegistryKey && Array.isArray(source.evidence) &&
            source.evidence.some((e: DocumentData) => e?.evidenceType === "nic"),
          "identity-unavailable", "Your verified identity record requires support assistance before upgrading.");
        }
        tx.set(appRef, {uid, accountType: "tourist", targetAccountType: "driver", purpose: "driver_upgrade",
          registrationStatus: "draft", applicationRevision: revision, identitySourceRevision: sourceRevision,
          profile: {}, reason: null, createdAt: stamp, operationId});
        tx.update(userRef, {driverUpgradeStatus: "draft", applicationRevision: revision, updatedAt: stamp});
        const audit = {actorUid: uid, action: "driver_upgrade_started", purpose: "driver_upgrade",
          previousValue: null, newValue: "draft", reason: "", createdAt: stamp, applicationRevision: revision, operationId};
        tx.create(appRef.collection("history").doc(operationId), audit);
        tx.create(db.doc(`users/${uid}/admin_history/application_${operationId}`), audit);
        tx.update(opRef, {status: "succeeded", completedAt: stamp, result: {driverUpgradeStatus: "draft"}});
        return;
      }
      const upgrade = previous?.purpose === "driver_upgrade";
      requireValue(user.driverUpgradeStatus == null || upgrade, "invalid-purpose", "Refresh the current driver upgrade before continuing.");
      requireValue(!submitting || submittingUpgrade === upgrade, "invalid-purpose", "Use the current application workflow.");
      if (upgrade) {
        requireValue(user.uid === uid && eligibleTourist(user), "invalid-account", "This account cannot submit or review a driver upgrade currently.");
        requireValue(previous && previous.uid === uid && previous.applicationRevision === revision &&
          previous.registrationStatus === user.driverUpgradeStatus, "stale-state", "Refresh the current driver upgrade before continuing.");
      }
      const currentStatus = upgrade ? user.driverUpgradeStatus : user.registrationStatus;
      const driver = upgrade || user.accountType === "driver";
      const payload = op.payload;
      let reason = "", next: string;
      const patch: DocumentData = {updatedAt: stamp};
      if (submitting) {
        requireValue(["draft", "correction_required", "rejected"].includes(currentStatus),
          "submission-locked", "This application is already under review or approved.");
        keys(payload, ["profile", "nicNumber", "drivingLicenceNumber", "evidence", "agreementVersion", "agreementAccepted"]);
        requireValue(payload.agreementAccepted === true && payload.agreementVersion === agreementVersion,
          "agreement-required", "Read and accept the current Registration Guidelines & Agreement.");
        const profile = upgrade ? {fullName: text(user.fullName, 120), phoneNumber: text(user.phoneNumber, 40), city: user.city ?? "",
          ...upgradeDriverProfile(payload.profile)} : applicationProfile(payload.profile, driver);
        const sourceRevision = upgrade ? previous!.identitySourceRevision : null;
        let source: DocumentData | undefined;
        if (sourceRevision != null) {
          requireValue(Number.isSafeInteger(sourceRevision) && sourceRevision > 0 && sourceRevision <= revision,
            "invalid-source", "Your verified identity record requires support assistance.");
          source = (await tx.get(appRef.collection("submissions").doc(String(sourceRevision)))).data();
          requireValue(source?.uid === uid && source.accountType === "tourist" && source.purpose !== "driver_upgrade" &&
            user.identityVerificationStatus === "verified", "invalid-source", "Your verified identity record requires support assistance.");
          requireValue(payload.nicNumber == null && !Object.hasOwn(payload.evidence ?? {}, "nic"),
            "immutable-identity", "Your verified NIC is reused. Contact support if it needs correction.");
        }
        const required = source ? ["driving_licence", "selfie"] : driver ? ["nic", "driving_licence", "selfie"] : ["nic", "selfie"];
        requireValue(evidence.length === required.length && required.every((type) => evidence.some((e) => e.evidenceType === type)),
          "documents-required", "Upload every required identity photo and selfie.");
        requireValue(driver || payload.drivingLicenceNumber == null, "invalid-input", "Tourist applications do not require a driving licence.");
        const nicNumber = source ? source.nicNumber : payload.nicNumber;
        const claims = [{type: "nic", normalized: normalizeIdentity("nic", nicNumber)}];
        if (driver) claims.push({type: "driving_licence", normalized: normalizeIdentity("driving_licence", payload.drivingLicenceNumber)});
        const keyRef = db.doc("system_config/driver_identity_registry");
        const config = (await tx.get(keyRef)).data();
        const fingerprint = registryKey(deps.secret, "key-check", "stable-key-v1");
        requireValue(!config || config.keyFingerprint === fingerprint, "secret-mismatch", "Identity verification requires operator assistance.");
        const refs = claims.map((c) => db.doc(`identity_registry/${registryKey(deps.secret, c.type, c.normalized)}`));
        const held: Array<DocumentData | undefined> = [];
        for (const ref of refs) held.push((await tx.get(ref)).data());
        held.forEach((claim, index) => requireValue(!claim || claim.uid === uid, "identity-unavailable",
          index === 0 ? "This NIC number is already registered with another account. Please use your existing account or contact support."
            : "This Driving Licence number is already registered with another driver account. Please use your existing account or contact support."));
        if (source) requireValue(source.nicRegistryKey === refs[0].id && held[0]?.uid === uid,
          "identity-unavailable", "Your verified NIC requires support assistance.");
        const reusedNic = source && Array.isArray(source.evidence)
          ? source.evidence.find((e: DocumentData) => e?.evidenceType === "nic") : undefined;
        if (source) requireValue(reusedNic?.applicationRevision === sourceRevision &&
          typeof reusedNic.storagePath === "string" && reusedNic.storagePath.startsWith(`registration_evidence/${uid}/${sourceRevision}/nic/`),
        "invalid-source", "Your verified NIC evidence requires support assistance.");
        const submittedEvidence = source ? [{...reusedNic, reusedFromApplicationRevision: sourceRevision}, ...evidence] : evidence;
        const submission = {uid, accountType: user.accountType, profile, email: user.email,
          purpose: upgrade ? "driver_upgrade" : "registration", targetAccountType: driver ? "driver" : "tourist",
          ...(upgrade ? {identitySourceRevision: sourceRevision ?? null} : {}),
          nicNumber: text(nicNumber, 40), drivingLicenceNumber: driver ? text(payload.drivingLicenceNumber, 40) : null,
          evidence: submittedEvidence, agreementVersion, agreementAcceptedAt: stamp, submittedAt: stamp,
          applicationRevision: revision + 1, registrationStatus: "pending_review", reason: null,
          nicRegistryKey: refs[0].id, licenceRegistryKey: driver ? refs[1].id : null,
          reviewedAt: null, reviewedBy: null, operationId};
        if (!config) tx.create(keyRef, {keyFingerprint: fingerprint, createdAt: stamp});
        refs.forEach((ref, index) => { if (!held[index]) tx.create(ref, {uid, identifierType: claims[index].type, claimedAt: stamp}); });
        tx.create(appRef.collection("submissions").doc(String(revision + 1)), submission);
        tx.set(appRef, submission);
        // Current queue summary only: initial submission and every resubmission
        // share the immutable revision's server timestamp in this same commit.
        // Review actions below intentionally do not advance this timestamp.
        if (upgrade) {
          Object.assign(patch, {applicationRevision: revision + 1, driverUpgradeSubmittedAt: stamp});
        } else {
          Object.assign(patch, profile, {applicationRevision: revision + 1, applicationSubmittedAt: submission.submittedAt,
            identityVerificationStatus: "pending", accountStatus: "pending_approval"});
        }
        if (driver && !upgrade) {
          const {registrationStatus: submittedRegistrationStatus, ...verificationFields} = submission;
          const verification = {...verificationFields, submittedRegistrationStatus, identityVerificationStatus: "pending", rejectionReason: null, updatedAt: stamp,
            nicDocumentPath: evidence.find((e) => e.evidenceType === "nic")!.storagePath,
            drivingLicenceDocumentPath: evidence.find((e) => e.evidenceType === "driving_licence")!.storagePath,
            selfiePath: evidence.find((e) => e.evidenceType === "selfie")!.storagePath};
          tx.set(db.doc(`driver_verifications/${uid}`), verification);
          tx.create(db.doc(`driver_verifications/${uid}/submissions/application_${revision + 1}`), verification);
          patch.driverAdminRevision = (user.driverAdminRevision ?? 0) + 1;
        }
        next = "pending_review";
      } else {
        keys(payload, []);
        requireValue(currentStatus === "pending_review" && previous?.registrationStatus === "pending_review" &&
          previous.applicationRevision === revision, "review-locked", "Only the current pending application can be reviewed.");
        if (op.action === "approve") {
          if (upgrade) {
            const submitted = (await tx.get(appRef.collection("submissions").doc(String(revision)))).data();
            requireValue(submitted && isDeepStrictEqual(previous, submitted) && submitted.uid === uid &&
              submitted.accountType === "tourist" && submitted.targetAccountType === "driver" &&
              submitted.purpose === "driver_upgrade" && submitted.registrationStatus === "pending_review" &&
              Object.hasOwn(submitted, "identitySourceRevision") &&
              submitted.applicationRevision === revision && submitted.agreementVersion === agreementVersion &&
              submitted.agreementAcceptedAt instanceof Timestamp && submitted.submittedAt instanceof Timestamp &&
              submitted.agreementAcceptedAt.isEqual(submitted.submittedAt),
            "incomplete-application", "The current submitted upgrade is inconsistent. Request a correction.");
            const fields = ["vehicleType", "vehicleNumber", "vehicleDetails", "operatingArea", "availableAreas"];
            const driverProfile = upgradeDriverProfile(Object.fromEntries(fields.map(field => [field, submitted.profile?.[field]])));
            requireValue(Array.isArray(submitted.evidence) && submitted.evidence.length === 3,
              "incomplete-application", "All driver identity photos are required.");
            const sourceRevision = submitted.identitySourceRevision;
            if (sourceRevision != null) {
              requireValue(Number.isSafeInteger(sourceRevision) && sourceRevision > 0 && sourceRevision < revision &&
                user.identityVerificationStatus === "verified", "invalid-source", "The original verified identity requires review.");
              const source = (await tx.get(appRef.collection("submissions").doc(String(sourceRevision)))).data();
              const originalNic = source && Array.isArray(source.evidence)
                ? source.evidence.find((e: DocumentData) => e?.evidenceType === "nic") : undefined;
              requireValue(source?.uid === uid && source.applicationRevision === sourceRevision &&
                source.accountType === "tourist" && source.purpose !== "driver_upgrade" &&
                source.nicNumber === submitted.nicNumber && source.nicRegistryKey === submitted.nicRegistryKey && originalNic &&
                isDeepStrictEqual(submitted.evidence.find((e: DocumentData) => e?.evidenceType === "nic"),
                  {...originalNic, reusedFromApplicationRevision: sourceRevision}),
              "invalid-source", "The original verified identity requires review.");
            }
            // Objects are append-only. Re-read authoritative Storage facts on review,
            // including the explicitly referenced historical NIC, on each transaction attempt.
            for (const kind of ["nic", "driving_licence", "selfie"]) {
              const item = submitted.evidence.find((e: DocumentData) => e?.evidenceType === kind);
              const evidenceRevision = kind === "nic" && sourceRevision != null ? sourceRevision : revision;
              requireValue(item?.applicationRevision === evidenceRevision, "invalid-evidence", "Review the required identity photos.");
              try {
                const [actual] = await readDriverEvidence(uid, evidenceRevision, {[kind]: item.storagePath}, deps.evidenceMetadata, "registration_evidence");
                const {reusedFromApplicationRevision: _source, ...stored} = item;
                requireValue(isDeepStrictEqual(actual, stored), "invalid-evidence", "An identity photo changed. Request a correction.");
              } catch (_) {
                throw new DriverOperationError("invalid-evidence", "An identity photo is unavailable or changed. Request a correction.");
              }
            }
            requireValue(!(await tx.get(db.doc(`driver_verifications/${uid}`))).exists &&
              user.driverRegistrationNumber == null && user.membershipPlan == null && user.currentRegistrationPaymentId == null &&
              (user.paymentStatus == null || user.paymentStatus === "pending") &&
              (user.membershipStatus == null || user.membershipStatus === "pending") &&
              Number.isSafeInteger(user.driverAdminRevision ?? 0) && (user.driverAdminRevision ?? 0) >= 0 &&
              (user.driverAdminRevision ?? 0) < Number.MAX_SAFE_INTEGER,
            "invalid-account", "Existing driver administration data requires operator review.");
            Object.assign(patch, driverProfile, {accountType: "driver", registrationStatus: "approved",
              identityVerificationStatus: "verified", accountStatus: "pending_approval", paymentStatus: "pending",
              membershipStatus: "pending", driverAdminRevision: (user.driverAdminRevision ?? 0) + 1});
          }
          // Confirm the submitted revision still holds its trusted identity claims.
          const config = (await tx.get(db.doc("system_config/driver_identity_registry"))).data();
          requireValue(config?.keyFingerprint === registryKey(deps.secret, "key-check", "stable-key-v1"),
            "secret-mismatch", "Identity verification requires operator assistance.");
          const claims: Array<{type: "nic" | "driving_licence"; value: unknown; key: unknown}> =
            [{type: "nic", value: previous.nicNumber, key: previous.nicRegistryKey}];
          if (driver) claims.push({type: "driving_licence", value: previous.drivingLicenceNumber, key: previous.licenceRegistryKey});
          for (const claim of claims) {
            const key = registryKey(deps.secret, claim.type, normalizeIdentity(claim.type, claim.value));
            requireValue(key === claim.key && (await tx.get(db.doc(`identity_registry/${key}`))).data()?.uid === uid,
              "identity-unavailable", "Identity claims require operator review. Contact support.");
          }
          requireValue(upgrade || (reviewableAgreementVersions.includes(previous.agreementVersion) && previous.agreementAcceptedAt != null &&
            Array.isArray(previous.evidence) && (driver ? ["nic", "driving_licence", "selfie"] : ["nic", "selfie"])
              .every((type) => previous.evidence.some((e: DocumentData | null) => e != null && e.evidenceType === type && e.applicationRevision === revision))),
            "incomplete-application", "The submitted application is incomplete. Request a correction.");
        }
        reason = op.action === "approve" ? "" : text(op.reason, 500);
        next = op.action === "approve" ? "approved" : op.action === "reject" ? "rejected" : "correction_required";
        if (!upgrade) Object.assign(patch, {identityVerificationStatus: next === "approved" ? "verified" : "rejected",
          accountStatus: next === "approved" && !driver ? "active" : "pending_approval"});
        if (driver && !upgrade && next === "approved") {
          // Current operational state lives on users; approval does not grant payment or membership.
          patch.paymentStatus = user.paymentStatus ?? "pending";
          patch.membershipStatus = user.membershipStatus ?? "pending";
        }
        tx.update(appRef, {registrationStatus: next, reason: reason || null, reviewedBy: actor.uid, reviewedAt: stamp});
        if (upgrade && next === "approved") {
          const {registrationStatus: submittedRegistrationStatus, ...snapshot} = previous;
          const verification = {...snapshot, submittedRegistrationStatus, identityVerificationStatus: "verified",
            reviewedBy: actor.uid, reviewedAt: stamp, rejectionReason: null, updatedAt: stamp,
            nicDocumentPath: previous.evidence.find((e: DocumentData) => e.evidenceType === "nic").storagePath,
            drivingLicenceDocumentPath: previous.evidence.find((e: DocumentData) => e.evidenceType === "driving_licence").storagePath,
            selfiePath: previous.evidence.find((e: DocumentData) => e.evidenceType === "selfie").storagePath};
          tx.create(db.doc(`driver_verifications/${uid}`), verification);
          tx.create(db.doc(`driver_verifications/${uid}/submissions/application_${revision}`), verification);
        }
        if (driver && !upgrade) {
          tx.update(db.doc(`driver_verifications/${uid}`), {identityVerificationStatus: patch.identityVerificationStatus,
            rejectionReason: reason || null, reviewedBy: actor.uid, reviewedAt: stamp, updatedAt: stamp});
          patch.driverAdminRevision = (user.driverAdminRevision ?? 0) + 1;
        }
      }
      patch[upgrade ? "driverUpgradeStatus" : "registrationStatus"] = next;
      tx.update(userRef, patch);
      const audit = {actorUid: actor.uid,
        ...(upgrade && next === "approved" ? {targetUid: uid, previousAccountType: "tourist", resultingAccountType: "driver",
          resultingAccountStatus: "pending_approval"} : {}),
        action: upgrade ? (submitting ? "driver_upgrade_submitted" : `driver_upgrade_${next}`)
          : submitting ? "application_submitted" : `application_${next}`,
        purpose: upgrade ? "driver_upgrade" : "registration",
        previousValue: currentStatus, newValue: next, reason, createdAt: stamp,
        applicationRevision: submitting ? revision + 1 : revision, operationId};
      tx.create(appRef.collection("history").doc(operationId), audit);
      tx.create(db.doc(`users/${uid}/admin_history/application_${operationId}`), audit);
      tx.update(opRef, {status: "succeeded", completedAt: stamp,
        result: upgrade ? {driverUpgradeStatus: next} : {registrationStatus: next}});
    });
  } catch (error) {
    if (!(error instanceof DriverOperationError)) throw error;
    await db.runTransaction(async (tx) => {
      if ((await tx.get(opRef)).data()?.status === "pending") tx.update(opRef,
        {status: "failed", errorCode: error.code, errorMessage: error.message, completedAt: FieldValue.serverTimestamp()});
    });
  }
}
