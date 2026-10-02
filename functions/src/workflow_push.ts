import {createHash} from "node:crypto";
import {Auth} from "firebase-admin/auth";
import {FieldPath, FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {Messaging} from "firebase-admin/messaging";
import {deliverPushRecipient, firestoreDeliveryPort, notificationPayload, PushDeliveryPort} from "./chat_push";

type Data = Record<string, unknown>;
type Audience = "owner" | "admin" | "support";
export const workflowBodies = {
  support_new_request: "A new support request needs review.",
  support_admin_reply: "You have a new support reply.",
  support_user_reply: "A support request has a new reply.",
  registration_submitted: "A new registration application is ready for review.",
  registration_correction_required: "Your registration application needs an update.",
  registration_rejected: "Your registration application has been reviewed.",
  registration_approved: "Your Ceylon Travel account has been approved.",
  registration_driver_approved: "Your driver application has been approved. Complete the remaining account steps.",
  driver_upgrade_submitted: "A driver upgrade application is ready for review.",
  driver_upgrade_correction_required: "Your driver upgrade application needs an update.",
  driver_upgrade_rejected: "Your driver upgrade application has been reviewed.",
  driver_upgrade_approved: "Your Driver/Partner upgrade was approved. Complete the remaining payment and membership steps to activate driver access.",
  identity_verified: "Your identity verification has been completed.",
  identity_action_required: "Your identity verification needs attention.",
  payment_submitted: "A driver payment is ready for review.",
  payment_verified: "Your registration payment has been verified.",
  payment_rejected: "Your registration payment needs attention.",
  membership_activated: "Your driver account is now active.",
  founding_offer_closed: "The founding driver offer has closed.",
} as const;
type Kind = keyof typeof workflowBodies;
export interface Principal {uid: string; disabled?: boolean; admin: boolean; support: boolean}
export interface WorkflowPort extends PushDeliveryPort {
  read(path: string): Promise<Data | undefined>;
  principal(uid: string): Promise<Principal | undefined>;
  staff(): AsyncIterable<string[]>;
}
export interface WorkflowEvent {
  source: "support_request" | "support_message" | "application" | "driver_operation" | "founding";
  path: string;
  data: Data;
  uid?: string;
  id: string;
  authId?: string;
}
interface Notice {type: Kind; audience: Audience; owner?: string; actor?: string; identifiers: Record<string, string>}
export const validWorkflowId = (v: unknown): v is string => typeof v === "string" &&
  v.length > 0 && Buffer.byteLength(v) <= 1500 && !v.includes("/") && v !== "." && v !== "..";
const time = (a: unknown, b: unknown): boolean => a instanceof Timestamp && b instanceof Timestamp && a.isEqual(b);
const role = (p: Principal | undefined, audience: Audience): boolean => !!p && !p.disabled &&
  (audience === "admin" ? p.admin : audience === "support" ? p.support : true);

function sourcePath(event: WorkflowEvent): string | null {
  if (!validWorkflowId(event.id)) return null;
  if (event.source === "support_request") return `support_requests/${event.id}`;
  if (event.source === "founding") return event.id === "founding_offer_closed" ? "admin_notifications/founding_offer_closed" : null;
  if (!validWorkflowId(event.uid)) return null;
  switch (event.source) {
    case "support_message": return `support_requests/${event.uid}/messages/${event.id}`;
    case "application": return `registration_applications/${event.uid}/history/${event.id}`;
    case "driver_operation": return `users/${event.uid}/driver_operations/${event.id}`;
    default: return null;
  }
}

/** The staff index is candidate discovery only. Live Auth claims always authorize. */
export async function syncNotificationStaff(db: Firestore, auth: Auth, uid: string): Promise<void> {
  if (!validWorkflowId(uid)) return;
  const p = await authPrincipal(auth, uid);
  const ref = db.doc(`notification_staff/${uid}`);
  if (p && !p.disabled && (p.admin || p.support)) {
    await ref.set({updatedAt: FieldValue.serverTimestamp()});
  } else await ref.delete();
}
async function authPrincipal(auth: Auth, uid: string): Promise<Principal | undefined> {
  try {
    const p = await auth.getUser(uid);
    return {uid: p.uid, disabled: p.disabled, admin: p.customClaims?.admin === true,
      support: p.customClaims?.supportAdmin === true};
  } catch (error) {
    if ((error as {code?: string}).code === "auth/user-not-found") return undefined;
    throw error;
  }
}

export async function workflowNotice(port: WorkflowPort, event: WorkflowEvent): Promise<Notice | null> {
  const d = event.data;
  const expectedPath = sourcePath(event);
  if (!expectedPath || event.path !== expectedPath || !d || typeof d !== "object" || Array.isArray(d)) return null;
  const current = await port.read(event.path);
  if (!current) return null;
  if (event.source === "support_request" || event.source === "support_message") {
    const requestId = event.source === "support_request" ? event.id : event.uid;
    if (!validWorkflowId(requestId)) return null;
    const request = event.source === "support_request" ? current : await port.read(`support_requests/${requestId}`);
    if (!request || request.id !== requestId || !validWorkflowId(request.userId) ||
        !(request.createdAt instanceof Timestamp)) return null;
    if (event.source === "support_request") {
      if (event.authId !== request.userId || d.userId !== request.userId || !time(d.createdAt, request.createdAt)) return null;
      return {type: "support_new_request", audience: "support", owner: request.userId, actor: request.userId,
        identifiers: {supportRequestId: requestId}};
    }
    // Original request is on the parent. Ignore acknowledgements/system roles.
    if (d.id !== event.id || current.id !== event.id || !validWorkflowId(d.senderId) ||
        event.authId !== d.senderId || current.senderId !== d.senderId || current.senderRole !== d.senderRole ||
        !time(current.createdAt, d.createdAt) || typeof current.message !== "string" || !current.message.trim() || current.message.length > 4000) return null;
    const sender = await port.principal(d.senderId);
    if (!sender || sender.uid !== d.senderId || sender.disabled) return null;
    if (d.senderRole === "user" && d.senderId === request.userId) {
      return {type: "support_user_reply", audience: "support", owner: request.userId, actor: d.senderId,
        identifiers: {supportRequestId: requestId}};
    }
    if (d.senderRole === "admin" && sender.support && d.senderId !== request.userId) {
      return {type: "support_admin_reply", audience: "owner", owner: request.userId, actor: d.senderId,
        identifiers: {supportRequestId: requestId}};
    }
    return null;
  }
  if (event.source === "founding") {
    if (event.id !== "founding_offer_closed" || current.type !== event.id || d.type !== event.id ||
        current.registrationNumber !== 100 || d.registrationNumber !== 100 ||
        !time(current.createdAt, d.createdAt)) return null;
    return {type: "founding_offer_closed", audience: "admin", identifiers: {eventId: event.id}};
  }
  if (!validWorkflowId(event.uid)) return null;
  const uid = event.uid;
  const user = await port.read(`users/${uid}`);
  if (!user || !["tourist", "driver"].includes(String(user.accountType))) return null;
  if (event.source === "application") {
    if (current.operationId !== event.id || d.operationId !== event.id || !time(current.createdAt, d.createdAt) ||
        current.actorUid !== d.actorUid || current.action !== d.action || current.newValue !== d.newValue ||
        !validWorkflowId(current.actorUid) || !Number.isSafeInteger(current.applicationRevision) ||
        (current.applicationRevision as number) < 1 || current.applicationRevision !== user.applicationRevision ||
        d.applicationRevision !== current.applicationRevision) return null;
    const app = await port.read(`registration_applications/${uid}`);
    if (!app || app.uid !== uid || app.applicationRevision !== user.applicationRevision) return null;
    if (app.purpose === "driver_upgrade") {
      const state = String(current.newValue);
      const states: Record<string, Kind> = {pending_review: "driver_upgrade_submitted",
        correction_required: "driver_upgrade_correction_required", rejected: "driver_upgrade_rejected", approved: "driver_upgrade_approved"};
      if (!Object.hasOwn(states, state) || current.purpose !== "driver_upgrade" || d.purpose !== current.purpose ||
          app.targetAccountType !== "driver" || app.accountType !== "tourist" || user.uid !== uid ||
          user.driverUpgradeStatus !== state || app.registrationStatus !== state ||
          (state === "approved" && user.registrationStatus !== "approved") ||
          user.accountType !== (state === "approved" ? "driver" : "tourist")) return null;
      const submitted = state === "pending_review";
      if (current.action !== (submitted ? "driver_upgrade_submitted" : `driver_upgrade_${state}`)) return null;
      if (submitted) {
        if (current.actorUid !== uid || app.operationId !== event.id || !time(app.submittedAt, current.createdAt)) return null;
      } else if (app.reviewedBy !== current.actorUid || !time(app.reviewedAt, current.createdAt) ||
          !role(await port.principal(current.actorUid), "admin")) return null;
      return {type: states[state], audience: submitted ? "admin" : "owner", owner: uid, actor: current.actorUid,
        identifiers: {accountUid: uid}};
    }
    if ((app.purpose != null && app.purpose !== "registration") || current.newValue !== user.registrationStatus ||
        app.registrationStatus !== user.registrationStatus) return null;
    const submitted = current.action === "application_submitted";
    const states: Record<string, Kind> = {correction_required: "registration_correction_required",
      rejected: "registration_rejected", approved: user.accountType === "driver" ? "registration_driver_approved" : "registration_approved"};
    if (submitted) {
      if (current.actorUid !== uid || current.newValue !== "pending_review" || !time(app.submittedAt, current.createdAt)) return null;
      return {type: "registration_submitted", audience: "admin", owner: uid, actor: uid, identifiers: {accountUid: uid}};
    }
    const state = String(current.newValue);
    if (!Object.hasOwn(states, state)) return null;
    const type = states[state];
    if (current.action !== `application_${current.newValue}` ||
        !role(await port.principal(current.actorUid), "admin") || !time(app.reviewedAt, current.createdAt)) return null;
    return {type, audience: "owner", owner: uid, actor: current.actorUid, identifiers: {accountUid: uid}};
  }
  // Successful trusted operations only, never a client's pending command.
  if (user.accountType !== "driver" || current.status !== "succeeded" || d.status !== "succeeded" ||
      current.action !== d.action || current.actorUid !== d.actorUid || current.expectedRevision !== d.expectedRevision ||
      !time(current.completedAt, d.completedAt) || !validWorkflowId(current.actorUid) ||
      !Number.isSafeInteger(current.expectedRevision) || (current.expectedRevision as number) < 0 ||
      user.driverAdminRevision !== (current.expectedRevision as number) + 1) return null;
  const action = current.action;
  const ownerAction = action === "submit_payment";
  if (ownerAction ? current.actorUid !== uid : !role(await port.principal(current.actorUid), "admin")) return null;
  const identifiers: Record<string, string> = {accountUid: uid};
  const base = {audience: "owner" as Audience, owner: uid, actor: current.actorUid, identifiers};
  if (action === "verify_identity" || action === "reject_identity") {
    const verified = action === "verify_identity";
    const verification = await port.read(`driver_verifications/${uid}`);
    if (!verification || verification.identityVerificationStatus !== (verified ? "verified" : "rejected") ||
        user.identityVerificationStatus !== verification.identityVerificationStatus || !time(verification.reviewedAt, current.completedAt)) return null;
    return {...base, type: verified ? "identity_verified" : "identity_action_required"};
  }
  if (["submit_payment", "verify_payment", "reject_payment"].includes(String(action))) {
    const payload = current.payload as Data | undefined;
    if (!payload || !validWorkflowId(payload.paymentId) || user.currentRegistrationPaymentId !== payload.paymentId) return null;
    const payment = await port.read(`users/${uid}/payments/${payload.paymentId}`);
    const status = action === "submit_payment" ? "pending" : action === "verify_payment" ? "verified" : "rejected";
    if (!payment || payment.paymentType !== "registration" || payment.status !== status || payment.claimSubmitted !== true ||
        user.paymentStatus !== status || !time(payment.updatedAt, current.completedAt)) return null;
    identifiers.paymentId = payload.paymentId;
    return {...base, type: action === "submit_payment" ? "payment_submitted" :
      action === "verify_payment" ? "payment_verified" : "payment_rejected", audience: ownerAction ? "admin" : "owner"};
  }
  if (action === "activate_membership") {
    if ((current.result as Data | undefined)?.alreadyActivated === true) return null;
    if (user.status !== "active" || user.membershipStatus !== "active" || user.accountStatus !== "active" || user.identityVerificationStatus !== "verified" ||
        user.paymentStatus !== "verified" || (user.registrationStatus != null && user.registrationStatus !== "approved") ||
        !time(user.membershipActivatedAt, current.completedAt) ||
        !["founding_lifetime", "standard_annual"].includes(String(user.membershipPlan)) ||
        (user.membershipPlan === "standard_annual" && (!(user.membershipValidUntil instanceof Timestamp) || user.membershipValidUntil.toMillis() <= Date.now()))) return null;
    return {...base, type: "membership_activated"};
  }
  return null;
}

export async function deliverWorkflowPush(port: WorkflowPort, event: WorkflowEvent): Promise<string> {
  try {
    const notice = await workflowNotice(port, event);
    if (!notice || !await port.claim()) return "ignored";
    let failed = false;
    const seen = new Set<string>();
    async function* candidates(): AsyncIterable<string[]> {
      if (notice!.audience === "owner") yield [notice!.owner!];
      else yield* port.staff();
    }
    for await (const page of candidates()) for (const uid of page) {
      if (seen.has(uid) || uid === notice.actor || (notice.audience !== "owner" && uid === notice.owner)) continue;
      seen.add(uid);
      const eligible = async () => {
        const fresh = await workflowNotice(port, event);
        const principal = await port.principal(uid);
        return fresh !== null && fresh.type === notice.type && fresh.owner === notice.owner &&
          principal?.uid === uid && role(principal, notice.audience) && (notice.audience !== "owner" || uid === notice.owner);
      };
      if (!await eligible()) continue;
      const result = await deliverPushRecipient(port, uid, eligible,
        tokens => notificationPayload(notice.type, notice.identifiers, workflowBodies[notice.type], tokens));
      if (result === "failed") failed = true;
    }
    return failed ? "failed" : "attempted";
  } catch (_) { return "failed"; }
}

export function firestoreWorkflowPort(db: Firestore, auth: Auth, messaging: Messaging, event: WorkflowEvent,
  commitKey: string): WorkflowPort {
  const key = createHash("sha256").update(event.source === "founding" ? "founding_offer_closed" : `${event.path}:${commitKey}`).digest("hex");
  return {...firestoreDeliveryPort(db, messaging, db.doc(`workflow_push_delivery/${key}`)),
    read: async path => (await db.doc(path).get()).data(),
    principal: uid => authPrincipal(auth, uid),
    async *staff() {
      let cursor: string | undefined;
      while (true) {
        let query = db.collection("notification_staff").orderBy(FieldPath.documentId()).limit(500);
        if (cursor) query = query.startAfter(cursor);
        const page = await query.get();
        yield page.docs.map(doc => doc.id);
        if (page.size < 500) return;
        cursor = page.docs[page.size - 1].id;
      }
    },
  };
}
