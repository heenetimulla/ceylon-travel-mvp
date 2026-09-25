import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {before, after, beforeEach, test} from 'node:test';
import {initializeTestEnvironment, assertSucceeds} from '@firebase/rules-unit-testing';
import {doc, getDocFromServer, setDoc, updateDoc, runTransaction, writeBatch, serverTimestamp, Timestamp} from 'firebase/firestore';

// Isolated demo project and an explicitly configured local emulator only.
// No Admin SDK or production credentials are used by any tested operation.
const projectId = 'demo-ceylon-lifecycle-rules';
let env;
const tripPath = 'trip_posts/start-regression';
const anchorPath = tripPath + '/lifecycle_requests/start';
const driverUid = 'driver';
const touristUid = 'tourist';

before(async () => {
  const endpoint = process.env.FIRESTORE_EMULATOR_HOST;
  assert.match(endpoint ?? '', /^(localhost|127\.0\.0\.1):[0-9]+$/,
    'Start a local Firestore emulator and set FIRESTORE_EMULATOR_HOST; never target production.');
  const [host, port] = endpoint.split(':');
  env = await initializeTestEnvironment({projectId, firestore: {host, port: Number(port),
    rules: await readFile(new URL('../firestore.rules', import.meta.url), 'utf8')}});
});
after(async () => { if (env) { await env.cleanup(); } });
beforeEach(async () => { await env.clearFirestore(); });

// assertFails alone accepts any permission denial, including evaluator exhaustion.
// Check the code and reject exhaustion diagnostics when the SDK exposes them.
// Some emulator versions report the budget failure ONLY in their separate log;
// README requires inspection of that log even when this suite is green.
async function assertDenied(operation) {
  await assert.rejects(operation, error => {
    assert.equal(error.code, 'permission-denied');
    assert.doesNotMatch(String(error.message), /maximum of 1000 expressions|expression.{0,40}(limit|exhaust)/i,
      'Denial must come from a predicate, not evaluator exhaustion. Inspect the emulator log.');
    return true;
  });
}

function driver(patch = {}) {
  return {uid: driverUid, status: 'active', accountType: 'driver', registrationStatus: 'approved',
    accountStatus: 'active', identityVerificationStatus: 'verified', paymentStatus: 'verified',
    membershipStatus: 'active', membershipPlan: 'founding_lifetime', ...patch};
}
async function seed(profile = driver(), tripPatch = {}) {
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, 'users/' + driverUid), profile);
    await setDoc(doc(db, 'users/' + touristUid), {uid: touristUid, status: 'active', accountType: 'tourist',
      registrationStatus: 'approved', accountStatus: 'active'});
    await setDoc(doc(db, 'users/other-driver'), {...driver(), uid: 'other-driver'});
    await setDoc(doc(db, tripPath), {id: 'start-regression', creatorId: touristUid, creatorType: 'tourist',
      creatorName: 'Tourist', status: 'accepted', acceptedDriverId: driverUid, acceptedBidId: driverUid,
      scheduledAt: Timestamp.fromMillis(Date.now() + 3600000), excludedDriverIds: [], cancellationCount: 0,
      startRequestedAt: null, startAutoStartAt: null, startedAt: null, startMethod: null,
      endRequestedAt: null, endAutoCompleteAt: null, endedAt: null, completionMethod: null,
      updatedAt: serverTimestamp(), ...tripPatch});
    await setDoc(doc(db, tripPath + '/bids/' + driverUid), {
      id: driverUid, tripId: 'start-regression', driverId: driverUid, status: 'accepted', updatedAt: serverTimestamp()});
    // No cancellation history exists: start must not require reciprocal cancellation documents.
  });
}
function shifted(at, seconds) { return new Timestamp(at.seconds + seconds, at.nanoseconds); }
function parentPayload(at, patch = {}) {
  return {status: 'start_requested', startRequestedAt: at, startAutoStartAt: shifted(at, 180),
    startedAt: null, startMethod: null, updatedAt: serverTimestamp(), ...patch};
}
async function createAnchor(db, actor = driverUid) {
  // Mirror transaction 1, including the same profile and trip reads as Flutter.
  await runTransaction(db, async tx => {
    await tx.get(doc(db, 'users/' + actor));
    await tx.get(doc(db, tripPath));
    tx.set(doc(db, anchorPath), {requestedBy: actor, createdAt: serverTimestamp()});
  });
  return (await getDocFromServer(doc(db, anchorPath))).data().createdAt;
}
async function publishStart(db) {
  // Mirror transaction 2: preserve the stored Timestamp, including nanoseconds.
  await runTransaction(db, async tx => {
    await tx.get(doc(db, 'users/' + driverUid));
    await tx.get(doc(db, tripPath));
    const at = (await tx.get(doc(db, anchorPath))).data().createdAt;
    tx.update(doc(db, tripPath), parentPayload(at));
  });
}
async function seedAnchor(at, requestedBy = driverUid) {
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), anchorPath), {createdAt: at, requestedBy});
  });
}

for (const plan of ['founding_lifetime', 'standard_annual']) {
  test('approved operational ' + plan + ' driver completes both start transactions', async () => {
    await seed(driver({membershipPlan: plan, membershipValidUntil: plan === 'founding_lifetime' ? null :
      Timestamp.fromMillis(Date.now() + 365 * 86400000)}));
    const db = env.authenticatedContext(driverUid).firestore();
    const at = await assertSucceeds(createAnchor(db));
    assert(at instanceof Timestamp);
    await assertSucceeds(publishStart(db));
    const result = (await getDocFromServer(doc(db, tripPath))).data();
    assert.equal(result.status, 'start_requested');
    assert(result.startRequestedAt.isEqual(at));
    assert(result.startAutoStartAt.isEqual(shifted(at, 180)));
    assert.equal(result.startedAt, null);
    assert.equal(result.startMethod, null);
  });
}

for (const [label, patch] of [
  ['draft', {registrationStatus: 'draft'}],
  ['pending approval', {registrationStatus: 'pending_review'}],
  ['correction required', {registrationStatus: 'correction_required'}],
  ['rejected', {registrationStatus: 'rejected'}],
  ['identity pending', {identityVerificationStatus: 'pending'}],
  ['payment pending', {paymentStatus: 'pending'}],
  ['membership pending', {membershipStatus: 'pending'}],
  ['membership expired', {membershipStatus: 'expired'}],
  ['account inactive', {accountStatus: 'inactive'}],
  ['account suspended', {accountStatus: 'suspended'}],
  ['legacy status inactive', {status: 'inactive'}],
  ['annual term expired', {membershipPlan: 'standard_annual', membershipValidUntil: Timestamp.fromMillis(1)}],
  ['annual term missing', {membershipPlan: 'standard_annual'}],
]) {
  test(label + ' denies anchor and direct parent update', async () => {
    await seed(driver(patch));
    const db = env.authenticatedContext(driverUid).firestore();
    await assertDenied(setDoc(doc(db, anchorPath), {requestedBy: driverUid, createdAt: serverTimestamp()}));
    const at = Timestamp.now();
    await seedAnchor(at);
    // Direct write ensures we test parent authorization, not merely a denied read.
    await assertDenied(updateDoc(doc(db, tripPath), parentPayload(at)));
  });
}

test('wrong driver cannot create anchor or publish start', async () => {
  await seed();
  const db = env.authenticatedContext('other-driver').firestore();
  await assertDenied(setDoc(doc(db, anchorPath), {requestedBy: 'other-driver', createdAt: serverTimestamp()}));
  const at = Timestamp.now();
  await seedAnchor(at, 'other-driver');
  await assertDenied(updateDoc(doc(db, tripPath), parentPayload(at)));
});
test('unaccepted trip denies both writes', async () => {
  await seed(driver(), {status: 'open', acceptedDriverId: null, acceptedBidId: null});
  const db = env.authenticatedContext(driverUid).firestore();
  await assertDenied(setDoc(doc(db, anchorPath), {requestedBy: driverUid, createdAt: serverTimestamp()}));
  const at = Timestamp.now(); await seedAnchor(at);
  await assertDenied(updateDoc(doc(db, tripPath), parentPayload(at)));
});
test('missing anchor cannot authorize parent transition', async () => {
  await seed();
  await assertDenied(updateDoc(doc(env.authenticatedContext(driverUid).firestore(), tripPath), parentPayload(Timestamp.now())));
});
test('anchor actor must match the accepted driver', async () => {
  await seed(); const at = Timestamp.now(); await seedAnchor(at, touristUid);
  await assertDenied(updateDoc(doc(env.authenticatedContext(driverUid).firestore(), tripPath), parentPayload(at)));
});
for (const age of [30, 61, -3600]) {
  test('anchor age ' + age + ' seconds preserves the 60-second freshness window', async () => {
    await seed();
    const db = env.authenticatedContext(driverUid).firestore();
    const committed = await createAnchor(db);
    const at = shifted(committed, -age);
    // Privileged fixture adjustment avoids sleeps and still exercises actual rules.
    await seedAnchor(at);
    const write = updateDoc(doc(db, tripPath), parentPayload(at));
    if (age === 30) { await assertSucceeds(write); } else { await assertDenied(write); }
  });
}
for (const [label, mutate] of [
  ['different request timestamp', at => ({startRequestedAt: shifted(at, 1)})],
  ['deadline before three minutes', at => ({startAutoStartAt: shifted(at, 179)})],
  ['deadline after three minutes', at => ({startAutoStartAt: shifted(at, 181)})],
  ['non-null startedAt', at => ({startedAt: at})],
  ['forged startMethod', () => ({startMethod: 'creator_confirmed'})],
  ['non-server updatedAt', () => ({updatedAt: Timestamp.fromMillis(1)})],
  ['unrelated notes', () => ({notes: 'Changed during start'})],
  ['changed assignment', () => ({acceptedDriverId: 'other-driver'})],
]) {
  test(label + ' is denied on the parent', async () => {
    await seed();
    const db = env.authenticatedContext(driverUid).firestore();
    const at = await createAnchor(db);
    await assertDenied(updateDoc(doc(db, tripPath), parentPayload(at, mutate(at))));
  });
}
test('legacy active driver behavior remains unchanged', async () => {
  await seed({uid: driverUid, status: 'active', accountType: 'driver'});
  const db = env.authenticatedContext(driverUid).firestore();
  await assertSucceeds(createAnchor(db));
  await assertSucceeds(publishStart(db));
});

// Acceptance and cancellation retain their reciprocal writes and actor checks.
async function seedOpenWithSubmittedBid() {
  await seed(driver(), {status: 'open', acceptedBidId: null, acceptedDriverId: null});
  await env.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), tripPath + '/bids/' + driverUid), {status: 'submitted'});
  });
}
function acceptanceBatch(db, extra = {}) {
  const batch = writeBatch(db);
  batch.update(doc(db, tripPath), {status: 'accepted', acceptedDriverId: driverUid,
    acceptedBidId: driverUid, updatedAt: serverTimestamp(), ...extra});
  batch.update(doc(db, tripPath + '/bids/' + driverUid), {status: 'accepted', updatedAt: serverTimestamp()});
  return batch;
}
test('creator acceptance still requires and accepts reciprocal selected-bid update', async () => {
  await seedOpenWithSubmittedBid();
  const db = env.authenticatedContext(touristUid).firestore();
  await assertDenied(updateDoc(doc(db, tripPath), {status: 'accepted', acceptedDriverId: driverUid,
    acceptedBidId: driverUid, updatedAt: serverTimestamp()}));
  await assertSucceeds(acceptanceBatch(db).commit());
  assert.equal((await getDocFromServer(doc(db, tripPath))).data().status, 'accepted');
  assert.equal((await getDocFromServer(doc(db, tripPath + '/bids/' + driverUid))).data().status, 'accepted');
});
test('driver cannot perform creator acceptance even with reciprocal bid write', async () => {
  await seedOpenWithSubmittedBid();
  await assertDenied(acceptanceBatch(env.authenticatedContext(driverUid).firestore()).commit());
});
test('acceptance cannot carry lifecycle fields', async () => {
  await seedOpenWithSubmittedBid();
  await assertDenied(acceptanceBatch(env.authenticatedContext(touristUid).firestore(),
    {startRequestedAt: Timestamp.now()}).commit());
});

function cancellationPayload(actor) {
  const byDriver = actor === driverUid;
  return {status: byDriver ? 'open' : 'cancelled', acceptedBidId: null, acceptedDriverId: null,
    excludedDriverIds: byDriver ? [driverUid] : [], cancellationCount: 1,
    lastCancellationBy: actor, lastCancellationReason: byDriver ? 'Vehicle issue' : 'Plans changed',
    lastCancellationAt: serverTimestamp(), updatedAt: serverTimestamp()};
}
function acceptedCancellationBatch(db, actor, {includeBid = true, includeHistory = true, extra = {}} = {}) {
  const byDriver = actor === driverUid;
  const batch = writeBatch(db);
  batch.update(doc(db, tripPath), {...cancellationPayload(actor), ...extra});
  if (includeBid) {
    batch.update(doc(db, tripPath + '/bids/' + driverUid), {
      status: byDriver ? 'cancelled' : 'trip_cancelled', updatedAt: serverTimestamp()});
  }
  if (includeHistory) {
    batch.set(doc(db, tripPath + '/cancellations/' + driverUid), {
      id: driverUid, tripId: 'start-regression', cancelledByUid: actor,
      cancelledByRole: byDriver ? 'driver' : 'creator', reasonCode: byDriver ? 'vehicle_issue' : 'plans_changed',
      reasonText: '', penaltyApplied: true, previousStatus: 'accepted',
      resultingStatus: byDriver ? 'open' : 'cancelled', cancelledAt: serverTimestamp()});
  }
  return batch;
}
for (const actor of [driverUid, touristUid]) {
  test('accepted cancellation retains reciprocal history/bid checks for ' + actor, async () => {
    await seed(); // Scheduled in one hour: existing two-hour penalty remains true.
    const db = env.authenticatedContext(actor).firestore();
    await assertDenied(acceptedCancellationBatch(db, actor, {includeBid: false}).commit());
    await assertDenied(acceptedCancellationBatch(db, actor, {includeHistory: false}).commit());
    await assertSucceeds(acceptedCancellationBatch(db, actor).commit());
    // Fixture inspection only: a reopened trip is no longer readable by its former driver.
    await env.withSecurityRulesDisabled(async context => {
      const inspect = context.firestore();
      const trip = (await getDocFromServer(doc(inspect, tripPath))).data();
      assert.equal(trip.status, actor === driverUid ? 'open' : 'cancelled');
      assert.equal(trip.acceptedDriverId, null);
      assert.deepEqual(trip.excludedDriverIds, actor === driverUid ? [driverUid] : []);
      assert.equal(trip.cancellationCount, 1);
      const history = (await getDocFromServer(doc(inspect, tripPath + '/cancellations/' + driverUid))).data();
      assert.equal(history.penaltyApplied, true);
      assert.equal(history.cancelledByUid, actor);
    });
  });
}
test('accepted cancellation cannot carry lifecycle fields', async () => {
  await seed();
  await assertDenied(acceptedCancellationBatch(env.authenticatedContext(driverUid).firestore(), driverUid,
    {extra: {startRequestedAt: Timestamp.now()}}).commit());
});
test('unassigned creator cancellation preserves its history requirement', async () => {
  await seed(driver(), {status: 'open', acceptedBidId: null, acceptedDriverId: null});
  const db = env.authenticatedContext(touristUid).firestore();
  const payload = {status: 'cancelled', lastCancellationBy: touristUid,
    lastCancellationReason: 'Plans changed', lastCancellationAt: serverTimestamp(), updatedAt: serverTimestamp()};
  await assertDenied(updateDoc(doc(db, tripPath), payload));
  const batch = writeBatch(db);
  batch.update(doc(db, tripPath), payload);
  batch.set(doc(db, tripPath + '/cancellations/' + touristUid), {
    id: touristUid, tripId: 'start-regression', cancelledByUid: touristUid, cancelledByRole: 'creator',
    reasonCode: 'plans_changed', reasonText: '', penaltyApplied: false,
    previousStatus: 'open', resultingStatus: 'cancelled', cancelledAt: serverTimestamp()});
  await assertSucceeds(batch.commit());
  assert.equal((await getDocFromServer(doc(db, tripPath))).data().status, 'cancelled');
});
for (const [from, to] of [['accepted', 'in_progress'], ['accepted', 'completed'],
  ['start_requested', 'completed'], ['in_progress', 'completed']]) {
  test('unsupported state shortcut ' + from + ' -> ' + to + ' is denied', async () => {
    await seed(driver(), {status: from});
    await assertDenied(updateDoc(doc(env.authenticatedContext(driverUid).firestore(), tripPath),
      {status: to, updatedAt: serverTimestamp()}));
  });
}

test('all four lifecycle routes retain confirmation roles, end deadline and completion writes', async () => {
  await seed();
  await env.withSecurityRulesDisabled(async context => {
    for (const uid of [driverUid, touristUid]) {
      await updateDoc(doc(context.firestore(), 'users/' + uid), {
        completedTripsCount: 0, ratingsCount: 0, ratingStarsTotal: 0, averageRating: 0});
    }
  });
  const driverDb = env.authenticatedContext(driverUid).firestore();
  const creatorDb = env.authenticatedContext(touristUid).firestore();
  await assertSucceeds(createAnchor(driverDb));
  await assertSucceeds(publishStart(driverDb));
  const confirmStart = {status: 'in_progress', startedAt: serverTimestamp(),
    startMethod: 'creator_confirmed', updatedAt: serverTimestamp()};
  await assertDenied(updateDoc(doc(driverDb, tripPath), confirmStart));
  await assertSucceeds(updateDoc(doc(creatorDb, tripPath), confirmStart));
  const endPath = tripPath + '/lifecycle_requests/end';
  await assertSucceeds(setDoc(doc(driverDb, endPath), {requestedBy: driverUid, createdAt: serverTimestamp()}));
  const at = (await getDocFromServer(doc(driverDb, endPath))).data().createdAt;
  const requestEnd = {status: 'end_requested', endRequestedAt: at, endAutoCompleteAt: shifted(at, 1800),
    endedAt: null, completionMethod: null, updatedAt: serverTimestamp()};
  await assertDenied(updateDoc(doc(driverDb, tripPath), {...requestEnd, endAutoCompleteAt: shifted(at, 1799)}));
  await assertSucceeds(updateDoc(doc(driverDb, tripPath), requestEnd));
  const complete = {status: 'completed', endedAt: serverTimestamp(),
    completionMethod: 'creator_confirmed', updatedAt: serverTimestamp()};
  await assertDenied(updateDoc(doc(driverDb, tripPath), complete));
  await assertDenied(updateDoc(doc(creatorDb, tripPath), complete)); // Reciprocal metrics are required.
  const batch = writeBatch(creatorDb);
  batch.update(doc(creatorDb, tripPath), complete);
  for (const uid of [driverUid, touristUid]) {
    batch.update(doc(creatorDb, 'users/' + uid), {completedTripsCount: 1, lastCompletedTripId: 'start-regression'});
    batch.set(doc(creatorDb, 'user_reputation/' + uid), {completedTripsCount: 1, ratingsCount: 0,
      ratingStarsTotal: 0, averageRating: 0, cancellationCount: null, cancellationRate: null});
  }
  await assertSucceeds(batch.commit());
  assert.equal((await getDocFromServer(doc(creatorDb, tripPath))).data().status, 'completed');
});
