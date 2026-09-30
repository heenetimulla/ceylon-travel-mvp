import {strict as assert} from "node:assert";
import {test} from "node:test";
import {Firestore, Timestamp} from "firebase-admin/firestore";
import {Messaging, MulticastMessage} from "firebase-admin/messaging";
import {ChatPushPort, chatPushPayload, chatRecipient, deliverChatPush, firestoreChatPushPort, invalidToken, PushToken} from "../src/chat_push";

const trip = {creatorId: "creator", acceptedDriverId: "driver", acceptedBidId: "bid", status: "accepted"};
const message = {id: "m", tripId: "t", senderId: "creator", senderRole: "creator", assignmentDriverId: "driver",
  createdAt: Timestamp.fromMillis(1000), messageType: "text", text: "PRIVATE MESSAGE", latitude: null, longitude: null};

function fixture() {
  const sent: MulticastMessage[] = [];
  const removed: PushToken[] = [];
  let current: Record<string, unknown> | undefined = {...trip};
  let claimed = false;
  const port: ChatPushPort = {
    loadTrip: async () => current,
    claim: async () => { if (claimed) return false; claimed = true; return true; },
    async *tokens(uid) {
      assert.notEqual(uid, message.senderId);
      assert.equal(uid, "driver");
      yield [{id: "one", token: "token-1"}, {id: "two", token: "token-2"}];
    },
    send: async payload => { sent.push(payload); return {responses: payload.tokens.map(() => ({success: true}))}; },
    removeIfUnchanged: async (_, device) => { removed.push(device); },
  };
  return {port, sent, removed, setTrip: (next: typeof current) => { current = next; }};
}

test("creator message targets current driver only; driver message targets creator only", () => {
  assert.equal(chatRecipient("t", "m", trip, message), "driver");
  assert.equal(chatRecipient("t", "m", trip, {...message, senderId: "driver", senderRole: "driver"}), "creator");
});

test("old/replaced driver, unrelated sender and forged role are ignored", () => {
  assert.equal(chatRecipient("t", "m", {...trip, acceptedDriverId: "replacement"}, message), null);
  assert.equal(chatRecipient("t", "m", trip, {...message, senderId: "unrelated"}), null);
  assert.equal(chatRecipient("t", "m", trip, {...message, senderRole: "driver"}), null);
  assert.equal(chatRecipient("t", "m", {...trip, status: "open", acceptedDriverId: null}, message), null);
});

test("missing trip and malformed message no-op before claiming or sending", async () => {
  for (const bad of [undefined, {}, {...message, id: "wrong"}, {...message, tripId: "wrong"},
    {...message, createdAt: null}, {...message, text: ""}, {...message, messageType: "unknown"},
    {...message, messageType: "location", text: null, latitude: NaN, longitude: 1}]) {
    const f = fixture();
    assert.equal(await deliverChatPush(f.port, "t", "m", bad), "ignored");
    assert.equal(f.sent.length, 0);
  }
  const f = fixture(); f.setTrip(undefined);
  assert.equal(await deliverChatPush(f.port, "t", "m", message), "ignored");
});

test("multiple devices receive a privacy-only payload and trigger retry does not duplicate", async () => {
  const f = fixture();
  assert.equal(await deliverChatPush(f.port, "t", "m", message), "attempted");
  assert.deepEqual(f.sent[0].tokens, ["token-1", "token-2"]);
  assert.deepEqual(f.sent[0].data, {type: "trip_chat", tripId: "t"});
  assert.deepEqual(f.sent[0].notification, {title: "Ceylon Travel", body: "You have a new trip message"});
  assert.doesNotMatch(JSON.stringify(f.sent), /PRIVATE MESSAGE|creator|assignmentDriverId|latitude/);
  assert.equal(await deliverChatPush(f.port, "t", "m", message), "ignored");
  assert.equal(f.sent.length, 1);
});

test("driver message delivery never enumerates sender devices", async () => {
  const f = fixture();
  f.port.tokens = async function* (uid) {
    assert.equal(uid, "creator");
    yield [{id: "creator-phone", token: "creator-token"}];
  };
  await deliverChatPush(f.port, "t", "m", {...message, senderId: "driver", senderRole: "driver"});
  assert.deepEqual(f.sent[0].tokens, ["creator-token"]);
});

test("assignment is revalidated after loading tokens, including between pages", async () => {
  const f = fixture();
  f.port.tokens = async function* () {
    f.setTrip({...trip, acceptedDriverId: "replacement"});
    yield [{id: "old", token: "old-driver-token"}];
  };
  assert.equal(await deliverChatPush(f.port, "t", "m", message), "ignored");
  assert.equal(f.sent.length, 0);
});

test("only permanently invalid/unregistered tokens are cleaned up", async () => {
  const f = fixture();
  f.port.send = async () => ({responses: [
    {success: false, error: {code: "messaging/registration-token-not-registered"}},
    {success: false, error: {code: "messaging/server-unavailable"}},
  ]});
  await deliverChatPush(f.port, "t", "m", message);
  assert.deepEqual(f.removed, [{id: "one", token: "token-1"}]);
  assert.equal(invalidToken("messaging/invalid-registration-token"), true);
  assert.equal(invalidToken("messaging/invalid-argument"), false);
});

test("FCM failure is contained; original chat message is unchanged", async () => {
  const f = fixture();
  const original = {...message};
  f.port.send = async () => { throw new Error("transport failure"); };
  assert.equal(await deliverChatPush(f.port, "t", "m", message), "failed");
  assert.deepEqual(message, original);
  assert.deepEqual(f.removed, []);
  assert.equal(await deliverChatPush(f.port, "t", "m", message), "ignored");
});

test("location messages use the same generic content and channel", () => {
  assert.equal(chatRecipient("t", "m", trip, {...message, messageType: "location", text: null,
    latitude: 7, longitude: 80}), "driver");
  const payload = chatPushPayload("t", ["token"]);
  assert.equal(payload.android?.notification?.channelId, "ceylon_travel_trip_chat");
  assert.equal(payload.android?.notification?.sound, "default");
  assert.equal(payload.android?.ttl, 300000);
});

test("cleanup transaction preserves a token refreshed while FCM was sending", async () => {
  const records: Record<string, {token: string}> = {"users/driver/fcm_tokens/one": {token: "replacement"}};
  const deleted: string[] = [];
  const collection = (path: string): any => ({doc: (key: string) => ({path: `${path}/${key}`,
    collection: (name: string) => collection(`${path}/${key}/${name}`)})});
  const db = {collection, runTransaction: async (body: any) => body({
    get: async (ref: any) => ({data: () => records[ref.path]}),
    delete: (ref: any) => { deleted.push(ref.path); delete records[ref.path]; },
  })} as unknown as Firestore;
  const port = firestoreChatPushPort(db, {} as Messaging, "t", "m");
  await port.removeIfUnchanged("driver", {id: "one", token: "obsolete"});
  assert.deepEqual(deleted, []);
  await port.removeIfUnchanged("driver", {id: "one", token: "replacement"});
  assert.deepEqual(deleted, ["users/driver/fcm_tokens/one"]);
});

test("concurrent duplicate event attempts send only once", async () => {
  const f = fixture();
  await Promise.all([deliverChatPush(f.port, "t", "m", message), deliverChatPush(f.port, "t", "m", message)]);
  assert.equal(f.sent.length, 1);
});
