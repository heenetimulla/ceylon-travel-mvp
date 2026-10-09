import {strict as assert} from "node:assert";
import {test} from "node:test";
import {DocumentData, Firestore, Timestamp} from "firebase-admin/firestore";
import {cleanupCategories, DeletionDependencies, processDeletionOperation, validCleanupClearance} from "../src/account_deletion";
import {processDriverOperation} from "../src/driver_administration";

// In-memory contract fixture; no Firebase initialization or subprocess.
class Store {
  docs = new Map<string, DocumentData>();
  removed: string[] = [];
  version = 0;
  doc(path: string): any {
    return {path, get: async () => this.snapshot(path),
      collection: (name: string) => this.collection(path + "/" + name),
      delete: async () => { this.docs.delete(path); this.removed.push(path); this.version++; }};
  }
  collection(path: string, filters: Array<[string, string, unknown]> = []): any {
    return {path, filters, doc: (id: string) => this.doc(path + "/" + id),
      where: (field: string, op: string, value: unknown) => this.collection(path, [...filters, [field, op, value]]),
      limit: (_limit: number) => this.collection(path, filters)};
  }
  snapshot(path: string): any {
    const data = this.docs.get(path);
    return {exists: data != null, data: () => data && {...data}};
  }
  async recursiveDelete(ref: any) {
    this.removed.push(ref.path);
    for (const key of this.docs.keys()) if (key === ref.path || key.startsWith(ref.path + "/")) this.docs.delete(key);
    this.version++;
  }
  async runTransaction<T>(body: (tx: any) => Promise<T>): Promise<T> {
    for (;;) {
      const version = this.version;
      const writes: Array<() => void> = [];
      const tx = {
        get: async (ref: any) => {
          assert.equal(writes.length, 0, "reads precede writes");
          if (ref.filters) {
            const matching = [...this.docs].filter(([path, data]) =>
              path.startsWith(ref.path + "/") && path.split("/").length === ref.path.split("/").length + 1 &&
              ref.filters.every(([field, op, value]: [string, string, any]) =>
                op === "==" ? data[field] === value : value.includes(data[field])));
            return {empty: matching.length === 0};
          }
          return this.snapshot(ref.path);
        },
        create: (ref: any, value: DocumentData) => writes.push(() => {
          assert.ok(!this.docs.has(ref.path)); this.docs.set(ref.path, {...value});
        }),
        set: (ref: any, value: DocumentData) => writes.push(() => this.docs.set(ref.path, {...value})),
        update: (ref: any, value: DocumentData) => writes.push(() => {
          assert.ok(this.docs.has(ref.path)); this.docs.set(ref.path, {...this.docs.get(ref.path), ...value});
        }),
      };
      const result = await body(tx);
      if (version !== this.version) continue;
      writes.forEach(write => write());
      if (writes.length) this.version++;
      return result;
    }
  }
  get db() { return this as unknown as Firestore; }
}
const requestPath = "account_deletion_requests/owner";
const opPath = (id: string) => requestPath + "/operations/" + id;
function fixture() {
  const store = new Store();
  store.docs.set("users/owner", {uid: "owner", accountType: "driver", fullName: "Private",
    email: "private@example.test", phoneNumber: "private", vehicleNumber: "private",
    status: "active", accountStatus: "active", membershipPlan: "standard_annual", registrationPaidTotalLkr: 5000});
  store.docs.set(requestPath, {requesterUid: "owner", status: "pending", reason: "Private reason", revision: 1});
  store.docs.set("users/owner/fcm_tokens/device", {token: "private"});
  store.docs.set("user_public_profiles/owner", {fullName: "Private"});
  store.docs.set("user_public_profiles/owner/reviews/review", {comment: "Private"});
  store.docs.set("trip_posts/shared", {creatorId: "other", acceptedDriverId: "owner", status: "completed"});
  store.docs.set("trip_posts/shared/ratings/r", {stars: 5, comment: "shared"});
  store.docs.set("users/owner/payments/p", {amount: 5000, status: "verified"});
  return store;
}
function operation(store: Store, id: string, action = "approve", actorUid = "admin") {
  store.docs.set(opPath(id), {actorUid, action, expectedRevision: store.docs.get(requestPath)!.revision,
    note: "", userMessage: "", status: "pending"});
  store.version++;
}
function dependencies(events: string[] = []): DeletionDependencies {
  return {principal: async uid => ({uid, admin: uid === "admin"}),
    disable: async uid => { events.push("disable:" + uid); },
    deleteAuth: async uid => { events.push("delete:" + uid); }};
}
function clearance(revision: number) {
  return {requestRevision: revision, operatorUid: "trusted-operator", policyReference: "reviewed-policy-v1",
    completedAt: Timestamp.fromMillis(1000), categories: Object.fromEntries(cleanupCategories.map(category =>
      [category, {disposition: "minimized_retention", recordReference: "case-record/" + category,
        rationale: "Specific reviewed dispute need", reviewAt: Timestamp.fromMillis(2000)}]))};
}
test("support-only, owner and unrelated actors cannot approve or complete", async () => {
  for (const actor of ["support", "owner", "other"]) {
    for (const action of ["approve", "complete"]) {
      const store = fixture(); operation(store, "op", action, actor);
      await processDeletionOperation(store.db, "owner", "op", dependencies());
      assert.equal(store.docs.get(opPath("op"))!.errorCode, "permission-denied");
      assert.equal(store.docs.has("account_deletion_blocks/owner"), false);
      assert.equal(store.docs.get("users/owner")!.fullName, "Private");
    }
  }
});
test("primary admin approval restricts access, removes private profile/tokens, preserves shared and financial history", async () => {
  const store = fixture(), events: string[] = [];
  const trip = {...store.docs.get("trip_posts/shared")!};
  const rating = {...store.docs.get("trip_posts/shared/ratings/r")!};
  const payment = {...store.docs.get("users/owner/payments/p")!};
  operation(store, "approve");
  await processDeletionOperation(store.db, "owner", "approve", dependencies(events));
  assert.deepEqual(events, ["disable:owner"]);
  assert.equal(store.docs.get(requestPath)!.status, "approved");
  assert.equal(store.docs.get(requestPath)!.processingStage, "manual_cleanup_required");
  assert.equal(store.docs.get("users/owner")!.email, "");
  assert.equal(store.docs.get("users/owner")!.vehicleNumber, undefined);
  assert.equal(store.docs.get("users/owner")!.accountStatus, "deleted");
  assert.equal(store.docs.has("account_deletion_blocks/owner"), true);
  assert.equal(store.docs.has("users/owner/fcm_tokens/device"), false);
  assert.equal(store.docs.has("user_public_profiles/owner/reviews/review"), false);
  assert.deepEqual(store.docs.get("trip_posts/shared"), trip);
  assert.deepEqual(store.docs.get("trip_posts/shared/ratings/r"), rating);
  assert.deepEqual(store.docs.get("users/owner/payments/p"), payment);
  assert.equal(store.docs.get(requestPath + "/private/membership")!.snapshot.registrationPaidTotalLkr, 5000);
  assert.ok(store.removed.every(path => !path.startsWith("trip_posts") && !path.includes("/payments")));
});
test("approval fails closed for open and active trips for any participant link", async () => {
  for (const field of ["creatorId", "acceptedDriverId", "touristId", "driverId"]) {
    const store = fixture();
    store.docs.set("trip_posts/active", {[field]: "owner", status: "accepted"});
    operation(store, "approve");
    await processDeletionOperation(store.db, "owner", "approve", dependencies());
    assert.equal(store.docs.get(opPath("approve"))!.errorCode, "active-trips");
    assert.equal(store.docs.has("account_deletion_blocks/owner"), false);
  }
});
test("completion requires a per-category trusted cleanup record and only then deletes Auth", async () => {
  const store = fixture(), events: string[] = [];
  operation(store, "approve");
  await processDeletionOperation(store.db, "owner", "approve", dependencies(events));
  operation(store, "missing", "complete");
  await processDeletionOperation(store.db, "owner", "missing", dependencies(events));
  assert.equal(store.docs.get(opPath("missing"))!.errorCode, "cleanup-required");
  assert.ok(!events.includes("delete:owner"));
  store.docs.set(requestPath + "/private/cleanup", clearance(store.docs.get(requestPath)!.revision));
  operation(store, "complete", "complete");
  await processDeletionOperation(store.db, "owner", "complete", dependencies(events));
  assert.equal(store.docs.get(requestPath)!.status, "completed");
  assert.ok(store.docs.get(requestPath)!.completionAt);
  assert.equal(store.docs.get(requestPath)!.reason, "");
  assert.equal(store.docs.get("users/owner")!.deletionStatus, "completed");
  assert.ok(store.docs.has("account_deletion_blocks/owner"));
  assert.ok(store.docs.has(requestPath + "/audit/complete_processed"));
  assert.ok(events.includes("delete:owner"));
  assert.ok(store.docs.has("trip_posts/shared"));
});
test("blanket, incomplete, stale or unbounded retention attestations cannot complete deletion", () => {
  const valid = clearance(2);
  assert.equal(validCleanupClearance(valid, 2), true);
  assert.equal(validCleanupClearance(valid, 3), false);
  assert.equal(validCleanupClearance({...valid, categories: {}}, 2), false);
  for (const field of ["rationale", "recordReference", "reviewAt"]) {
    const broken = clearance(2);
    delete (broken.categories.shared_history as Record<string, unknown>)[field];
    assert.equal(validCleanupClearance(broken, 2), false);
  }
});
test("external failure stays retryable; replay cannot duplicate approval or reverse completion", async () => {
  const store = fixture(), events: string[] = [];
  operation(store, "approve");
  await assert.rejects(processDeletionOperation(store.db, "owner", "approve", {
    ...dependencies(events), disable: async () => { throw new Error("temporary"); },
  }));
  assert.equal(store.docs.get(opPath("approve"))!.status, "processing");
  assert.ok(store.docs.has("account_deletion_blocks/owner"));
  await processDeletionOperation(store.db, "owner", "approve", dependencies(events));
  await processDeletionOperation(store.db, "owner", "approve", dependencies(events));
  assert.deepEqual(events, ["disable:owner"]);
  assert.equal([...store.docs.keys()].filter(path => path === requestPath + "/audit/approve").length, 1);
});
test("concurrent admin approvals permit only one revision and one durable decision", async () => {
  const store = fixture(); operation(store, "one"); operation(store, "two");
  await Promise.all(["one", "two"].map(id => processDeletionOperation(store.db, "owner", id, dependencies())));
  assert.equal(["one", "two"].filter(id => store.docs.get(opPath(id))!.status === "succeeded").length, 1);
  assert.equal(store.docs.get(requestPath)!.revision, 2);
});
test("queued driver operation cannot restore a deleted account even with stale active profile", async () => {
  const store = fixture();
  store.docs.set("account_deletion_blocks/owner", {blockedAt: Timestamp.now()});
  store.docs.set("users/owner/driver_operations/restore", {
    actorUid: "admin", status: "pending", action: "set_account_status",
    expectedRevision: 0, reason: "", payload: {accountStatus: "active"},
  });
  await processDriverOperation(store.db, "owner", "restore", {...dependencies(), secret: "unused"});
  assert.equal(store.docs.get("users/owner/driver_operations/restore")!.errorCode, "account-deletion");
});

test("clarification exposes only the explicit user message, not private admin notes", async () => {
  const store = fixture();
  operation(store, "clarify", "request_clarification");
  Object.assign(store.docs.get(opPath("clarify"))!, {
    note: "Private internal review", userMessage: "Please clarify which unresolved trip needs support.",
  });
  await processDeletionOperation(store.db, "owner", "clarify", dependencies());
  const request = store.docs.get(requestPath)!;
  assert.equal(request.status, "needs_clarification");
  assert.equal(request.userMessage, "Please clarify which unresolved trip needs support.");
  assert.equal(request.note, undefined);
  assert.equal(store.docs.get(opPath("clarify"))!.note, "Private internal review");
  assert.equal(store.docs.has("account_deletion_blocks/owner"), false);
});
test("disabled admin and staff-account targets fail closed before deletion", async () => {
  for (const mode of ["disabled-admin", "staff-target"]) {
    const store = fixture(); operation(store, "approve");
    const deps = dependencies();
    deps.principal = async uid => ({uid, admin: uid === "admin",
      disabled: mode === "disabled-admin" && uid === "admin",
      supportAdmin: mode === "staff-target" && uid === "owner"});
    await processDeletionOperation(store.db, "owner", "approve", deps);
    assert.equal(store.docs.get(opPath("approve"))!.status, "failed");
    assert.equal(store.docs.has("account_deletion_blocks/owner"), false);
  }
});
