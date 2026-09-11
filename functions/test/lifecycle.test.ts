import {strict as assert} from "node:assert";
import {test} from "node:test";
import {DocumentData, FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {executeDeadline, pendingDeadline, tripIdFromPayload} from "../src/lifecycle";

// In-memory transaction contract tests. No credentials, Firebase app or emulator.
class Store {
  docs = new Map<string, DocumentData>();
  now = new Timestamp(2000, 0);
  revision = 0;
  commits = 0;
  collection(path: string) { return {doc: (id: string) => ({path: `${path}/${id}`})}; }
  async runTransaction<T>(body: (tx: any) => Promise<T>): Promise<T> {
    for (;;) {
      const version = this.revision;
      const writes: Array<() => void> = [];
      const tx = {
        get: async (ref: {path: string}) => {
          assert.equal(writes.length, 0, "all reads must precede writes");
          const value = this.docs.get(ref.path);
          const captured = value && {...value};
          return {exists: value !== undefined, data: () => captured, readTime: this.now};
        },
        update: (ref: {path: string}, value: DocumentData) => {
          writes.push(() => this.docs.set(ref.path, {...this.docs.get(ref.path), ...value}));
        },
        set: (ref: {path: string}, value: DocumentData) => {
          writes.push(() => this.docs.set(ref.path, {...value}));
        },
      };
      const result = await body(tx);
      if (version !== this.revision) continue; // Simulate optimistic conflict/retry.
      if (writes.length) {
        for (const write of writes) write();
        this.revision++; this.commits++;
      }
      return result;
    }
  }
  get db() { return this as unknown as Firestore; }
}
function fixture(phase: "start" | "end") {
  const store = new Store();
  const request = new Timestamp(100, 123000);
  const deadline = new Timestamp(100 + (phase === "start" ? 180 : 1800), 123000);
  store.docs.set("trip_posts/t", {
    status: phase === "start" ? "start_requested" : "end_requested",
    creatorId: "creator", acceptedDriverId: "performer", acceptedBidId: "bid",
    driverId: "creator", tripReference: "CT-260910-ABC234",
    [phase === "start" ? "startRequestedAt" : "endRequestedAt"]: request,
    [phase === "start" ? "startAutoStartAt" : "endAutoCompleteAt"]: deadline,
  });
  for (const uid of ["creator", "performer"]) {
    store.docs.set(`users/${uid}`, {completedTripsCount: 4, ratingsCount: 2,
      ratingStarsTotal: 9, averageRating: 4.5, phoneNumber: "private"});
    store.docs.set(`user_reputation/${uid}`, {completedTripsCount: 4, ratingsCount: 2,
      ratingStarsTotal: 9, averageRating: 4.5, cancellationCount: 1, cancellationRate: null});
  }
  return {store, deadline};
}
for (const phase of ["start", "end"] as const) {
  test(`${phase}: early dispatch retries, deadline and late dispatch succeed`, async () => {
    for (const offset of [-1, 0, 1]) {
      const {store, deadline} = fixture(phase);
      store.now = new Timestamp(deadline.seconds + offset, deadline.nanoseconds);
      if (offset < 0) {
        await assert.rejects(executeDeadline(store.db, "t", phase), /not yet due/);
        assert.equal(store.commits, 0);
      } else {
        assert.equal(await executeDeadline(store.db, "t", phase), "changed");
        const trip = store.docs.get("trip_posts/t")!;
        assert.equal(trip.status, phase === "start" ? "in_progress" : "completed");
        assert.equal(trip[phase === "start" ? "startMethod" : "completionMethod"], phase === "start" ? "auto_started" : "auto_completed");
        assert.ok(trip[phase === "start" ? "startedAt" : "endedAt"].isEqual(FieldValue.serverTimestamp()));
        assert.ok(trip.updatedAt.isEqual(FieldValue.serverTimestamp()));
        assert.equal(trip.driverId, "creator");
        assert.equal(trip.acceptedDriverId, "performer");
        assert.equal(trip.tripReference, "CT-260910-ABC234");
        assert.equal(store.docs.get("users/performer")!.completedTripsCount, phase === "start" ? 4 : 5);
      }
    }
  });
  test(`${phase}: manual confirmation, changed status and deletion make stale tasks no-ops`, async () => {
    for (const status of ["accepted", "cancelled", "open", "completed", "in_progress"]) {
      const {store} = fixture(phase);
      const trip = store.docs.get("trip_posts/t")!;
      trip.status = status;
      trip[phase === "start" ? "startMethod" : "completionMethod"] = "creator_confirmed";
      assert.equal(await executeDeadline(store.db, "t", phase), "noop");
      assert.equal(store.commits, 0);
      assert.equal(trip[phase === "start" ? "startMethod" : "completionMethod"], "creator_confirmed");
    }
    const {store} = fixture(phase);
    store.docs.delete("trip_posts/t");
    assert.equal(await executeDeadline(store.db, "t", phase), "noop");
  });
  test(`${phase}: reject invalid assignment/deadline without partial writes`, async () => {
    for (const patch of [{acceptedDriverId: null}, {acceptedDriverId: "creator"}, {acceptedBidId: ""},
      {[phase === "start" ? "startAutoStartAt" : "endAutoCompleteAt"]: new Timestamp(1, 0)}]) {
      const {store} = fixture(phase);
      Object.assign(store.docs.get("trip_posts/t")!, patch);
      await assert.rejects(executeDeadline(store.db, "t", phase));
      assert.equal(store.commits, 0);
    }
  });
}
test("duplicate/concurrent completion commits creator and performing-driver counters once", async () => {
  const {store} = fixture("end");
  const results = await Promise.all(Array.from({length: 5}, () => executeDeadline(store.db, "t", "end")));
  assert.equal(results.filter((r) => r === "changed").length, 1);
  assert.equal(store.commits, 1);
  await executeDeadline(store.db, "t", "end");
  for (const uid of ["creator", "performer"]) {
    const profile = store.docs.get(`users/${uid}`)!;
    const publicData = store.docs.get(`user_reputation/${uid}`)!;
    assert.equal(profile.completedTripsCount, 5);
    assert.equal(profile.lastCompletedTripId, "t");
    assert.equal(profile.phoneNumber, "private");
    assert.equal(publicData.completedTripsCount, 5);
    assert.equal(publicData.averageRating, 4.5);
    assert.equal(publicData.ratingsCount, 2);
    assert.equal(publicData.cancellationCount, 1);
    assert.equal(publicData.cancellationRate, null);
    assert.equal(publicData.phoneNumber, undefined);
  }
});
test("missing/mismatched metrics abort the entire completion transaction", async () => {
  for (const missing of [true, false]) {
    const {store} = fixture("end");
    if (missing) store.docs.delete("users/performer");
    else store.docs.get("user_reputation/performer")!.completedTripsCount = 99;
    await assert.rejects(executeDeadline(store.db, "t", "end"), /repair required/);
    assert.equal(store.commits, 0);
    assert.equal(store.docs.get("trip_posts/t")!.status, "end_requested");
    assert.equal(store.docs.get("users/creator")!.completedTripsCount, 4);
  }
});
test("missing public mirror is initialized from private metrics without contact data", async () => {
  const {store} = fixture("end");
  store.docs.delete("user_reputation/performer");
  await executeDeadline(store.db, "t", "end");
  const rep = store.docs.get("user_reputation/performer")!;
  assert.equal(rep.completedTripsCount, 5);
  assert.equal(rep.averageRating, 4.5);
  assert.equal(rep.phoneNumber, undefined);
  assert.equal(rep.cancellationRate, null);
});
test("payload contains only a valid trip identifier; stored state supplies deadline", () => {
  assert.equal(tripIdFromPayload({tripId: "t"}), "t");
  for (const data of [null, [], {}, {tripId: ""}, {tripId: "x/y"}, {tripId: "t", status: "end_requested"}, {tripId: "t", acceptedDriverId: "attacker"}]) {
    assert.throws(() => tripIdFromPayload(data));
  }
  const {store, deadline} = fixture("start");
  assert.ok(pendingDeadline(store.docs.get("trip_posts/t")!, "start")!.isEqual(deadline));
});

test("duplicate start tasks never increment completion counters", async () => {
  const {store} = fixture("start");
  assert.equal(await executeDeadline(store.db, "t", "start"), "changed");
  assert.equal(await executeDeadline(store.db, "t", "start"), "noop");
  assert.equal(store.commits, 1);
  assert.equal(store.docs.get("users/creator")!.completedTripsCount, 4);
  assert.equal(store.docs.get("users/performer")!.completedTripsCount, 4);
});
test("manual completion winning during an automatic transaction forces a no-op retry", async () => {
  const {store} = fixture("end");
  const automatic = executeDeadline(store.db, "t", "end");
  // Simulate a committed manual transaction after the worker read, before its commit.
  store.docs.get("trip_posts/t")!.status = "completed";
  store.docs.get("trip_posts/t")!.completionMethod = "creator_confirmed";
  for (const uid of ["creator", "performer"]) {
    store.docs.get(`users/${uid}`)!.completedTripsCount = 5;
    store.docs.get(`user_reputation/${uid}`)!.completedTripsCount = 5;
  }
  store.revision++;
  assert.equal(await automatic, "noop");
  assert.equal(store.commits, 0);
  assert.equal(store.docs.get("trip_posts/t")!.completionMethod, "creator_confirmed");
  assert.equal(store.docs.get("users/creator")!.completedTripsCount, 5);
  assert.equal(store.docs.get("users/performer")!.completedTripsCount, 5);
});
