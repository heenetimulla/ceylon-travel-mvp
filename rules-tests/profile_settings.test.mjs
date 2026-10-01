import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {before, after, beforeEach, test} from 'node:test';
import {initializeTestEnvironment, assertSucceeds, assertFails} from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc, updateDoc, deleteField, serverTimestamp} from 'firebase/firestore';

let env;
const path = 'users/owner';
const fresh = () => Math.floor(Date.now() / 1000);
const profile = {
  uid: 'owner', accountType: 'tourist', fullName: 'Applicant', city: 'Kandy',
  phoneNumber: '+94771234567', email: 'owner@example.test', status: 'active',
  registrationStatus: 'approved', accountStatus: 'active', applicationRevision: 1,
  identityVerificationStatus: 'verified', paymentStatus: 'pending', membershipStatus: 'pending',
  completedTripsCount: 0, cancelledTripsCount: 0, cancellationCount: 0,
  cancellationRate: 0, averageRating: 0, ratingsCount: 0, ratingStarsTotal: 0,
};
before(async () => {
  const endpoint = process.env.FIRESTORE_EMULATOR_HOST;
  assert.match(endpoint ?? '', /^(localhost|127\.0\.0\.1):[0-9]+$/);
  const [host, port] = endpoint.split(':');
  env = await initializeTestEnvironment({projectId: 'demo-ceylon-profile-rules', firestore: {
    host, port: Number(port), rules: await readFile(new URL('../firestore.rules', import.meta.url), 'utf8'),
  }});
});
after(async () => { if (env) await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(), path), profile));
});
const ref = (uid = 'owner', claims = {}) => doc(env.authenticatedContext(uid, claims).firestore(), path);

test('owner reads current profile and changes only safe display fields', async () => {
  await assertSucceeds(getDoc(ref()));
  await assertSucceeds(updateDoc(ref(), {fullName: 'Updated Name', city: 'Galle', updatedAt: serverTimestamp()}));
  const data = (await getDoc(ref())).data();
  assert.equal(data.fullName, 'Updated Name');
  assert.equal(data.phoneNumber, profile.phoneNumber);
  assert.equal(data.registrationStatus, 'approved');
});
test('unrelated user and signed-out user cannot edit profile', async () => {
  await assertFails(updateDoc(ref('other', {auth_time: fresh()}), {fullName: 'Other', updatedAt: serverTimestamp()}));
  await assertFails(getDoc(ref('other')));
  await assertFails(updateDoc(doc(env.unauthenticatedContext().firestore(), path), {city: 'Other', updatedAt: serverTimestamp()}));
});
test('phone requires recent trusted auth_time and does not change any other account state', async () => {
  const patch = {phoneNumber: '+94777654321', updatedAt: serverTimestamp()};
  await assertFails(updateDoc(ref(), patch));
  await assertFails(updateDoc(ref('owner', {auth_time: fresh() - 600}), patch));
  await assertFails(updateDoc(ref('owner', {auth_time: fresh() + 600}), patch));
  await assertSucceeds(updateDoc(ref('owner', {auth_time: fresh()}), patch));
  const after = (await getDoc(ref())).data();
  assert.equal(after.phoneNumber, patch.phoneNumber);
  for (const [key, value] of Object.entries(profile)) {
    if (key !== 'phoneNumber') assert.deepEqual(after[key], value);
  }
});
test('empty/invalid/deleted contact and invalid display values denied', async () => {
  for (const patch of [{phoneNumber: ''}, {phoneNumber: 'words'}, {phoneNumber: deleteField()},
    {fullName: ''}, {fullName: '  '}, {fullName: 'x'.repeat(121)}, {city: 'x'.repeat(101)},
    {fullName: deleteField()}, {updatedAt: null}]) {
    await assertFails(updateDoc(ref('owner', {auth_time: fresh()}), {updatedAt: serverTimestamp(), ...patch}));
  }
});
const forbidden = {
  uid: 'other', accountType: 'driver', accountStatus: 'suspended', registrationStatus: 'draft',
  identityVerificationStatus: 'pending', paymentStatus: 'verified', membershipStatus: 'active',
  membershipPlan: 'founding_lifetime', membershipType: 'founding_lifetime', registrationNumber: 1,
  driverRegistrationNumber: 1, applicationRevision: 2, admin: true, supportAdmin: true,
  email: 'forged@example.test', profilePhotoPath: 'unreviewed', nicNumber: 'private',
  drivingLicenceNumber: 'private', evidence: {}, verification: {},
  registrationFeePaidLkr: 3500, annualRenewalRequired: false, annualRenewalFeeLkr: 0,
  membershipValidUntil: null, applicationSubmittedAt: null, status: 'inactive',
  completedTripsCount: 1, cancelledTripsCount: 1, cancellationCount: 1, cancellationRate: 1,
  ratingsCount: 1, ratingStarsTotal: 5, averageRating: 5,
};
for (const [field, value] of Object.entries(forbidden)) {
  test(`profile edit cannot alter ${field}, even with fresh auth or admin claim`, async () => {
    for (const claims of [{auth_time: fresh()}, {auth_time: fresh(), admin: true}]) {
      await assertFails(updateDoc(ref('owner', claims), {[field]: value, fullName: 'Updated Name', updatedAt: serverTimestamp()}));
    }
  });
}
test('registration/payment evidence/history remain client-immutable', async () => {
  const db = env.authenticatedContext('owner', {auth_time: fresh()}).firestore();
  for (const target of ['registration_applications/owner', 'registration_applications/owner/submissions/1',
    'driver_verifications/owner', 'users/owner/payments/p', 'users/owner/admin_history/h']) {
    await assertFails(setDoc(doc(db, target), {phoneNumber: '+94777654321'}));
  }
});
