import {strict as assert} from "node:assert";
import {test} from "node:test";
import {DocumentData, Firestore, Timestamp} from "firebase-admin/firestore";
import {firstAnniversary, normalizeIdentity, paymentReference, processDriverOperation, registryKey} from "../src/driver_administration";
import {publicProfile} from "../src/public_profiles";

// Contract fake retries optimistic conflicts and rejects reads after any writes.
// No Firebase app, credentials, network, emulator or real secret is used.
class Store {
  docs = new Map<string, DocumentData>();
  revision = 0;
  doc(path: string): any {
    return {path, id: path.split("/").at(-1), get: async () => this.snapshot(path)};
  }
  snapshot(path: string) {
    const data = this.docs.get(path);
    return {exists: data !== undefined, data: () => data && {...data}};
  }
  async runTransaction<T>(body: (tx: any) => Promise<T>): Promise<T> {
    for (;;) {
      const revision = this.revision;
      const writes: Array<() => void> = [];
      const tx = {
        get: async (ref: {path: string}) => { assert.equal(writes.length, 0); return this.snapshot(ref.path); },
        create: (ref: {path: string}, value: DocumentData) => writes.push(() => {
          assert.ok(!this.docs.has(ref.path), `create-only: ${ref.path}`); this.docs.set(ref.path, {...value});
        }),
        set: (ref: {path: string}, value: DocumentData) => writes.push(() => this.docs.set(ref.path, {...value})),
        update: (ref: {path: string}, value: DocumentData) => writes.push(() => {
          assert.ok(this.docs.has(ref.path)); this.docs.set(ref.path, {...this.docs.get(ref.path), ...value});
        }),
      };
      const result = await body(tx);
      if (revision !== this.revision) continue;
      if (writes.length) { writes.forEach((write) => write()); this.revision++; }
      return result;
    }
  }
  get db() { return this as unknown as Firestore; }
}
const secret = "test-fixture-only-not-a-production-secret-32-bytes";
const now = () => new Date("2026-09-19T12:34:56.000Z");
function fixture(number = 1, uid = "driver") {
  const store = new Store();
  store.docs.set("system_config/driver_registration_counter", {nextRegistrationNumber: number, foundingOfferClosed: number > 100});
  store.docs.set(`users/${uid}`, {uid, accountType: "driver", status: "active", fullName: "Original name", email: "private@example.com",
    phoneNumber: "original phone", profilePhotoPath: "original photo", ratingsCount: 3, averageRating: 4,
    completedTripsCount: 9, cancelledTripsCount: 2, cancellationRate: 5});
  return store;
}
function operation(store: Store, uid: string, op: string, action: string, payload: DocumentData = {}, actorUid = "admin", revision?: number) {
  store.docs.set(`users/${uid}/driver_operations/${op}`, {action, payload, actorUid, status: "pending", reason: "Manual review",
    expectedRevision: revision ?? store.docs.get(`users/${uid}`)?.driverAdminRevision ?? 0});
  store.revision++;
}
async function process(store: Store, uid: string, op: string, key = secret) {
  await processDriverOperation(store.db, uid, op, {secret: key, now,
    evidenceMetadata: async (path) => ({contentType: 'image/jpeg', size: 100000, generation: '1', timeCreated: now().toISOString(),
      metadata: {ownerUid: path.split('/')[1], paymentId: path.split('/')[2], evidenceType: 'payment_slip', width: '1200', height: '800'}}),
    principal: async (actor) => ({uid: actor, admin: actor === "admin"})});
  return store.docs.get(`users/${uid}/driver_operations/${op}`)!;
}
const identity = {nicNumber: "901234567V", drivingLicenceNumber: "B1234567", nicDocumentPath: "private/nic",
  drivingLicenceDocumentPath: "private/licence", selfiePath: "private/selfie"};
async function submitIdentity(store: Store, uid = "driver", payload = identity) {
  operation(store, uid, "submit-id", "submit_identity", payload, uid);
  return process(store, uid, "submit-id");
}
function ready(store: Store, founding: boolean, uid = "driver") {
  Object.assign(store.docs.get(`users/${uid}`)!, {identityVerificationStatus: "verified", paymentStatus: "verified",
    registrationPaidTotalLkr: founding ? 3500 : 5000, currentRegistrationPaymentId: "paid"});
  store.docs.set(`driver_verifications/${uid}`, {identityVerificationStatus: "verified"});
  store.docs.set(`users/${uid}/payments/paid`, {paymentType: "registration", status: "verified",
    expectedAmountLkr: founding ? 3500 : 5000, claimedAmountLkr: founding ? 3500 : 5000,
    quotedRegistrationFeeLkr: founding ? 3500 : 5000, quotedMembershipPlan: founding ? "founding_lifetime" : "standard_annual",
    quotedAnnualRenewalRequired: !founding, quotedAnnualRenewalFeeLkr: founding ? null : 10000,
    quotedAt: Timestamp.fromDate(now()), foundingOfferOpenAtQuote: founding});
}

test("activation honors founding and standard quote fixtures with exact fees and no date waiver", async () => {
  for (const [number, founding] of [[1, true], [100, true], [101, false], [103, true]] as const) {
    const store = fixture(number); ready(store, founding);
    operation(store, "driver", "activate", "activate_membership");
    assert.equal((await process(store, "driver", "activate")).status, "succeeded");
    const user = store.docs.get("users/driver")!;
    assert.equal(user.driverRegistrationNumber, number);
    assert.equal(user.registrationFeePaidLkr, founding ? 3500 : 5000);
    assert.equal(user.membershipPlan, founding ? "founding_lifetime" : "standard_annual");
    assert.equal(user.annualRenewalRequired, !founding);
    assert.equal(user.annualRenewalFeeLkr, founding ? null : 10000);
    assert.equal(user.membershipStatus, "active");
    if (founding) assert.equal(user.membershipValidUntil, null);
    else assert.equal((user.membershipValidUntil as Timestamp).toDate().toISOString(), "2027-09-19T12:34:56.000Z");
    assert.equal(user.firstAnnualRenewalWaived, undefined);
    assert.equal(store.docs.get("system_config/driver_registration_counter")!.nextRegistrationNumber, number + 1);
    assert.equal(store.docs.get("users/driver/admin_history/activate")!.action, "membership_activated");
  }
  assert.equal(firstAnniversary(new Date("2024-02-29T10:00:00Z")).toISOString(), "2025-02-28T10:00:00.000Z");
});

test("non-admin, support-only, cross-owner and tourist operations cannot change privileged state", async () => {
  for (const actor of ["driver", "support-only", "stranger"]) {
    const store = fixture();
    operation(store, "driver", "attack", "set_account_status", {accountStatus: "suspended"}, actor);
    assert.equal((await process(store, "driver", "attack")).errorCode, "permission-denied");
    assert.equal(store.docs.get("users/driver")!.accountStatus, undefined);
    operation(store, "driver", "self-verify", "verify_identity", {}, actor);
    assert.equal((await process(store, "driver", "self-verify")).status, "failed");
    operation(store, "driver", "self-pay", "verify_payment", {paymentId: "p", bankRecordReference: "BANK1"}, actor);
    assert.equal((await process(store, "driver", "self-pay")).status, "failed");
  }
  const store = fixture();
  store.docs.get("users/driver")!.accountType = "tourist";
  operation(store, "driver", "tourist", "activate_membership");
  assert.equal((await process(store, "driver", "tourist")).errorCode, "not-driver");
});

test("identity is private, HMAC-claimed, manually verified/rejected and revision guarded", async () => {
  const store = fixture();
  assert.equal((await submitIdentity(store)).status, "succeeded");
  const submitted = store.docs.get("driver_verifications/driver")!;
  assert.equal(submitted.identityVerificationStatus, "pending");
  assert.equal(store.docs.get("users/driver")!.nicNumber, undefined);
  const registries = [...store.docs.keys()].filter((key) => key.startsWith("identity_registry/"));
  assert.equal(registries.length, 2);
  assert.ok(registries.every((key) => /^identity_registry\/[0-9a-f]{64}$/.test(key)));
  operation(store, "driver", "verify", "verify_identity");
  assert.equal((await process(store, "driver", "verify")).status, "succeeded");
  assert.equal(store.docs.get("users/driver")!.identityVerificationStatus, "verified");
  assert.equal(store.docs.get("driver_verifications/driver")!.reviewedBy, "admin");
  operation(store, "driver", "reject", "reject_identity");
  assert.equal((await process(store, "driver", "reject")).status, "succeeded");
  assert.equal(store.docs.get("driver_verifications/driver")!.identityVerificationStatus, "rejected");
  assert.equal(store.docs.get("driver_verifications/driver/submissions/submit-id")!.identityVerificationStatus, "pending");
  assert.equal(store.docs.get("users/driver/admin_history/verify")!.previousValue, "pending");
  operation(store, "driver", "stale", "verify_identity", {}, "admin", 0);
  assert.equal((await process(store, "driver", "stale")).errorCode, "stale-state");
});

test("duplicate NIC (including old/new format) or driving licence cannot be claimed by another account", async () => {
  for (const payload of [{...identity, nicNumber: normalizeIdentity("nic", identity.nicNumber), drivingLicenceNumber: "B7654321"},
    {...identity, nicNumber: "199923456789", drivingLicenceNumber: "b-1234567"}]) {
    const store = fixture(); await submitIdentity(store);
    store.docs.set("users/second", {accountType: "driver", status: "active"});
    assert.equal((await submitIdentity(store, "second", payload)).errorCode, "identity-unavailable");
    assert.equal(store.docs.has("driver_verifications/second"), false);
    assert.equal([...store.docs.keys()].filter((path) => path.startsWith("identity_registry/")).length, 2);
  }
});

test("concurrent duplicate identity submissions claim only one account", async () => {
  const store = fixture(); store.docs.set("users/second", {accountType: "driver", status: "active"});
  operation(store, "driver", "one", "submit_identity", identity, "driver");
  operation(store, "second", "two", "submit_identity", identity, "second");
  const results = await Promise.all([process(store, "driver", "one"), process(store, "second", "two")]);
  assert.equal(results.filter((r) => r.status === "succeeded").length, 1);
  assert.equal(results.filter((r) => r.errorCode === "identity-unavailable").length, 1);
});

test("missing/changed HMAC key fails closed; malformed values never create claims", async () => {
  const store = fixture();
  operation(store, "driver", "missing-key", "submit_identity", identity, "driver");
  assert.equal((await process(store, "driver", "missing-key", "")).errorCode, "secret-unavailable");
  await submitIdentity(store);
  operation(store, "driver", "changed-key", "submit_identity", identity, "driver");
  assert.equal((await process(store, "driver", "changed-key", secret + "rotated")).errorCode, "secret-mismatch");
  for (const input of [null, "", "short", "!!!", 123]) assert.throws(() => normalizeIdentity("nic", input));
  assert.notEqual(registryKey(secret, "nic", "123"), registryKey(secret, "driving_licence", "123"));
});

async function claimedPayment(store: Store, uid = "driver", amount = 3500) {
  operation(store, uid, "quote", "request_payment", {}, uid);
  assert.equal((await process(store, uid, "quote")).status, "succeeded");
  operation(store, uid, "claim", "submit_payment", {paymentId: "quote", claimedAmountLkr: amount,
    claimedPaymentDate: "2026-09-19", bankTransactionReference: "driver-reference", depositorName: "Depositor",
    slipPath: `payment_evidence/${uid}/quote/${'a'.repeat(32)}.jpg`}, uid);
  assert.equal((await process(store, uid, "claim")).status, "succeeded");
}

test("payment quote/proof/review preserves verified history and human-readable reference", async () => {
  const store = fixture(); await claimedPayment(store);
  const before = store.docs.get("users/driver/payments/quote")!;
  assert.equal(before.expectedAmountLkr, 3500); assert.equal(before.status, "pending");
  assert.match(before.paymentReference, /^CTP260919[A-Z0-9]{6}$/);
  assert.equal(before.paymentReference.length, 15);
  operation(store, "driver", "verify-pay", "verify_payment", {paymentId: "quote", bankRecordReference: "BANK-001"});
  assert.equal((await process(store, "driver", "verify-pay")).status, "succeeded");
  const paid = {...store.docs.get("users/driver/payments/quote")!};
  assert.equal(paid.status, "verified"); assert.equal(paid.verifiedBy, "admin");
  assert.equal(paid.slipPath, before.slipPath); assert.equal(paid.claimedAmountLkr, before.claimedAmountLkr);
  await process(store, "driver", "verify-pay");
  operation(store, "driver", "reject-paid", "reject_payment", {paymentId: "quote"});
  assert.equal((await process(store, "driver", "reject-paid")).errorCode, "payment-final");
  assert.deepEqual(store.docs.get("users/driver/payments/quote"), paid);
  assert.equal(store.docs.get("users/driver")!.registrationPaidTotalLkr, 3500);
  assert.equal(store.docs.get("users/driver/admin_history/verify-pay")!.action, "payment_status_changed");
  assert.equal(paymentReference(now(), "A8K4Q2"), 'CTP260919A8K4Q2');
});

test('Old issued reference remains byte-for-byte unchanged through payment review', async () => {
  const store = fixture(); await claimedPayment(store);
  store.docs.get('users/driver/payments/quote')!.paymentReference = 'CT-PAY-260919-OLD123';
  operation(store, 'driver', 'verify-old', 'verify_payment', {paymentId: 'quote', bankRecordReference: 'BANK-OLD'});
  assert.equal((await process(store, 'driver', 'verify-old')).status, 'succeeded');
  assert.equal(store.docs.get('users/driver/payments/quote')!.paymentReference, 'CT-PAY-260919-OLD123');
});

test('Slip required, payment rejection needs reason, and support-only cannot verify payment', async () => {
  const store = fixture();
  operation(store, 'driver', 'quote', 'request_payment', {}, 'driver'); await process(store, 'driver', 'quote');
  operation(store, 'driver', 'no-slip', 'submit_payment', {paymentId: 'quote', claimedAmountLkr: 3500,
    claimedPaymentDate: '2026-09-19', bankTransactionReference: 'BANK', depositorName: 'Owner'}, 'driver');
  assert.equal((await process(store, 'driver', 'no-slip')).errorCode, 'invalid-evidence');
  assert.equal(store.docs.get('users/driver/payments/quote')!.claimSubmitted, false);
  const claimed = fixture(); await claimedPayment(claimed);
  operation(claimed, 'driver', 'no-reason', 'reject_payment', {paymentId: 'quote'});
  claimed.docs.get('users/driver/driver_operations/no-reason')!.reason = '  ';
  assert.equal((await process(claimed, 'driver', 'no-reason')).errorCode, 'reason-required');
  assert.equal(claimed.docs.get('users/driver/payments/quote')!.status, 'pending');
  for (const actor of ['driver', 'support-only', 'stranger']) {
    operation(claimed, 'driver', `verify-${actor}`, 'verify_payment', {paymentId: 'quote', bankRecordReference: 'BANK'}, actor);
    assert.equal((await process(claimed, 'driver', `verify-${actor}`)).errorCode, 'permission-denied');
    operation(claimed, 'driver', `reject-${actor}`, 'reject_payment', {paymentId: 'quote'}, actor);
    assert.equal((await process(claimed, 'driver', `reject-${actor}`)).errorCode, 'permission-denied');
  }
});

test("wrong amounts cannot verify; rejection retains claim and cannot activate", async () => {
  const store = fixture(); await claimedPayment(store, "driver", 3400);
  operation(store, "driver", "bad-pay", "verify_payment", {paymentId: "quote", bankRecordReference: "BANK-WRONG"});
  assert.equal((await process(store, "driver", "bad-pay")).errorCode, "incorrect-amount");
  operation(store, "driver", "reject", "reject_payment", {paymentId: "quote"});
  assert.equal((await process(store, "driver", "reject")).status, "succeeded");
  const payment = store.docs.get("users/driver/payments/quote")!;
  assert.equal(payment.status, "rejected"); assert.equal(payment.claimedAmountLkr, 3400);
  assert.equal(store.docs.get("users/driver")!.paymentStatus, "rejected");
});

test("membership requires verified identity, verified payment, correct total and configured counter", async () => {
  for (const patch of [{identityVerificationStatus: "pending"}, {paymentStatus: "pending"},
    {paymentStatus: "not_required"}, {registrationPaidTotalLkr: 1}]) {
    const store = fixture(); ready(store, true); Object.assign(store.docs.get("users/driver")!, patch);
    operation(store, "driver", "activate", "activate_membership");
    assert.equal((await process(store, "driver", "activate")).status, "failed");
    assert.equal(store.docs.get("users/driver")!.driverRegistrationNumber, undefined);
    assert.equal(store.docs.get("system_config/driver_registration_counter")!.nextRegistrationNumber, 1);
  }
  const store = fixture(); ready(store, true); store.docs.delete("system_config/driver_registration_counter");
  operation(store, "driver", "activate", "activate_membership");
  assert.equal((await process(store, "driver", "activate")).errorCode, "counter-unavailable");
});

test("pre-cutoff quote verified and activated after closure preserves lifetime entitlement", async () => {
  const store = fixture(100); await claimedPayment(store);
  store.docs.set("users/hundredth", {accountType: "driver", status: "active"}); ready(store, true, "hundredth");
  operation(store, "hundredth", "activate", "activate_membership");
  assert.equal((await process(store, "hundredth", "activate")).status, "succeeded");
  operation(store, "driver", "verify", "verify_payment", {paymentId: "quote", bankRecordReference: "BANK1"});
  assert.equal((await process(store, "driver", "verify")).status, "succeeded");
  Object.assign(store.docs.get("users/driver")!, {identityVerificationStatus: "verified"});
  store.docs.set("driver_verifications/driver", {identityVerificationStatus: "verified"});
  operation(store, "driver", "activate", "activate_membership");
  assert.equal((await process(store, "driver", "activate")).status, "succeeded");
  const user = store.docs.get("users/driver")!;
  assert.equal(user.driverRegistrationNumber, 101);
  assert.equal(user.registrationFeePaidLkr, 3500);
  assert.equal(user.membershipPlan, "founding_lifetime");
  assert.equal(user.annualRenewalRequired, false);
  assert.equal(user.annualRenewalFeeLkr, null);
  assert.equal(user.membershipValidUntil, null);
  assert.equal([...store.docs.keys()].filter((key) => key.startsWith("users/driver/payments/")).length, 1);
});

test("concurrent activation assigns distinct numbers; duplicates never consume another number or audit", async () => {
  const store = fixture(1); ready(store, true);
  store.docs.set("users/second", {accountType: "driver", status: "active"}); ready(store, true, "second");
  operation(store, "driver", "first", "activate_membership");
  operation(store, "second", "second", "activate_membership");
  await Promise.all([process(store, "driver", "first"), process(store, "second", "second")]);
  assert.deepEqual(new Set([store.docs.get("users/driver")!.driverRegistrationNumber,
    store.docs.get("users/second")!.driverRegistrationNumber]), new Set([1, 2]));
  operation(store, "driver", "duplicate", "activate_membership");
  await Promise.all([process(store, "driver", "duplicate"), process(store, "driver", "first")]);
  assert.equal(store.docs.get("system_config/driver_registration_counter")!.nextRegistrationNumber, 3);
  assert.equal(store.docs.has("users/driver/admin_history/duplicate"), false);
  assert.equal(store.docs.get("users/driver/driver_operations/duplicate")!.result.alreadyActivated, true);
});

test("manual account changes accept only allowed values and never alter protected profile fields", async () => {
  const store = fixture(), before = {...store.docs.get("users/driver")!};
  for (const status of ["suspended", "inactive", "active"]) {
    operation(store, "driver", status, "set_account_status", {accountStatus: status});
    assert.equal((await process(store, "driver", status)).status, "succeeded");
    assert.equal(store.docs.get("users/driver/admin_history/" + status)!.action, "account_status_changed");
  }
  for (const key of Object.keys(before)) assert.deepEqual(store.docs.get("users/driver")![key], before[key]);
  for (const patch of [{accountStatus: "deleted"}, {accountStatus: "suspended", accountType: "tourist"},
    {accountStatus: "suspended", email: "changed"}, {accountStatus: "suspended", phoneNumber: "changed"},
    {accountStatus: "suspended", ratingsCount: 999}, {accountStatus: "suspended", cancellationRate: 0},
    {accountStatus: "suspended", completedTripsCount: 999}]) {
    operation(store, "driver", "invalid", "set_account_status", patch);
    assert.equal((await process(store, "driver", "invalid")).status, "failed");
    assert.equal(store.docs.get("users/driver")!.accountStatus, "active");
  }
});

test("public projection exposes only a safe identity label, never raw identity or payment fields", () => {
  const profile = publicProfile("driver", {fullName: "Driver", identityVerificationStatus: "verified", nicNumber: "sensitive",
    drivingLicenceNumber: "sensitive", bankTransactionReference: "private", registrationPaidTotalLkr: 3500,
    membershipPlan: "founding_lifetime", accountStatus: "active"});
  assert.equal(profile.verificationStatus, "verified");
  for (const key of ["nicNumber", "drivingLicenceNumber", "bankTransactionReference", "registrationPaidTotalLkr", "membershipPlan", "accountStatus"]) {
    assert.equal(profile[key], undefined);
  }
  assert.equal(publicProfile("driver", {identityVerificationStatus: "rejected", verification: {status: "verified"}}).verificationStatus, "not_verified");
});

test("bank record reuse across accounts cannot credit a second payment", async () => {
  const store = fixture(); await claimedPayment(store);
  operation(store, "driver", "verify", "verify_payment", {paymentId: "quote", bankRecordReference: "BANK-ONE"});
  await process(store, "driver", "verify");
  store.docs.set("users/second", {accountType: "driver", status: "active"});
  await claimedPayment(store, "second");
  operation(store, "second", "verify", "verify_payment", {paymentId: "quote", bankRecordReference: " bank-one "});
  assert.equal((await process(store, "second", "verify")).errorCode, "payment-used");
  assert.equal(store.docs.get("users/second/payments/quote")!.status, "pending");
  assert.equal(store.docs.get("users/second")!.registrationPaidTotalLkr, undefined);
});

test("registration number collision fails without consuming counter or membership", async () => {
  const store = fixture(100); ready(store, true);
  store.docs.set("driver_registration_registry/100", {uid: "already-assigned"});
  operation(store, "driver", "activate", "activate_membership");
  assert.equal((await process(store, "driver", "activate")).errorCode, "counter-conflict");
  assert.equal(store.docs.get("system_config/driver_registration_counter")!.nextRegistrationNumber, 100);
  assert.equal(store.docs.get("users/driver")!.driverRegistrationNumber, undefined);
});

test("simultaneous activation of one account creates exactly one assignment and audit", async () => {
  const store = fixture(100); ready(store, true);
  operation(store, "driver", "one", "activate_membership");
  operation(store, "driver", "two", "activate_membership");
  const results = await Promise.all([process(store, "driver", "one"), process(store, "driver", "two")]);
  assert.ok(results.every((result) => result.status === "succeeded"));
  assert.equal(store.docs.get("users/driver")!.driverRegistrationNumber, 100);
  assert.equal(store.docs.get("system_config/driver_registration_counter")!.nextRegistrationNumber, 101);
  assert.equal([...store.docs.keys()].filter((key) => key.startsWith("users/driver/admin_history/")).length, 1);
  assert.equal([...store.docs.keys()].filter((key) => key.startsWith("driver_registration_registry/")).length, 1);
});

test("changed secret cannot bypass the verified bank transaction registry", async () => {
  const store = fixture(); await claimedPayment(store);
  operation(store, "driver", "verify", "verify_payment", {paymentId: "quote", bankRecordReference: "BANK-ONE"});
  await process(store, "driver", "verify");
  store.docs.set("users/second", {accountType: "driver", status: "active"});
  await claimedPayment(store, "second");
  operation(store, "second", "verify", "verify_payment", {paymentId: "quote", bankRecordReference: "BANK-ONE"});
  assert.equal((await process(store, "second", "verify", secret + "changed")).errorCode, "secret-mismatch");
  assert.equal(store.docs.get("users/second/payments/quote")!.status, "pending");
});

test("disabled admin fails authorization before any business mutation", async () => {
  const store = fixture(); ready(store, true);
  operation(store, "driver", "activate", "activate_membership");
  await processDriverOperation(store.db, "driver", "activate", {secret, now,
    principal: async (uid) => ({uid, admin: true, disabled: true})});
  assert.equal(store.docs.get("users/driver/driver_operations/activate")!.errorCode, "permission-denied");
  assert.equal(store.docs.get("system_config/driver_registration_counter")!.nextRegistrationNumber, 1);
  assert.equal(store.docs.has("users/driver/admin_history/activate"), false);
});

test("99 leaves offer open; 100 closes it once and subsequent new quotes use annual terms", async () => {
  const store = fixture(99); ready(store, true);
  operation(store, "driver", "activate", "activate_membership");
  await process(store, "driver", "activate");
  assert.equal(store.docs.get("system_config/driver_registration_counter")!.foundingOfferClosed, false);
  assert.equal(store.docs.has("admin_notifications/founding_offer_closed"), false);
  store.docs.set("users/early", {accountType: "driver", status: "active"});
  operation(store, "early", "quote", "request_payment", {}, "early");
  await process(store, "early", "quote");
  const early = store.docs.get("users/early/payments/quote")!;
  assert.equal(early.quotedRegistrationFeeLkr, 3500);
  assert.equal(early.quotedMembershipPlan, "founding_lifetime");
  assert.equal(early.quotedAnnualRenewalRequired, false);
  assert.equal(early.quotedAnnualRenewalFeeLkr, null);
  assert.equal(early.foundingOfferOpenAtQuote, true);
  assert.ok(early.quotedAt);
  store.docs.set("users/hundredth", {accountType: "driver", status: "active"}); ready(store, true, "hundredth");
  operation(store, "hundredth", "activate", "activate_membership");
  await process(store, "hundredth", "activate");
  const config = store.docs.get("system_config/driver_registration_counter")!;
  assert.equal(config.foundingOfferClosed, true);
  assert.equal(config.foundingOfferClosedByRegistrationNumber, 100);
  assert.ok(config.foundingOfferClosedAt);
  const event = {...store.docs.get("admin_notifications/founding_offer_closed")!};
  assert.equal(event.type, "founding_offer_closed"); assert.equal(event.read, false);
  assert.equal(event.registrationNumber, 100);
  operation(store, "hundredth", "retry", "activate_membership");
  await process(store, "hundredth", "retry");
  await process(store, "hundredth", "activate");
  assert.deepEqual(store.docs.get("admin_notifications/founding_offer_closed"), event);
  assert.equal([...store.docs.keys()].filter((key) => key.startsWith("admin_notifications/")).length, 1);
  store.docs.set("users/late", {accountType: "driver", status: "active"});
  await claimedPayment(store, "late", 5000);
  const late = store.docs.get("users/late/payments/quote")!;
  assert.equal(late.quotedRegistrationFeeLkr, 5000);
  assert.equal(late.quotedMembershipPlan, "standard_annual");
  assert.equal(late.quotedAnnualRenewalRequired, true);
  assert.equal(late.quotedAnnualRenewalFeeLkr, 10000);
  assert.equal(late.foundingOfferOpenAtQuote, false);
  operation(store, "late", "verify", "verify_payment", {paymentId: "quote", bankRecordReference: "LATE-BANK"});
  assert.equal((await process(store, "late", "verify")).status, "succeeded");
  Object.assign(store.docs.get("users/late")!, {identityVerificationStatus: "verified"});
  store.docs.set("driver_verifications/late", {identityVerificationStatus: "verified"});
  operation(store, "late", "activate", "activate_membership");
  assert.equal((await process(store, "late", "activate")).status, "succeeded");
  assert.equal(store.docs.get("users/late")!.membershipPlan, "standard_annual");
  assert.equal(store.docs.get("users/late")!.registrationFeePaidLkr, 5000);
});

test("concurrent 100 and 101 activations both honor pre-cutoff quotes and close exactly once", async () => {
  const store = fixture(100); ready(store, true);
  store.docs.set("users/second", {accountType: "driver", status: "active"}); ready(store, true, "second");
  operation(store, "driver", "activate", "activate_membership");
  operation(store, "second", "activate", "activate_membership");
  const results = await Promise.all([process(store, "driver", "activate"), process(store, "second", "activate")]);
  assert.ok(results.every((result) => result.status === "succeeded"));
  assert.deepEqual(new Set([store.docs.get("users/driver")!.driverRegistrationNumber,
    store.docs.get("users/second")!.driverRegistrationNumber]), new Set([100, 101]));
  for (const uid of ["driver", "second"]) {
    assert.equal(store.docs.get(`users/${uid}`)!.membershipPlan, "founding_lifetime");
    assert.equal(store.docs.get(`users/${uid}`)!.registrationFeePaidLkr, 3500);
    operation(store, uid, "retry", "activate_membership"); await process(store, uid, "retry");
    assert.equal(store.docs.has(`users/${uid}/admin_history/retry`), false);
  }
  assert.equal(store.docs.get("system_config/driver_registration_counter")!.nextRegistrationNumber, 102);
  assert.equal(store.docs.get("system_config/driver_registration_counter")!.foundingOfferClosed, true);
  assert.equal([...store.docs.keys()].filter((key) => key.startsWith("admin_notifications/")).length, 1);
});

test("rejected claim replacement after closure keeps the original quote entitlement and issuance time", async () => {
  const store = fixture(100); await claimedPayment(store);
  const original = {...store.docs.get("users/driver/payments/quote")!};
  operation(store, "driver", "reject", "reject_payment", {paymentId: "quote"}); await process(store, "driver", "reject");
  store.docs.set("users/second", {accountType: "driver", status: "active"}); ready(store, true, "second");
  operation(store, "second", "activate", "activate_membership"); await process(store, "second", "activate");
  operation(store, "driver", "replacement", "request_payment", {}, "driver");
  assert.equal((await process(store, "driver", "replacement")).status, "succeeded");
  const replacement = store.docs.get("users/driver/payments/replacement")!;
  assert.equal(replacement.expectedAmountLkr, 3500);
  assert.equal(replacement.quotedMembershipPlan, "founding_lifetime");
  assert.deepEqual(replacement.quotedAt, original.quotedAt);
});

test("client payloads cannot reopen cutoff, forge terms, lower standard fee or self-activate", async () => {
  const store = fixture(101);
  for (const payload of [{foundingOfferClosed: false}, {quotedRegistrationFeeLkr: 3500},
    {quotedMembershipPlan: "founding_lifetime"}, {expectedAmountLkr: 3500}]) {
    operation(store, "driver", "forged", "request_payment", payload, "driver");
    assert.equal((await process(store, "driver", "forged")).errorCode, "invalid-input");
  }
  await claimedPayment(store, "driver", 3500);
  operation(store, "driver", "verify", "verify_payment", {paymentId: "quote", bankRecordReference: "LOW"});
  assert.equal((await process(store, "driver", "verify")).errorCode, "incorrect-amount");
  operation(store, "driver", "self", "activate_membership", {}, "driver");
  assert.equal((await process(store, "driver", "self")).errorCode, "permission-denied");
  assert.equal(store.docs.get("system_config/driver_registration_counter")!.foundingOfferClosed, true);
  assert.equal(store.docs.get("users/driver/payments/quote")!.quotedRegistrationFeeLkr, 5000);
});

test("missing or inconsistent quote terms and cutoff state fail closed", async () => {
  const store = fixture(); ready(store, true);
  store.docs.get("users/driver/payments/paid")!.quotedMembershipPlan = "standard_annual";
  operation(store, "driver", "activate", "activate_membership");
  assert.equal((await process(store, "driver", "activate")).errorCode, "invalid-quote");
  assert.equal(store.docs.get("system_config/driver_registration_counter")!.nextRegistrationNumber, 1);
  const broken = fixture(101); broken.docs.get("system_config/driver_registration_counter")!.foundingOfferClosed = false;
  operation(broken, "driver", "quote", "request_payment", {}, "driver");
  assert.equal((await process(broken, "driver", "quote")).errorCode, "counter-unavailable");
});

test("quote issuance racing with activation 100 persists a valid serialized entitlement", async () => {
  const store = fixture(100); ready(store, true);
  store.docs.set("users/new", {accountType: "driver", status: "active"});
  operation(store, "driver", "activate", "activate_membership");
  operation(store, "new", "quote", "request_payment", {}, "new");
  const results = await Promise.all([process(store, "driver", "activate"), process(store, "new", "quote")]);
  assert.ok(results.every((result) => result.status === "succeeded"));
  const quote = store.docs.get("users/new/payments/quote")!;
  const founding = quote.foundingOfferOpenAtQuote;
  assert.equal(quote.quotedRegistrationFeeLkr, founding ? 3500 : 5000);
  assert.equal(quote.quotedMembershipPlan, founding ? "founding_lifetime" : "standard_annual");
  assert.equal(quote.quotedAnnualRenewalRequired, !founding);
  assert.equal(quote.quotedAnnualRenewalFeeLkr, founding ? null : 10000);
  assert.equal(store.docs.get("system_config/driver_registration_counter")!.foundingOfferClosed, true);
  assert.equal([...store.docs.keys()].filter((key) => key.startsWith("admin_notifications/")).length, 1);
});

test("verified founding payment before closure activates later without another payment", async () => {
  const store = fixture(100); await claimedPayment(store);
  operation(store, "driver", "verify", "verify_payment", {paymentId: "quote", bankRecordReference: "PRE-CUTOFF"});
  assert.equal((await process(store, "driver", "verify")).status, "succeeded");
  const payment = {...store.docs.get("users/driver/payments/quote")!};
  store.docs.set("users/second", {accountType: "driver", status: "active"}); ready(store, true, "second");
  operation(store, "second", "activate", "activate_membership"); await process(store, "second", "activate");
  operation(store, "driver", "extra", "request_payment", {}, "driver");
  assert.equal((await process(store, "driver", "extra")).errorCode, "already-paid");
  Object.assign(store.docs.get("users/driver")!, {identityVerificationStatus: "verified"});
  store.docs.set("driver_verifications/driver", {identityVerificationStatus: "verified"});
  operation(store, "driver", "activate", "activate_membership");
  assert.equal((await process(store, "driver", "activate")).status, "succeeded");
  assert.equal(store.docs.get("users/driver")!.driverRegistrationNumber, 101);
  assert.equal(store.docs.get("users/driver")!.membershipPlan, "founding_lifetime");
  assert.equal(store.docs.get("users/driver")!.registrationFeePaidLkr, 3500);
  assert.deepEqual(store.docs.get("users/driver/payments/quote"), payment);
});

test("number-only identity intake supports manual review without fabricated evidence paths", async () => {
  const store = fixture();
  operation(store, "driver", "numbers", "submit_identity", {nicNumber: " 901234567v ", drivingLicenceNumber: " b-1234567 "}, "driver");
  assert.equal((await process(store, "driver", "numbers")).status, "succeeded");
  const submitted = store.docs.get("driver_verifications/driver")!;
  assert.equal(submitted.nicNumber, "901234567v");
  assert.equal(submitted.drivingLicenceNumber, "b-1234567");
  assert.equal(submitted.nicDocumentPath, null);
  assert.equal(submitted.drivingLicenceDocumentPath, null);
  assert.equal(submitted.selfiePath, null);
  assert.equal(submitted.identityVerificationStatus, "pending");
  assert.equal(store.docs.get("users/driver")!.nicNumber, undefined);
  assert.equal(store.docs.get("users/driver")!.drivingLicenceNumber, undefined);
  operation(store, "driver", "review", "verify_identity");
  assert.equal((await process(store, "driver", "review")).status, "succeeded");
  assert.equal(store.docs.get("users/driver")!.identityVerificationStatus, "verified");
  assert.equal(store.docs.get("users/driver/admin_history/review")!.actorUid, "admin");
});

test("rejected number-only submission can be corrected with revision protection and preserved history", async () => {
  const store = fixture();
  operation(store, "driver", "first", "submit_identity", {nicNumber: "901234567V", drivingLicenceNumber: "B1234567"}, "driver");
  await process(store, "driver", "first");
  operation(store, "driver", "reject", "reject_identity");
  await process(store, "driver", "reject");
  const corrected = {nicNumber: "199012304567", drivingLicenceNumber: "B7654321"};
  operation(store, "driver", "stale", "submit_identity", corrected, "driver", 1);
  assert.equal((await process(store, "driver", "stale")).errorCode, "stale-state");
  operation(store, "driver", "corrected", "submit_identity", corrected, "driver");
  assert.equal((await process(store, "driver", "corrected")).status, "succeeded");
  assert.equal(store.docs.get("driver_verifications/driver")!.identityVerificationStatus, "pending");
  assert.equal(store.docs.get("driver_verifications/driver/submissions/first")!.drivingLicenceNumber, "B1234567");
  assert.equal(store.docs.get("driver_verifications/driver/submissions/corrected")!.drivingLicenceNumber, "B7654321");
  assert.equal([...store.docs.keys()].filter((key) => key.startsWith("identity_registry/")).length, 3);
});


test("identity attachments use server-read metadata, preserve private history and reject stale revisions", async () => {
  const store = fixture();
  const path = "driver_evidence/driver/0/nic/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg";
  const payload = {nicNumber: identity.nicNumber, drivingLicenceNumber: identity.drivingLicenceNumber, evidence: {nic: path}};
  operation(store, "driver", "evidence", "submit_identity", payload, "driver");
  const deps = {secret, now, principal: async (uid: string) => ({uid, admin: false}),
    evidenceMetadata: async () => ({contentType: "image/jpeg", size: "120000", generation: "123",
      timeCreated: now().toISOString(), metadata: {ownerUid: "driver", applicationRevision: "0", evidenceType: "nic", width: "1600", height: "1000"}})};
  await processDriverOperation(store.db, "driver", "evidence", deps);
  assert.equal(store.docs.get("users/driver/driver_operations/evidence")!.status, "succeeded");
  const current = store.docs.get("driver_verifications/driver")!;
  const history = store.docs.get("driver_verifications/driver/submissions/evidence")!;
  assert.equal(current.nicDocumentPath, path);
  assert.deepEqual(current.evidence, history.evidence);
  assert.equal(current.evidence[0].compressedSizeBytes, 120000);
  assert.equal(current.evidence[0].applicationRevision, 0);
  assert.equal(current.evidence[0].uploadedAt.toDate().toISOString(), now().toISOString());
  assert.equal(store.docs.get("users/driver")!.evidence, undefined);
  assert.equal(store.docs.get("users/driver")!.nicDocumentPath, undefined);
  await processDriverOperation(store.db, "driver", "evidence", deps);
  assert.equal([...store.docs.keys()].filter((p) => p.includes("/submissions/")).length, 1);
  operation(store, "driver", "stale-evidence", "submit_identity", payload, "driver", 0);
  await processDriverOperation(store.db, "driver", "stale-evidence", deps);
  assert.equal(store.docs.get("users/driver/driver_operations/stale-evidence")!.errorCode, "stale-state");
  assert.deepEqual(store.docs.get("driver_verifications/driver/submissions/evidence"), history);
});
