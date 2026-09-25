import {createHmac, randomBytes} from "node:crypto";
import {DocumentData, FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {EvidenceMetadataReader, readDriverEvidence, readPaymentEvidence} from "./driver_evidence";

export class DriverOperationError extends Error {
  constructor(readonly code: string, message: string) { super(message); }
}
function requireValue(condition: unknown, code: string, message: string): asserts condition {
  if (!condition) throw new DriverOperationError(code, message);
}
export const driverActions = ["submit_identity", "request_payment", "submit_payment"];
export const adminDriverActions = ["verify_identity", "reject_identity", "verify_payment", "reject_payment", "activate_membership", "set_account_status"];
function membershipEntitlement(founding: boolean) {
  return founding ? {membershipPlan: "founding_lifetime", registrationFeePaidLkr: 3500,
    annualRenewalRequired: false, annualRenewalFeeLkr: null} : {membershipPlan: "standard_annual",
    registrationFeePaidLkr: 5000, annualRenewalRequired: true, annualRenewalFeeLkr: 10000};
}
function registrationCounter(counter: DocumentData | undefined): number {
  const number = counter?.nextRegistrationNumber;
  requireValue(Number.isSafeInteger(number) && number > 0 && number < Number.MAX_SAFE_INTEGER &&
    typeof counter?.foundingOfferClosed === "boolean" && counter.foundingOfferClosed === (number > 100),
    "counter-unavailable", "Registration counter and founding cutoff require operator setup.");
  return number;
}
function quoteEntitlement(payment: DocumentData) {
  const founding = payment.quotedMembershipPlan === "founding_lifetime";
  const tier = membershipEntitlement(founding);
  requireValue(payment.paymentType === "registration" && payment.quotedMembershipPlan === tier.membershipPlan &&
    payment.quotedRegistrationFeeLkr === tier.registrationFeePaidLkr &&
    payment.expectedAmountLkr === tier.registrationFeePaidLkr &&
    payment.quotedAnnualRenewalRequired === tier.annualRenewalRequired &&
    (payment.quotedAnnualRenewalFeeLkr === tier.annualRenewalFeeLkr || (founding && payment.quotedAnnualRenewalFeeLkr === 0)) &&
    payment.foundingOfferOpenAtQuote === founding && payment.quotedAt != null,
    "invalid-quote", "Registration quote requires trusted operator review.");
  return tier;
}
export function firstAnniversary(now: Date): Date {
  const year = now.getUTCFullYear() + 1, month = now.getUTCMonth();
  const day = Math.min(now.getUTCDate(), new Date(Date.UTC(year, month + 1, 0)).getUTCDate());
  return new Date(Date.UTC(year, month, day, now.getUTCHours(), now.getUTCMinutes(), now.getUTCSeconds(), now.getUTCMilliseconds()));
}
function string(value: unknown, max = 500, required = true): string {
  requireValue(typeof value === "string" && value.trim().length <= max && (!required || value.trim().length > 0),
    "invalid-input", "Check the required fields and their lengths.");
  return value.trim();
}
function id(value: unknown): string {
  const result = string(value, 128);
  requireValue(/^[A-Za-z0-9_-]+$/.test(result), "invalid-input", "Invalid record identifier.");
  return result;
}
function keys(data: DocumentData, allowed: string[]) {
  requireValue(Object.keys(data).every((key) => allowed.includes(key)), "invalid-input", "Unexpected operation fields.");
}
export function normalizeIdentity(type: "nic" | "driving_licence", input: unknown): string {
  const value = string(input, 40).toUpperCase().replace(/[\s-]/g, "");
  if (type === "nic") {
    requireValue(/^(\d{9}[VX]|\d{12})$/.test(value), "invalid-identity", "Enter a valid NIC format.");
    // Old NIC YYDDDSSSSV/X and its 19YYDDD0SSSS form share one registry key.
    return value.length === 10 ? `19${value.slice(0, 5)}0${value.slice(5, 9)}` : value;
  }
  requireValue(/^[A-Z0-9]{6,20}$/.test(value), "invalid-identity", "Enter a valid driving licence format.");
  return value;
}
export function registryKey(secret: string, type: string, value: string): string {
  requireValue(Buffer.byteLength(secret, "utf8") >= 32, "secret-unavailable", "Identity verification is not configured.");
  return createHmac("sha256", secret).update(`ceylon-travel:v1:${type}:${value}`).digest("hex");
}
export function paymentReference(now: Date, random?: string): string {
  const date = now.toISOString().slice(2, 10).replace(/-/g, "");
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const suffix = random ?? [...randomBytes(6)].map((byte) => alphabet[byte & 31]).join("");
  requireValue(/^[A-Z0-9]{6}$/.test(suffix), "invalid-reference", "Invalid payment reference suffix.");
  return `CTP${date}${suffix}`;
}

type Principal = {uid: string; admin: boolean; disabled?: boolean};
type Dependencies = {principal: (uid: string) => Promise<Principal>; secret: string; now?: () => Date; evidenceMetadata?: EvidenceMetadataReader};

/** Durable Firestore command boundary. No client chooses a plan, fee or number.
 * All reads precede all writes; the command result and audit commit atomically.
 * Transport/Firestore failures are retried by the trigger. Domain failures are
 * recorded safely, without NIC/DL, payloads or raw backend errors in logs.
 */
export async function processDriverOperation(db: Firestore, uid: string, operationId: string, deps: Dependencies): Promise<void> {
  requireValue(typeof uid === "string" && uid.length > 0 && uid.length <= 128 && !uid.includes("/"), "invalid-input", "Invalid account.");
  id(operationId);
  const operationRef = db.doc(`users/${uid}/driver_operations/${operationId}`);
  const initial = (await operationRef.get()).data();
  if (!initial || initial.status !== "pending") return;
  try {
    const actor = await deps.principal(string(initial.actorUid, 128));
    requireValue(!actor.disabled && actor.uid === initial.actorUid, "permission-denied", "This account cannot perform this action.");
    let evidence: Awaited<ReturnType<typeof readDriverEvidence>> = [];
    let slipEvidence: Awaited<ReturnType<typeof readPaymentEvidence>> | undefined;
    if (initial.action === "submit_payment" || initial.action === "verify_payment") {
      requireValue(initial.action === "submit_payment" ? actor.uid === uid : actor.admin,
        "permission-denied", "Payment access denied.");
      requireValue(deps.evidenceMetadata, "evidence-unavailable", "Payment evidence is not configured.");
      const paymentId = id(initial.payload?.paymentId);
      const stored = initial.action === "verify_payment" ? (await db.doc(`users/${uid}/payments/${paymentId}`).get()).data() : null;
      const path = initial.action === "submit_payment" ? initial.payload?.slipPath : stored?.slipPath;
      try { slipEvidence = await readPaymentEvidence(uid, paymentId, path, deps.evidenceMetadata); }
      catch (_) { throw new DriverOperationError("invalid-evidence", "Upload a clear payment slip for this payment request before verification."); }
    }
    if (initial.action === "submit_identity" && initial.payload?.evidence != null) {
      requireValue(actor.uid === uid, "permission-denied", "Only the applicant can submit identity evidence.");
      requireValue(deps.evidenceMetadata, "evidence-unavailable", "Evidence uploads are not configured.");
      try { evidence = await readDriverEvidence(uid, initial.expectedRevision, initial.payload.evidence, deps.evidenceMetadata); }
      catch (_) { throw new DriverOperationError("invalid-evidence", "Evidence could not be confirmed. Refresh and upload photos for the current application."); }
    }
    const now = (deps.now ?? (() => new Date()))();
    const reference = paymentReference(now);
    await db.runTransaction(async (tx) => {
      const operation = (await tx.get(operationRef)).data();
      if (!operation || operation.status !== "pending") return;
      requireValue(operation.actorUid === actor.uid, "permission-denied", "The operation actor changed.");
      const action = operation.action;
      const adminAction = adminDriverActions.includes(action);
      requireValue(adminAction ? actor.admin : driverActions.includes(action) && actor.uid === uid,
        "permission-denied", "Primary administrator permission is required for review actions.");
      const payload = operation.payload;
      requireValue(payload && typeof payload === "object" && !Array.isArray(payload), "invalid-input", "Invalid operation payload.");
      const reason = string(operation.reason ?? "", 500, false);
      const userRef = db.doc(`users/${uid}`), verificationRef = db.doc(`driver_verifications/${uid}`);
      const user = (await tx.get(userRef)).data();
      requireValue(user?.accountType === "driver", "not-driver", "This workflow is only for driver accounts.");
      if (user.registrationStatus != null) {
        requireValue(!["submit_identity", "verify_identity", "reject_identity"].includes(action),
          "application-required", "Use the registration application review and correction workflow.");
        requireValue(user.registrationStatus === "approved", "application-required", "Application approval is required before driver administration.");
      }
      const revision = user.driverAdminRevision ?? 0;
      requireValue(Number.isSafeInteger(revision) && revision >= 0, "invalid-state", "Driver state requires review.");
      // Retried activations under a different ID never consume another number.
      if (action === "activate_membership" && user.driverRegistrationNumber != null) {
        keys(payload, []);
        requireValue(Number.isSafeInteger(user.driverRegistrationNumber) && user.driverRegistrationNumber > 0 &&
          ["founding_lifetime", "standard_annual"].includes(user.membershipPlan),
          "invalid-state", "Existing membership requires operator review.");
        tx.update(operationRef, {status: "succeeded", completedAt: FieldValue.serverTimestamp(), result: {alreadyActivated: true}});
        return;
      }
      requireValue(operation.expectedRevision === revision, "stale-state", "Driver details changed. Refresh before submitting a new action.");
      const patch: DocumentData = {driverAdminRevision: revision + 1, updatedAt: FieldValue.serverTimestamp()};
      const stamp = FieldValue.serverTimestamp();
      const writes: Array<() => void> = [];
      let audit: {action: string; previousValue: unknown; newValue: unknown} | undefined;
      let result: DocumentData = {};

      if (action === "submit_identity") {
        keys(payload, ["nicNumber", "drivingLicenceNumber", "nicDocumentPath", "drivingLicenceDocumentPath", "selfiePath", "evidence"]);
        const previous = (await tx.get(verificationRef)).data();
        requireValue(previous?.identityVerificationStatus !== "verified", "already-verified", "Verified identity cannot be replaced by the driver.");
        const nic = normalizeIdentity("nic", payload.nicNumber), licence = normalizeIdentity("driving_licence", payload.drivingLicenceNumber);
        const keyConfigRef = db.doc("system_config/driver_identity_registry");
        const keyConfig = (await tx.get(keyConfigRef)).data();
        const fingerprint = registryKey(deps.secret, "key-check", "stable-key-v1");
        requireValue(!keyConfig || keyConfig.keyFingerprint === fingerprint, "secret-mismatch", "Identity registry key requires operator review.");
        const claims = [{type: "nic", normalized: nic}, {type: "driving_licence", normalized: licence}];
        const claimRefs = claims.map((claim) => db.doc(`identity_registry/${registryKey(deps.secret, claim.type, claim.normalized)}`));
        const existing: Array<DocumentData | undefined> = [];
        for (const ref of claimRefs) existing.push((await tx.get(ref)).data());
        existing.forEach((claim) => requireValue(!claim || claim.uid === uid, "identity-unavailable", "An identity identifier is already claimed. Contact support."));
        const submission = {uid, nicNumber: string(payload.nicNumber, 40), drivingLicenceNumber: string(payload.drivingLicenceNumber, 40),
          evidence,
          nicDocumentPath: evidence.find((e) => e.evidenceType === "nic")?.storagePath ?? (payload.nicDocumentPath == null ? null : string(payload.nicDocumentPath, 500)),
          drivingLicenceDocumentPath: evidence.find((e) => e.evidenceType === "driving_licence")?.storagePath ?? (payload.drivingLicenceDocumentPath == null ? null : string(payload.drivingLicenceDocumentPath, 500)),
          selfiePath: evidence.find((e) => e.evidenceType === "selfie")?.storagePath ?? (payload.selfiePath == null ? null : string(payload.selfiePath, 500)),
          identityVerificationStatus: "pending", submittedAt: stamp,
          reviewedAt: null, reviewedBy: null, rejectionReason: null, updatedAt: stamp,
          nicRegistryKey: claimRefs[0].id, licenceRegistryKey: claimRefs[1].id};
        if (!keyConfig) writes.push(() => tx.create(keyConfigRef, {keyFingerprint: fingerprint, createdAt: stamp}));
        claims.forEach((claim, index) => {
          if (!existing[index]) writes.push(() => tx.create(claimRefs[index], {identifierType: claim.type, uid, claimedAt: stamp}));
        });
        writes.push(() => tx.set(verificationRef, submission));
        writes.push(() => tx.create(db.doc(`driver_verifications/${uid}/submissions/${operationId}`), submission));
        patch.identityVerificationStatus = "pending";
      } else if (action === "verify_identity" || action === "reject_identity") {
        keys(payload, []);
        const verification = (await tx.get(verificationRef)).data();
        requireValue(verification && ["pending", "verified", "rejected"].includes(verification.identityVerificationStatus),
          "missing-identity", "The driver must submit identity evidence first.");
        const status = action === "verify_identity" ? "verified" : "rejected";
        requireValue(verification.identityVerificationStatus !== status, "no-change", "Identity already has this status.");
        if (status === "verified") {
          const nicKey = registryKey(deps.secret, "nic", normalizeIdentity("nic", verification.nicNumber));
          const dlKey = registryKey(deps.secret, "driving_licence", normalizeIdentity("driving_licence", verification.drivingLicenceNumber));
          for (const key of [nicKey, dlKey]) {
            const claim = (await tx.get(db.doc(`identity_registry/${key}`))).data();
            requireValue(claim?.uid === uid, "identity-unavailable", "Identity registry claims are missing or conflicting.");
          }
          // Manual staff review is required; deferred uploads are not a prerequisite.
        }
        writes.push(() => tx.update(verificationRef, {identityVerificationStatus: status, reviewedAt: stamp,
          reviewedBy: actor.uid, rejectionReason: status === "rejected" ? reason : null, updatedAt: stamp}));
        patch.identityVerificationStatus = status;
        audit = {action: "identity_verification_changed", previousValue: verification.identityVerificationStatus, newValue: status};
      } else if (action === "request_payment") {
        keys(payload, []);
        requireValue(user.driverRegistrationNumber == null, "already-active", "Registration membership has already been activated.");
        const counter = (await tx.get(db.doc("system_config/driver_registration_counter"))).data();
        registrationCounter(counter);
        let tier = membershipEntitlement(!counter!.foundingOfferClosed);
        let quotedAt: unknown = stamp;
        const paid = user.registrationPaidTotalLkr ?? 0;
        requireValue(paid === 0, "already-paid", "Registration payment has already been credited. No further registration payment is required.");
        if (user.currentRegistrationPaymentId) {
          const current = (await tx.get(db.doc(`users/${uid}/payments/${id(user.currentRegistrationPaymentId)}`))).data();
          requireValue(current?.status !== "pending", "payment-pending", "Use or review the existing pending payment request first.");
          requireValue(current?.status === "rejected", "invalid-quote", "Existing registration quote requires operator review.");
          // A replacement claim retains this user's original commercial entitlement.
          tier = quoteEntitlement(current);
          quotedAt = current.quotedAt;
        }
        const paymentRef = db.doc(`users/${uid}/payments/${operationId}`), referenceRef = db.doc(`payment_reference_registry/${reference}`);
        requireValue(!(await tx.get(referenceRef)).exists, "reference-conflict", "Create another payment request.");
        const payment = {paymentType: "registration", paymentReference: reference,
          expectedAmountLkr: tier.registrationFeePaidLkr,
          quotedRegistrationFeeLkr: tier.registrationFeePaidLkr, quotedMembershipPlan: tier.membershipPlan,
          quotedAnnualRenewalRequired: tier.annualRenewalRequired, quotedAnnualRenewalFeeLkr: tier.annualRenewalFeeLkr,
          quotedAt, foundingOfferOpenAtQuote: !tier.annualRenewalRequired,
          claimedAmountLkr: null, claimedPaymentDate: null,
          bankTransactionReference: null, depositorName: null, slipPath: null, status: "pending", claimSubmitted: false,
          submittedAt: null, verifiedAt: null, verifiedBy: null, rejectionReason: null, createdAt: stamp, updatedAt: stamp};
        writes.push(() => tx.create(paymentRef, payment));
        writes.push(() => tx.create(referenceRef, {uid, paymentId: operationId, createdAt: stamp}));
        patch.paymentStatus = "pending"; patch.currentRegistrationPaymentId = operationId;
        result = {paymentId: operationId, paymentReference: reference, expectedAmountLkr: payment.expectedAmountLkr};
      } else if (action === "submit_payment" || action === "verify_payment" || action === "reject_payment") {
        keys(payload, action === "submit_payment" ? ["paymentId", "claimedAmountLkr", "claimedPaymentDate", "bankTransactionReference", "depositorName", "slipPath"]
          : action === "verify_payment" ? ["paymentId", "bankRecordReference"] : ["paymentId"]);
        const paymentId = id(payload.paymentId), paymentRef = db.doc(`users/${uid}/payments/${paymentId}`);
        const payment = (await tx.get(paymentRef)).data();
        requireValue(payment?.paymentType === "registration" && payment.status === "pending", "payment-final", "Only pending registration payments can change.");
        requireValue(user.currentRegistrationPaymentId === paymentId, "stale-payment", "Refresh the current registration payment.");
        if (action === "submit_payment") {
          const confirmedSlip = slipEvidence;
          requireValue(confirmedSlip && confirmedSlip.storagePath === payload.slipPath && confirmedSlip.paymentId === paymentId,
            "invalid-evidence", "Payment slip does not match this claim.");
          requireValue(!payment.claimSubmitted, "already-submitted", "A submitted claim is immutable. Ask an admin to review it.");
          requireValue(Number.isSafeInteger(payload.claimedAmountLkr) && payload.claimedAmountLkr > 0 && payload.claimedAmountLkr <= 1000000,
            "invalid-amount", "Enter a valid claimed amount in whole LKR.");
          const date = string(payload.claimedPaymentDate, 10);
          requireValue(/^\d{4}-\d{2}-\d{2}$/.test(date) && Number.isFinite(Date.parse(date)) && new Date(date).toISOString().slice(0, 10) === date,
            "invalid-date", "Enter the claimed payment date as YYYY-MM-DD.");
          writes.push(() => tx.update(paymentRef, {claimedAmountLkr: payload.claimedAmountLkr, claimedPaymentDate: date,
            bankTransactionReference: string(payload.bankTransactionReference, 120), depositorName: string(payload.depositorName, 120),
            slipPath: confirmedSlip.storagePath, slipEvidence: confirmedSlip, claimSubmitted: true, submittedAt: stamp, updatedAt: stamp}));
        } else {
          requireValue(payment.claimSubmitted === true, "missing-claim", "The driver has not submitted a payment claim.");
          const status = action === "verify_payment" ? "verified" : "rejected";
          let metadata: DocumentData = {};
          if (status === "verified") {
            requireValue(slipEvidence && slipEvidence.storagePath === payment.slipPath && slipEvidence.paymentId === paymentId,
              "invalid-evidence", "Refresh and review the current payment slip.");
            requireValue(Number.isSafeInteger(payment.expectedAmountLkr) && payment.expectedAmountLkr > 0 && payment.claimedAmountLkr === payment.expectedAmountLkr,
              "incorrect-amount", "Claimed and expected amounts must match; verify against bank records.");
            const required = quoteEntitlement(payment).registrationFeePaidLkr;
            const total = (user.registrationPaidTotalLkr ?? 0) + payment.expectedAmountLkr;
            requireValue(Number.isSafeInteger(total) && total === required, "incorrect-amount", "Payment must satisfy the stored registration quote exactly.");
            const bankReference = string(payload.bankRecordReference, 120).toUpperCase().replace(/\s/g, "");
            const keyConfigRef = db.doc("system_config/driver_identity_registry");
            const keyConfig = (await tx.get(keyConfigRef)).data();
            const fingerprint = registryKey(deps.secret, "key-check", "stable-key-v1");
            requireValue(!keyConfig || keyConfig.keyFingerprint === fingerprint, "secret-mismatch", "Identity registry key requires operator review.");
            const bankRef = db.doc(`payment_bank_registry/${registryKey(deps.secret, "bank-reference", bankReference)}`);
            requireValue(!(await tx.get(bankRef)).exists, "payment-used", "That bank transaction has already been verified.");
            if (!keyConfig) writes.push(() => tx.create(keyConfigRef, {keyFingerprint: fingerprint, createdAt: stamp}));
            writes.push(() => tx.create(bankRef, {uid, paymentId, claimedAt: stamp}));
            metadata = {bankRecordReference: bankReference, verifiedAt: stamp, verifiedBy: actor.uid};
            patch.registrationPaidTotalLkr = total;
            patch.paymentStatus = "verified";
          } else {
            requireValue(reason.length > 0, "reason-required", "Enter a reason for rejecting the payment.");
            patch.paymentStatus = "rejected";
          }
          writes.push(() => tx.update(paymentRef, {status, ...metadata, reviewedAt: stamp, reviewedBy: actor.uid,
            rejectionReason: status === "rejected" ? reason : null, updatedAt: stamp}));
          audit = {action: "payment_status_changed", previousValue: {paymentId, status: payment.status}, newValue: {paymentId, status}};
        }
      } else if (action === "activate_membership") {
        keys(payload, []);
        requireValue(user.membershipStatus !== "active" && user.membershipActivatedAt == null && user.membershipPlan == null,
          "invalid-state", "Membership has already been activated or requires operator review.");
        requireValue(user.identityVerificationStatus === "verified", "identity-required", "Verified identity is required.");
        requireValue(user.paymentStatus === "verified", "payment-required", "Verified registration payment is required.");
        const verification = (await tx.get(verificationRef)).data();
        requireValue(verification?.identityVerificationStatus === "verified", "identity-required", "Verified identity evidence is required.");
        const payment = user.currentRegistrationPaymentId
          ? (await tx.get(db.doc(`users/${uid}/payments/${id(user.currentRegistrationPaymentId)}`))).data() : null;
        requireValue(payment?.status === "verified", "payment-required", "A verified registration payment is required.");
        const counterRef = db.doc("system_config/driver_registration_counter"), counter = (await tx.get(counterRef)).data();
        const number = registrationCounter(counter), tier = quoteEntitlement(payment);
        requireValue(user.registrationPaidTotalLkr === tier.registrationFeePaidLkr && payment.claimedAmountLkr === tier.registrationFeePaidLkr,
          "incorrect-amount", "Verified payment must satisfy the stored registration quote.");
        const numberRef = db.doc(`driver_registration_registry/${number}`);
        requireValue(!(await tx.get(numberRef)).exists, "counter-conflict", "Registration counter conflicts with an assigned number.");
        const closureRef = db.doc("admin_notifications/founding_offer_closed");
        if (number === 100) {
          requireValue(!(await tx.get(closureRef)).exists, "counter-conflict", "Founding closure event already exists; operator review required.");
          writes.push(() => tx.create(closureRef, {type: "founding_offer_closed", title: "Founding offer closed",
            message: "Driver registration #100 has been activated. New driver registration quotes are now LKR 5,000.",
            registrationNumber: 100, createdAt: stamp, read: false}));
        }
        Object.assign(patch, tier, {driverRegistrationNumber: number, membershipStatus: "active",
          membershipValidUntil: tier.annualRenewalRequired ? Timestamp.fromDate(firstAnniversary(now)) : null,
          membershipActivatedAt: stamp, accountStatus: user.registrationStatus === "approved" && user.accountStatus === "pending_approval" ? "active" : (user.accountStatus ?? (user.status === "active" ? "active" : "inactive"))});
        writes.push(() => tx.update(counterRef, {nextRegistrationNumber: number + 1,
          ...(number === 100 ? {foundingOfferClosed: true, foundingOfferClosedAt: stamp,
            foundingOfferClosedByRegistrationNumber: 100} : {})}));
        writes.push(() => tx.create(numberRef, {uid, assignedAt: stamp}));
        audit = {action: "membership_activated", previousValue: {membershipStatus: user.membershipStatus ?? "pending"},
          newValue: {driverRegistrationNumber: number, ...tier, membershipStatus: "active", membershipValidUntil: patch.membershipValidUntil}};
        result = {driverRegistrationNumber: number, membershipPlan: tier.membershipPlan};
      } else if (action === "set_account_status") {
        keys(payload, ["accountStatus"]);
        requireValue(["active", "inactive", "suspended"].includes(payload.accountStatus), "invalid-status", "Choose an allowed account status.");
        const previous = user.accountStatus ?? (user.status === "active" ? "active" : "inactive");
        requireValue(previous !== payload.accountStatus, "no-change", "Account already has this status.");
        patch.accountStatus = payload.accountStatus;
        audit = {action: "account_status_changed", previousValue: previous, newValue: payload.accountStatus};
      }
      // Defaults are server-managed and independent of the legacy profile status.
      for (const [key, value] of Object.entries({identityVerificationStatus: "pending", paymentStatus: "pending", membershipStatus: "pending",
        accountStatus: user.status === "active" ? "active" : "inactive"})) {
        if (user[key] == null && patch[key] == null) patch[key] = value;
      }
      if (audit) writes.push(() => tx.create(db.doc(`users/${uid}/admin_history/${operationId}`),
        {...audit, actorUid: actor.uid, reason, createdAt: stamp, operationId}));
      for (const write of writes) write();
      tx.update(userRef, patch);
      tx.update(operationRef, {status: "succeeded", completedAt: stamp, result});
    });
  } catch (error) {
    if (!(error instanceof DriverOperationError)) throw error;
    await db.runTransaction(async (tx) => {
      const current = (await tx.get(operationRef)).data();
      if (current?.status === "pending") tx.update(operationRef, {status: "failed", completedAt: FieldValue.serverTimestamp(),
        errorCode: error.code, errorMessage: error.message});
    });
  }
}
