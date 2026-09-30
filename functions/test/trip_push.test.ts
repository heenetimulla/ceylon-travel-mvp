import {strict as assert} from "node:assert";
import {test} from "node:test";
import {Firestore, Timestamp} from "firebase-admin/firestore";
import {Messaging, MulticastMessage} from "firebase-admin/messaging";
import {bidCreatedEvent, deliverTripPush, firestoreTripPushPort, TripPushEvent, TripPushPort, tripPushBodies,
  tripPushRecipients, tripTransitionEvent} from "../src/trip_push";

const time = Timestamp.fromMillis(1000);
const assigned = {creatorId: "creator", acceptedDriverId: "driver", acceptedBidId: "driver",
  status: "accepted", updatedAt: time};
const bid = {id: "driver", tripId: "t", driverId: "driver", status: "submitted",
  createdAt: time, priceAmount: 5000, message: "PRIVATE", driverName: "PRIVATE", phone: "PRIVATE"};
type Data = Record<string, unknown>;

function fixture(event: TripPushEvent) {
  let current: Data | undefined = event.type === "new_bid"
    ? {creatorId: "creator", status: "open", acceptedDriverId: null, acceptedBidId: null}
    : {...event.after};
  let currentBid: Data | undefined = {...bid, status: event.type === "new_bid" ? "submitted" :
    event.type === "trip_cancelled" ? "trip_cancelled" : event.type === "trip_reopened" ? "cancelled" : "accepted"};
  let history: Data | undefined = {tripId: "t", previousStatus: "accepted", resultingStatus: event.after.status,
    cancelledByUid: event.after.lastCancellationBy,
    cancelledByRole: event.type === "trip_cancelled" ? "creator" : "driver", cancelledAt: time};
  let claimed = false;
  const sent: MulticastMessage[] = [];
  const recipients: string[] = [];
  const removed: string[] = [];
  const port: TripPushPort = {
    loadTrip: async () => current,
    loadBid: async () => currentBid,
    loadCancellation: async () => history,
    claim: async () => { if (claimed) return false; claimed = true; return true; },
    async *tokens(uid) {
      recipients.push(uid);
      yield [{id: "a", token: `${uid}-a`}, {id: "b", token: `${uid}-b`}];
    },
    send: async payload => { sent.push(payload); return {responses: payload.tokens.map(() => ({success: true}))}; },
    removeIfUnchanged: async (uid, token) => { removed.push(`${uid}/${token.id}`); },
  };
  return {port, sent, recipients, removed, setTrip: (t?: Data) => { current = t; },
    setBid: (b?: Data) => { currentBid = b; }, setHistory: (h?: Data) => { history = h; }};
}
function transition(from: string, to: string, extra: Data = {}): TripPushEvent {
  const cancellation = to === "open" || to === "cancelled";
  const result = tripTransitionEvent({...assigned, status: from}, {...assigned, status: to,
    ...(cancellation ? {acceptedDriverId: null, acceptedBidId: null, lastCancellationAt: time,
      lastCancellationBy: to === "open" ? "driver" : "creator"} : {}), ...extra});
  assert.ok(result);
  return result;
}

test("new bid notifies creator only, never bidder, unrelated or parent partner driverId", async () => {
  const event = bidCreatedEvent("t", "driver", bid)!;
  const f = fixture(event);
  f.setTrip({creatorId: "creator", driverId: "partner", status: "open"});
  await deliverTripPush(f.port, "t", event);
  assert.deepEqual(f.recipients, ["creator"]);
  assert.deepEqual(f.sent[0].tokens, ["creator-a", "creator-b"]);
});

for (const [from, to, extra, expected] of [
  ["open", "accepted", {}, ["driver"]],
  ["accepted", "start_requested", {}, ["creator"]],
  ["start_requested", "in_progress", {startMethod: "creator_confirmed"}, ["driver"]],
  ["start_requested", "in_progress", {startMethod: "auto_started"}, ["creator", "driver"]],
  ["in_progress", "end_requested", {}, ["creator"]],
  ["end_requested", "completed", {completionMethod: "creator_confirmed"}, ["driver"]],
  ["end_requested", "completed", {completionMethod: "auto_completed"}, ["creator", "driver"]],
  ["accepted", "cancelled", {}, ["driver"]],
  ["accepted", "open", {}, ["creator"]],
] as [string, string, Data, string[]][]) {
  test(`${from} -> ${to} ${JSON.stringify(extra)} targets only authorized participants`, async () => {
    const event = transition(from, to, extra);
    const f = fixture(event);
    await deliverTripPush(f.port, "t", event);
    assert.deepEqual(f.recipients, expected);
    for (const payload of f.sent) {
      assert.deepEqual(payload.data, {type: event.type, tripId: "t"});
      assert.deepEqual(payload.notification, {title: "Ceylon Travel", body: tripPushBodies[event.type]});
      assert.doesNotMatch(JSON.stringify(payload), /PRIVATE|5000|phone|driverName|priceAmount/);
      assert.equal(payload.android?.notification?.channelId, "ceylon_travel_trip_chat");
    }
  });
}

test("accepted bid excludes losing/replaced driver and stale commit", async () => {
  const event = transition("open", "accepted");
  for (const changed of [undefined, {...event.after, acceptedDriverId: "replacement", acceptedBidId: "replacement"},
    {...event.after, updatedAt: Timestamp.fromMillis(2000)}, {...event.after, creatorId: "unrelated"}]) {
    const f = fixture(event); f.setTrip(changed);
    assert.equal(await deliverTripPush(f.port, "t", event), "ignored");
    assert.deepEqual(f.sent, []);
  }
});

test("reassignment after token loading stops delivery and later device pages", async () => {
  const event = transition("open", "accepted");
  const f = fixture(event);
  f.port.tokens = async function* () {
    yield [{id: "first", token: "first"}];
    f.setTrip({...event.after, acceptedDriverId: "replacement"});
    yield [{id: "second", token: "old-driver-second-device"}];
  };
  await deliverTripPush(f.port, "t", event);
  assert.equal(f.sent.length, 1);
  assert.deepEqual(f.sent[0].tokens, ["first"]);
});

test("cancellation needs matching immutable history and reciprocal bid", async () => {
  const event = transition("accepted", "cancelled");
  const f = fixture(event); f.setHistory(undefined);
  assert.deepEqual(await tripPushRecipients(f.port, "t", event), []);
  const g = fixture(event); g.setBid({...bid, status: "accepted"});
  assert.deepEqual(await tripPushRecipients(g.port, "t", event), []);
  const reopened = transition("accepted", "open");
  const h = fixture(reopened); h.setTrip({...assigned, acceptedDriverId: "replacement"});
  assert.deepEqual(await tripPushRecipients(h.port, "t", reopened), []);
});

test("missing/malformed bid or trip and unsupported transitions safely no-op", async () => {
  for (const bad of [undefined, {}, {...bid, driverId: "other"}, {...bid, createdAt: null},
    {...bid, status: "accepted"}, {...bid, priceAmount: -1}]) {
    assert.equal(bidCreatedEvent("t", "driver", bad), null);
  }
  assert.equal(tripTransitionEvent(undefined, assigned), null);
  assert.equal(tripTransitionEvent(assigned, {...assigned, status: "completed"}), null);
  assert.equal(tripTransitionEvent(assigned, {...assigned, status: "accepted"}), null);
  const event = bidCreatedEvent("t", "driver", bid)!;
  const f = fixture(event); f.setBid(undefined);
  assert.equal(await deliverTripPush(f.port, "t", event), "ignored");
  f.setTrip(undefined);
  assert.equal(await deliverTripPush(f.port, "t", event), "ignored");
  assert.equal(await deliverTripPush(f.port, "t", null), "ignored");
});

test("creator's own or excluded-driver bid never notifies", async () => {
  const event = bidCreatedEvent("t", "driver", bid)!;
  const f = fixture(event); f.setTrip({creatorId: "driver", status: "open"});
  assert.deepEqual(await tripPushRecipients(f.port, "t", event), []);
  f.setTrip({creatorId: "creator", status: "open", excludedDriverIds: ["driver"]});
  assert.deepEqual(await tripPushRecipients(f.port, "t", event), []);
});

test("concurrent/retried trigger claims once for all devices", async () => {
  const event = transition("accepted", "start_requested"); const f = fixture(event);
  await Promise.all([deliverTripPush(f.port, "t", event), deliverTripPush(f.port, "t", event)]);
  assert.equal(f.sent.length, 1);
  assert.equal(await deliverTripPush(f.port, "t", event), "ignored");
});

test("permanent invalid token removed, temporary FCM failure preserves token", async () => {
  const event = transition("open", "accepted"); const f = fixture(event);
  f.port.send = async () => ({responses: [
    {success: false, error: {code: "messaging/registration-token-not-registered"}},
    {success: false, error: {code: "messaging/server-unavailable"}},
  ]});
  assert.equal(await deliverTripPush(f.port, "t", event), "failed");
  assert.deepEqual(f.removed, ["driver/a"]);
});

test("transport failure cannot mutate trip/bid; ambiguous send is not repeated", async () => {
  const event = transition("open", "accepted"); const original = {...event.after}; const f = fixture(event);
  f.port.send = async () => { throw new Error("offline"); };
  assert.equal(await deliverTripPush(f.port, "t", event), "failed");
  assert.deepEqual(event.after, original); assert.deepEqual(f.removed, []);
  assert.equal(await deliverTripPush(f.port, "t", event), "ignored");
});

test("separate trigger invocations share server-only commit marker; next commit is independent", async () => {
  const records = new Set<string>();
  interface Ref {path: string; collection(name: string): Collection}
  interface Collection {doc(key: string): Ref}
  const collection = (path: string): Collection => ({doc: key => ({path: `${path}/${key}`,
    collection: name => collection(`${path}/${key}/${name}`)})});
  const db = {collection, runTransaction: async (body: (tx: {
    get(ref: Ref): Promise<{exists: boolean}>; create(ref: Ref): void;
  }) => Promise<boolean>) => body({
    get: async ref => ({exists: records.has(ref.path)}), create: ref => { records.add(ref.path); },
  })} as unknown as Firestore;
  const first = firestoreTripPushPort(db, {} as Messaging, "t", "transition:bid_accepted:1:0");
  const retry = firestoreTripPushPort(db, {} as Messaging, "t", "transition:bid_accepted:1:0");
  assert.equal(await first.claim(), true);
  assert.equal(await retry.claim(), false);
  assert.equal(await firestoreTripPushPort(db, {} as Messaging, "t", "transition:bid_accepted:2:0").claim(), true);
  assert.equal(records.size, 2);
  for (const path of records) assert.match(path, /^trip_posts\/t\/push_delivery\/[a-f0-9]{64}$/);
});
