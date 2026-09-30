import {strict as assert} from "node:assert";
import {test} from "node:test";
import {Auth} from "firebase-admin/auth";
import {Firestore, Timestamp} from "firebase-admin/firestore";
import {Messaging, MulticastMessage} from "firebase-admin/messaging";
import {deliverWorkflowPush, firestoreWorkflowPort, Principal, syncNotificationStaff,
  WorkflowEvent, WorkflowPort, workflowBodies, workflowNotice} from "../src/workflow_push";

type Data = Record<string, unknown>;
const stamp = Timestamp.fromMillis(1000);
const people: Record<string, Principal> = {
  owner: {uid: "owner", admin: false, support: false},
  admin: {uid: "admin", admin: true, support: true},
  primary: {uid: "primary", admin: true, support: false},
  support: {uid: "support", admin: false, support: true},
  unrelated: {uid: "unrelated", admin: false, support: false},
  disabled: {uid: "disabled", admin: true, support: true, disabled: true},
};
function fixture(event: WorkflowEvent, extra: Record<string, Data> = {}) {
  const docs: Record<string, Data> = {[event.path]: {...event.data}, ...extra};
  const principals = {...people};
  const sent: MulticastMessage[] = [], recipients: string[] = [], removed: string[] = [];
  let claimed = false;
  const port: WorkflowPort = {
    read: async path => docs[path], principal: async uid => principals[uid],
    async *staff() { yield ["admin", "support", "primary", "owner", "unrelated", "disabled"]; },
    claim: async () => { if (claimed) return false; claimed = true; return true; },
    async *tokens(uid) { recipients.push(uid); yield [{id: "one", token: `${uid}-1`}, {id: "two", token: `${uid}-2`}]; },
    send: async payload => { sent.push(payload); return {responses: payload.tokens.map(() => ({success: true}))}; },
    removeIfUnchanged: async (uid, token) => { removed.push(`${uid}/${token.id}`); },
  };
  return {port, docs, principals, sent, recipients, removed};
}
const request: Data = {id: "r", userId: "owner", createdAt: stamp, message: "SECRET complaint", contactNumber: "SECRET phone"};
const newRequest: WorkflowEvent = {source: "support_request", id: "r", path: "support_requests/r", data: request, authId: "owner"};
function reply(sender: string, senderRole: string): WorkflowEvent {
  return {source: "support_message", uid: "r", id: "m", path: "support_requests/r/messages/m", authId: sender,
    data: {id: "m", senderId: sender, senderRole, createdAt: stamp, message: "SECRET reply"}};
}
function application(state: string, driver = false) {
  const event: WorkflowEvent = {source: "application", uid: "owner", id: "op", path: "registration_applications/owner/history/op",
    data: {operationId: "op", actorUid: state === "pending_review" ? "owner" : "admin", applicationRevision: 2,
      action: state === "pending_review" ? "application_submitted" : `application_${state}`, newValue: state,
      createdAt: stamp, reason: "SECRET rejection"}};
  const f = fixture(event, {
    "users/owner": {accountType: driver ? "driver" : "tourist", applicationRevision: 2, registrationStatus: state},
    "registration_applications/owner": {uid: "owner", applicationRevision: 2, registrationStatus: state,
      submittedAt: stamp, reviewedAt: stamp, nicNumber: "SECRET NIC", evidence: "SECRET path"},
  });
  return {...f, event};
}
function operation(action: string) {
  const event: WorkflowEvent = {source: "driver_operation", uid: "owner", id: "op", path: "users/owner/driver_operations/op",
    data: {action, status: "succeeded", expectedRevision: 0, completedAt: stamp,
      actorUid: action === "submit_payment" ? "owner" : "admin", payload: {paymentId: "p"}}};
  const status = action === "reject_payment" ? "rejected" : action === "submit_payment" ? "pending" : "verified";
  const identity = action === "reject_identity" ? "rejected" : "verified";
  const f = fixture(event, {
    "users/owner": {status: "active", accountType: "driver", driverAdminRevision: 1, currentRegistrationPaymentId: "p",
      paymentStatus: status, identityVerificationStatus: identity, membershipStatus: "active", membershipPlan: "founding_lifetime",
      membershipActivatedAt: stamp, accountStatus: "active", registrationStatus: "approved"},
    "driver_verifications/owner": {identityVerificationStatus: identity, reviewedAt: stamp, nicNumber: "SECRET NIC"},
    "users/owner/payments/p": {paymentType: "registration", status, claimSubmitted: true, updatedAt: stamp,
      paymentReference: "SECRET reference", claimedAmountLkr: 3500, slipPath: "SECRET image", bankTransactionReference: "SECRET bank"},
  });
  if (action === "verify_identity" || action === "reject_identity") delete f.docs["users/owner"].registrationStatus;
  return {...f, event};
}

test("new support request targets support-eligible admins, never submitting or normal users", async () => {
  const f = fixture(newRequest);
  await deliverWorkflowPush(f.port, newRequest);
  assert.deepEqual(f.recipients, ["admin", "support"]);
  assert.deepEqual(f.sent[0].data, {type: "support_new_request", supportRequestId: "r"});
  assert.equal(f.sent[0].tokens.length, 2);
});
test("staff reply targets owner only; user reply targets support staff only", async () => {
  for (const [sender, role, recipients] of [["admin", "admin", ["owner"]], ["support", "admin", ["owner"]],
    ["owner", "user", ["admin", "support"]]] as [string, string, string[]][]) {
    const event = reply(sender, role), f = fixture(event, {"support_requests/r": request});
    await deliverWorkflowPush(f.port, event);
    assert.deepEqual(f.recipients, recipients);
    assert.doesNotMatch(JSON.stringify(f.sent), /SECRET/);
  }
});
test("acknowledgement/system, forged role/owner and mismatched authenticated sender no-op", async () => {
  for (const event of [reply("admin", "system"), reply("unrelated", "admin"), reply("primary", "admin"),
    reply("unrelated", "user"), {...reply("admin", "admin"), authId: "unrelated"},
    {...newRequest, authId: "unrelated"}, {...newRequest, authId: undefined}]) {
    const f = fixture(event, event.source === "support_message" ? {"support_requests/r": request} : {});
    assert.equal(await deliverWorkflowPush(f.port, event), "ignored");
    assert.deepEqual(f.sent, []);
  }
});
for (const driver of [false, true]) for (const state of ["pending_review", "correction_required", "rejected", "approved"]) {
  test(`${driver ? "driver" : "tourist"} application ${state} uses correct audience and private wording`, async () => {
    const f = application(state, driver);
    await deliverWorkflowPush(f.port, f.event);
    assert.deepEqual(f.recipients, state === "pending_review" ? ["admin", "primary"] : ["owner"]);
    assert.doesNotMatch(JSON.stringify(f.sent), /SECRET|evidence|nicNumber|reason/);
    if (state === "approved" && driver) {
      assert.equal(f.sent[0].data?.type, "registration_driver_approved");
      assert.match(f.sent[0].notification?.body ?? "", /remaining account steps/);
      assert.doesNotMatch(f.sent[0].notification?.body ?? "", /now active/);
    }
  });
}
for (const [action, type] of [
  ["verify_identity", "identity_verified"], ["reject_identity", "identity_action_required"],
  ["submit_payment", "payment_submitted"], ["verify_payment", "payment_verified"],
  ["reject_payment", "payment_rejected"], ["activate_membership", "membership_activated"],
]) {
  test(`${action} notifies only intended owner/reviewers`, async () => {
    const f = operation(action);
    await deliverWorkflowPush(f.port, f.event);
    assert.deepEqual(f.recipients, action === "submit_payment" ? ["admin", "primary"] : ["owner"]);
    assert.equal(f.sent[0].data?.type, type);
    assert.doesNotMatch(JSON.stringify(f.sent), /SECRET|3500|bank|slipPath|nicNumber/);
    if (type.startsWith("payment_")) assert.equal(f.sent[0].data?.paymentId, "p");
  });
}
test("quotes, pending/failed commands, duplicate activation and obsolete revisions do not notify", async () => {
  const quote = operation("request_payment");
  assert.equal(await deliverWorkflowPush(quote.port, quote.event), "ignored");
  for (const status of ["pending", "failed"]) {
    const f = operation("verify_payment"); f.docs[f.event.path].status = status;
    assert.equal(await deliverWorkflowPush(f.port, f.event), "ignored");
  }
  const stale = operation("activate_membership"); stale.docs["users/owner"].driverAdminRevision = 2;
  assert.equal(await deliverWorkflowPush(stale.port, stale.event), "ignored");
  const inactive = operation("activate_membership"); inactive.docs["users/owner"].accountStatus = "suspended";
  assert.equal(await deliverWorkflowPush(inactive.port, inactive.event), "ignored");
  const duplicate = operation("activate_membership");
  duplicate.docs[duplicate.event.path].result = {alreadyActivated: true};
  assert.equal(await deliverWorkflowPush(duplicate.port, duplicate.event), "ignored");
});

test("annual membership notices require an unexpired current entitlement", async () => {
  const f = operation("activate_membership");
  f.docs["users/owner"].membershipPlan = "standard_annual";
  f.docs["users/owner"].membershipValidUntil = Timestamp.fromMillis(Date.now() + 86400000);
  assert.equal((await workflowNotice(f.port, f.event))?.type, "membership_activated");
  f.docs["users/owner"].membershipValidUntil = Timestamp.fromMillis(1);
  assert.equal(await workflowNotice(f.port, f.event), null);
});

test("wrong source owner/path and malformed application states are ignored", async () => {
  const f = application("approved");
  assert.equal(await deliverWorkflowPush(f.port, {...f.event, uid: "unrelated"}), "ignored");
  const malformed = application("toString");
  assert.equal(await deliverWorkflowPush(malformed.port, malformed.event), "ignored");
  malformed.docs[malformed.event.path].applicationRevision = undefined;
  assert.equal(await deliverWorkflowPush(malformed.port, malformed.event), "ignored");
});
test("admin/support-only cannot forge application/payment reviewer roles", async () => {
  const f = application("approved"); f.docs[f.event.path].actorUid = "support";
  assert.equal(await deliverWorkflowPush(f.port, f.event), "ignored");
  const p = operation("verify_payment"); p.docs[p.event.path].actorUid = "owner";
  assert.equal(await deliverWorkflowPush(p.port, p.event), "ignored");
});
test("missing/malformed/current owner changes suppress delivery", async () => {
  const f = fixture(newRequest); delete f.docs[newRequest.path];
  assert.equal(await deliverWorkflowPush(f.port, newRequest), "ignored");
  f.docs[newRequest.path] = {...request, userId: "unrelated"};
  assert.equal(await deliverWorkflowPush(f.port, newRequest), "ignored");
  f.docs[newRequest.path] = {...request, createdAt: null};
  assert.equal(await deliverWorkflowPush(f.port, newRequest), "ignored");
  const app = application("approved"); app.docs["users/owner"].applicationRevision = 3;
  assert.equal(await deliverWorkflowPush(app.port, app.event), "ignored");
});
test("claim revocation between token loading and sending blocks staff delivery", async () => {
  const f = fixture(newRequest);
  f.port.tokens = async function* (uid) {
    f.principals[uid] = {uid, admin: false, support: false};
    yield [{id: "one", token: "revoked-token"}];
  };
  await deliverWorkflowPush(f.port, newRequest);
  assert.deepEqual(f.sent, []);
});
test("duplicate trigger attempts, multiple devices, fixed privacy payload and no loops", async () => {
  const f = operation("verify_payment");
  await Promise.all([deliverWorkflowPush(f.port, f.event), deliverWorkflowPush(f.port, f.event)]);
  assert.equal(f.sent.length, 1); assert.equal(f.sent[0].tokens.length, 2);
  assert.deepEqual(f.sent[0].data, {type: "payment_verified", accountUid: "owner", paymentId: "p"});
  assert.equal(f.sent[0].notification?.body, workflowBodies.payment_verified);
  assert.equal(await deliverWorkflowPush(f.port, f.event), "ignored");
});
test("permanently invalid cleanup only; temporary failure does not remove tokens", async () => {
  const f = operation("verify_payment");
  f.port.send = async () => ({responses: [
    {success: false, error: {code: "messaging/registration-token-not-registered"}},
    {success: false, error: {code: "messaging/server-unavailable"}},
  ]});
  assert.equal(await deliverWorkflowPush(f.port, f.event), "failed");
  assert.deepEqual(f.removed, ["owner/one"]);
});
test("FCM failure leaves durable source records unchanged", async () => {
  const f = operation("reject_payment"), before = JSON.stringify(f.docs);
  f.port.send = async () => { throw new Error("network"); };
  assert.equal(await deliverWorkflowPush(f.port, f.event), "failed");
  assert.equal(JSON.stringify(f.docs), before); assert.deepEqual(f.removed, []);
});
test("single existing founding closure event targets primary admins once", async () => {
  const event: WorkflowEvent = {source: "founding", id: "founding_offer_closed", path: "admin_notifications/founding_offer_closed",
    data: {type: "founding_offer_closed", registrationNumber: 100, createdAt: stamp, message: "SECRET price"}};
  const f = fixture(event);
  await Promise.all([deliverWorkflowPush(f.port, event), deliverWorkflowPush(f.port, event)]);
  assert.deepEqual(f.recipients, ["admin", "primary"]);
  assert.doesNotMatch(JSON.stringify(f.sent), /SECRET|price|100/);
  assert.equal((await workflowNotice(f.port, event))?.type, "founding_offer_closed");
  const paths: string[] = [];
  const db = {doc: (path: string) => { paths.push(path); return {}; }} as unknown as Firestore;
  firestoreWorkflowPort(db, {} as Auth, {} as Messaging, event, "first-commit");
  firestoreWorkflowPort(db, {} as Auth, {} as Messaging, event, "redelivery");
  assert.equal(paths[0], paths[1]);
  assert.match(paths[0], /^workflow_push_delivery\/[a-f0-9]{64}$/);
});
test("staff candidate registry comes only from Auth claims, not profile fields", async () => {
  const writes: string[] = [];
  const db = {doc: (path: string) => ({set: async (data: Data) => {
    assert.deepEqual(Object.keys(data), ["updatedAt"]); writes.push(`set:${path}`);
  }, delete: async () => { writes.push(`delete:${path}`); }})} as unknown as Firestore;
  const auth = {getUser: async (uid: string) => ({uid, disabled: false,
    customClaims: uid === "admin" ? {admin: true} : {}})} as unknown as Auth;
  await syncNotificationStaff(db, auth, "admin");
  await syncNotificationStaff(db, auth, "owner");
  assert.deepEqual(writes, ["set:notification_staff/admin", "delete:notification_staff/owner"]);
});
