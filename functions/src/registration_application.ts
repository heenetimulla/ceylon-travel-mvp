import {DocumentData, FieldValue, Firestore} from "firebase-admin/firestore";
import {DriverOperationError, normalizeIdentity, registryKey} from "./driver_administration";
import {EvidenceMetadataReader, readDriverEvidence} from "./driver_evidence";

export const agreementVersion = "1.0";
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

/** Same durable operation pattern and HMAC namespace as Stage 11D. No raw-identity lookup. */
export async function processRegistrationOperation(db: Firestore, uid: string, operationId: string, deps: Dependencies): Promise<void> {
  requireValue(/^[^/]{1,128}$/.test(uid) && /^[A-Za-z0-9_-]{1,128}$/.test(operationId), "invalid-input", "Invalid application.");
  const opRef = db.doc(`users/${uid}/application_operations/${operationId}`);
  const initial = (await opRef.get()).data();
  if (!initial || initial.status !== "pending") return;
  try {
    const actor = await deps.principal(text(initial.actorUid, 128));
    requireValue(!actor.disabled && actor.uid === initial.actorUid, "permission-denied", "Application access denied.");
    const submitting = initial.action === "submit_application";
    requireValue(submitting ? actor.uid === uid : actor.admin && ["approve", "reject", "request_correction"].includes(initial.action),
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
      requireValue(user && ["tourist", "driver"].includes(user.accountType) && user.registrationStatus != null,
        "invalid-account", "This account requires operator assistance before applying.");
      const revision = user.applicationRevision;
      requireValue(Number.isSafeInteger(revision) && revision >= 0 && op.expectedRevision === revision,
        "stale-state", "Your application changed. Refresh before submitting again.");
      const stamp = FieldValue.serverTimestamp();
      const driver = user.accountType === "driver";
      const payload = op.payload;
      let reason = "", next: string;
      const patch: DocumentData = {updatedAt: stamp};
      if (submitting) {
        requireValue(["draft", "correction_required", "rejected"].includes(user.registrationStatus),
          "submission-locked", "This application is already under review or approved.");
        keys(payload, ["profile", "nicNumber", "drivingLicenceNumber", "evidence", "agreementVersion", "agreementAccepted"]);
        requireValue(payload.agreementAccepted === true && payload.agreementVersion === agreementVersion,
          "agreement-required", "Read and accept the current Registration Guidelines & Agreement.");
        const profile = applicationProfile(payload.profile, driver);
        const required = driver ? ["nic", "driving_licence", "selfie"] : ["nic", "selfie"];
        requireValue(evidence.length === required.length && required.every((type) => evidence.some((e) => e.evidenceType === type)),
          "documents-required", "Upload every required identity photo and selfie.");
        requireValue(driver || payload.drivingLicenceNumber == null, "invalid-input", "Tourist applications do not require a driving licence.");
        const claims = [{type: "nic", normalized: normalizeIdentity("nic", payload.nicNumber)}];
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
        const submission = {uid, accountType: user.accountType, profile, email: user.email,
          nicNumber: text(payload.nicNumber, 40), drivingLicenceNumber: driver ? text(payload.drivingLicenceNumber, 40) : null,
          evidence, agreementVersion, agreementAcceptedAt: stamp, submittedAt: stamp,
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
        Object.assign(patch, profile, {applicationRevision: revision + 1, applicationSubmittedAt: submission.submittedAt,
          identityVerificationStatus: "pending", accountStatus: "pending_approval"});
        if (driver) {
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
        requireValue(user.registrationStatus === "pending_review" && previous?.registrationStatus === "pending_review" &&
          previous.applicationRevision === revision, "review-locked", "Only the current pending application can be reviewed.");
        if (op.action === "approve") {
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
          requireValue(previous.agreementVersion === agreementVersion && previous.agreementAcceptedAt != null &&
            Array.isArray(previous.evidence) && (driver ? ["nic", "driving_licence", "selfie"] : ["nic", "selfie"])
              .every((type) => previous.evidence.some((e: DocumentData | null) => e != null && e.evidenceType === type && e.applicationRevision === revision)),
            "incomplete-application", "The submitted application is incomplete. Request a correction.");
        }
        reason = op.action === "approve" ? "" : text(op.reason, 500);
        next = op.action === "approve" ? "approved" : op.action === "reject" ? "rejected" : "correction_required";
        Object.assign(patch, {identityVerificationStatus: next === "approved" ? "verified" : "rejected",
          accountStatus: next === "approved" && !driver ? "active" : "pending_approval"});
        if (driver && next === "approved") {
          // Current operational state lives on users; approval does not grant payment or membership.
          patch.paymentStatus = user.paymentStatus ?? "pending";
          patch.membershipStatus = user.membershipStatus ?? "pending";
        }
        tx.update(appRef, {registrationStatus: next, reason: reason || null, reviewedBy: actor.uid, reviewedAt: stamp});
        if (driver) {
          tx.update(db.doc(`driver_verifications/${uid}`), {identityVerificationStatus: patch.identityVerificationStatus,
            rejectionReason: reason || null, reviewedBy: actor.uid, reviewedAt: stamp, updatedAt: stamp});
          patch.driverAdminRevision = (user.driverAdminRevision ?? 0) + 1;
        }
      }
      patch.registrationStatus = next;
      tx.update(userRef, patch);
      const audit = {actorUid: actor.uid, action: submitting ? "application_submitted" : `application_${next}`,
        previousValue: user.registrationStatus, newValue: next, reason, createdAt: stamp,
        applicationRevision: submitting ? revision + 1 : revision, operationId};
      tx.create(appRef.collection("history").doc(operationId), audit);
      tx.create(db.doc(`users/${uid}/admin_history/application_${operationId}`), audit);
      tx.update(opRef, {status: "succeeded", completedAt: stamp, result: {registrationStatus: next}});
    });
  } catch (error) {
    if (!(error instanceof DriverOperationError)) throw error;
    await db.runTransaction(async (tx) => {
      if ((await tx.get(opRef)).data()?.status === "pending") tx.update(opRef,
        {status: "failed", errorCode: error.code, errorMessage: error.message, completedAt: FieldValue.serverTimestamp()});
    });
  }
}
