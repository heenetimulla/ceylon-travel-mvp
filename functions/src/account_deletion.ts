import {DocumentData, FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {DriverOperationError} from "./driver_administration";

export const deletionActions = ["approve", "reject", "request_clarification", "complete"];
export const activeDeletionTripStatuses = ["open", "accepted", "start_requested", "in_progress", "end_requested"];
export const cleanupCategories = ["shared_history", "private_evidence", "identity_and_applications",
  "payments_and_membership", "support_and_messages", "operations_and_audit", "backups_and_exports"];
export type DeletionDependencies = {
  principal: (uid: string) => Promise<{uid: string; admin: boolean; supportAdmin?: boolean; disabled?: boolean}>;
  disable: (uid: string) => Promise<void>;
  deleteAuth: (uid: string) => Promise<void>;
};
function check(value: unknown, code: string, message: string): asserts value {
  if (!value) throw new DriverOperationError(code, message);
}
/** A backend-only operator record, never a client checkbox. */
export function validCleanupClearance(data: DocumentData | undefined, revision: number): boolean {
  return !!data && data.requestRevision === revision && data.completedAt instanceof Timestamp &&
    typeof data.operatorUid === "string" && data.operatorUid.length > 0 &&
    typeof data.policyReference === "string" && data.policyReference.trim().length > 0 &&
    cleanupCategories.every(category => {
      const item = data.categories?.[category];
      return item && ["deleted", "anonymized", "not_present", "minimized_retention"].includes(item.disposition) &&
        typeof item.recordReference === "string" && item.recordReference.trim().length > 0 &&
        typeof item.rationale === "string" && item.rationale.trim().length > 0 &&
        (item.disposition !== "minimized_retention" ||
          (item.reviewAt instanceof Timestamp && item.reviewAt.toMillis() > data.completedAt.toMillis()));
    });
}

/** Replace the parent to remove unknown private fields; never cascade subcollections. */
export function deletionProfile(uid: string, user: DocumentData, completed: boolean): DocumentData {
  const result: DocumentData = {uid, fullName: "Deleted account", email: "", phoneNumber: "", city: "",
    profilePhotoPath: null, accountType: user.accountType === "driver" ? "driver" : "tourist",
    status: "blocked", accountStatus: "deleted", registrationStatus: "deleted",
    membershipStatus: "inactive", identityVerificationStatus: "not_verified",
    deletionStatus: completed ? "completed" : "approved", updatedAt: FieldValue.serverTimestamp()};
  // Historical counters keep counterpart rating transactions compatible.
  for (const field of ["completedTripsCount", "cancelledTripsCount", "cancellationCount", "cancellationRate",
    "ratingsCount", "ratingStarsTotal", "averageRating"]) result[field] = user[field] ?? 0;
  return result;
}

export async function processDeletionOperation(db: Firestore, uid: string, operationId: string,
  deps: DeletionDependencies): Promise<void> {
  check(uid.length > 0 && uid.length <= 128 && !uid.includes("/") && /^[A-Za-z0-9_-]{1,128}$/.test(operationId),
    "invalid-input", "Invalid deletion operation.");
  const requestRef = db.doc(`account_deletion_requests/${uid}`);
  const opRef = requestRef.collection("operations").doc(operationId);
  const initial = (await opRef.get()).data();
  if (!initial || !["pending", "processing"].includes(initial.status)) return;
  try {
    // A committed job is durable authorization; retries finish it without authorizing new decisions.
    if (initial.status === "pending") {
      const actor = await deps.principal(initial.actorUid);
      check(actor.uid === initial.actorUid && actor.admin && !actor.disabled && actor.uid !== uid,
        "permission-denied", "A different active primary administrator must review this request.");
      const target = await deps.principal(uid);
      check(!target.admin && !target.supportAdmin, "staff-account", "Remove staff privileges through the trusted staff process first.");
      await db.runTransaction(async tx => {
        const op = (await tx.get(opRef)).data();
        if (!op || op.status !== "pending") return;
        const request = (await tx.get(requestRef)).data();
        const userRef = db.doc(`users/${uid}`);
        const user = (await tx.get(userRef)).data();
        const actorBlocked = (await tx.get(db.doc(`account_deletion_blocks/${actor.uid}`))).exists;
        check(!actorBlocked && op.actorUid === actor.uid && deletionActions.includes(op.action),
          "permission-denied", "Deletion review is not permitted.");
        check(request && user && request.requesterUid === uid && op.expectedRevision === request.revision,
          "stale-state", "Refresh the deletion request before reviewing it.");
        check(typeof op.note === "string" && op.note.length <= 1000,
          "invalid-input", "Use a private review note of at most 1000 characters.");
        check(typeof op.userMessage === "string" && op.userMessage.length <= 500 &&
          (!["reject", "request_clarification"].includes(op.action) || op.userMessage.trim().length > 0),
          "invalid-input", "Add a short message for the requester when rejecting or requesting clarification.");
        const completing = op.action === "complete";
        check(completing ? request.status === "approved" && request.processingStage === "manual_cleanup_required"
          : ["pending", "needs_clarification"].includes(request.status), "invalid-state", "This request cannot take that action.");
        if (completing) {
          const clearance = (await tx.get(requestRef.collection("private").doc("cleanup"))).data();
          check(validCleanupClearance(clearance, request.revision), "cleanup-required",
            "Trusted operator cleanup and retention review must be recorded before completion.");
        }
        if (op.action === "approve" || completing) {
          // Never strand a participant or silently cancel a shared trip.
          for (const field of ["creatorId", "acceptedDriverId", "touristId", "driverId"]) {
            const active = await tx.get(db.collection("trip_posts").where(field, "==", uid)
              .where("status", "in", activeDeletionTripStatuses).limit(1));
            check(active.empty, "active-trips", "Resolve open or active trips before approving deletion.");
          }
        }
        const stamp = FieldValue.serverTimestamp();
        const next = completing ? "approved" : op.action === "approve" ? "approved"
          : op.action === "reject" ? "rejected" : "needs_clarification";
        const processing = op.action === "approve" || completing;
        tx.update(requestRef, {status: next, revision: request.revision + 1, updatedAt: stamp,
          reviewedBy: actor.uid, reviewedAt: stamp, userMessage: op.userMessage.trim(),
          processingStage: processing ? (completing ? "completing" : "restricting_access") : null});
        if (op.action === "approve") {
          const membership: DocumentData = {};
          for (const field of ["driverRegistrationNumber", "membershipPlan", "membershipActivatedAt",
            "membershipValidUntil", "registrationFeePaidLkr", "registrationPaidTotalLkr",
            "annualRenewalRequired", "annualRenewalFeeLkr", "currentRegistrationPaymentId"]) {
            if (user[field] !== undefined) membership[field] = user[field];
          }
          tx.set(requestRef.collection("private").doc("membership"), {snapshot: membership, capturedAt: stamp});
        }
        if (processing) {
          tx.set(db.doc(`account_deletion_blocks/${uid}`), {requesterUid: uid, blockedAt: stamp});
          tx.update(userRef, {status: "blocked", accountStatus: "deleted", deletionStatus: "approved",
            membershipStatus: "inactive", updatedAt: stamp});
        }
        tx.create(requestRef.collection("audit").doc(operationId), {actorUid: actor.uid, action: op.action,
          fromStatus: request.status, toStatus: next, requestRevision: request.revision, createdAt: stamp});
        tx.update(opRef, {status: processing ? "processing" : "succeeded", authorizedAt: stamp,
          ...(processing ? {} : {completedAt: stamp})});
      });
    }
    const op = (await opRef.get()).data();
    if (op?.status !== "processing") return;
    // Idempotent external effects; transient errors leave processing retryable.
    await deps.disable(uid);
    await db.recursiveDelete(db.collection(`users/${uid}/fcm_tokens`));
    await db.doc(`notification_staff/${uid}`).delete();
    await db.recursiveDelete(db.doc(`user_public_profiles/${uid}`));
    const completing = op.action === "complete";
    if (completing) await deps.deleteAuth(uid);
    await db.runTransaction(async tx => {
      const current = (await tx.get(opRef)).data();
      const request = (await tx.get(requestRef)).data();
      const userRef = db.doc(`users/${uid}`);
      const user = (await tx.get(userRef)).data();
      if (current?.status !== "processing") return;
      check(request?.status === "approved" && user, "invalid-state", "Deletion state requires operator review.");
      const stamp = FieldValue.serverTimestamp();
      tx.set(userRef, deletionProfile(uid, user, completing));
      tx.update(requestRef, {status: completing ? "completed" : "approved", updatedAt: stamp,
        processingStage: completing ? "completed" : "manual_cleanup_required",
        ...(completing ? {completionAt: stamp, reason: "", userMessage: ""} : {})});
      tx.create(requestRef.collection("audit").doc(`${operationId}_processed`), {
        actorUid: "trusted_backend", action: completing ? "deletion_completed" : "access_disabled_profile_removed",
        operationId, createdAt: stamp});
      tx.update(opRef, {status: "succeeded", completedAt: stamp,
        ...(completing ? {note: "", userMessage: ""} : {})});
    });
  } catch (error) {
    if (!(error instanceof DriverOperationError)) throw error;
    await db.runTransaction(async tx => {
      const op = (await tx.get(opRef)).data();
      // Partially executed irreversible work must remain retryable.
      if (op?.status === "processing") throw error;
      if (op?.status === "pending") tx.update(opRef, {status: "failed", errorCode: error.code,
        errorMessage: error.message, completedAt: FieldValue.serverTimestamp()});
    });
  }
}
