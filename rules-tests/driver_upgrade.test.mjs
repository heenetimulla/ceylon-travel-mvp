import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {before, after, beforeEach, test} from 'node:test';
import {initializeTestEnvironment, assertSucceeds, assertFails} from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc, updateDoc, serverTimestamp} from 'firebase/firestore';

let env;
const user = {uid: 'owner', accountType: 'tourist', status: 'active', registrationStatus: 'approved',
  accountStatus: 'active', applicationRevision: 1, identityVerificationStatus: 'verified',
  fullName: 'Applicant', phoneNumber: '+94771234567', city: 'Kandy'};
before(async () => {
  const endpoint = process.env.FIRESTORE_EMULATOR_HOST;
  assert.match(endpoint ?? '', /^(localhost|127\.0\.0\.1):[0-9]+$/);
  const [host, port] = endpoint.split(':');
  env = await initializeTestEnvironment({projectId: 'demo-ceylon-upgrade-rules', firestore: {host, port: Number(port),
    rules: await readFile(new URL('../firestore.rules', import.meta.url), 'utf8')}});
});
after(async () => { if (env) await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(), 'users/owner'), user));
});
const db = (uid = 'owner', claims = {}) => env.authenticatedContext(uid, claims).firestore();
const command = (action, payload = {}) => ({action, payload, actorUid: 'owner', expectedRevision: 1,
  reason: '', status: 'pending', createdAt: serverTimestamp()});
const payload = () => ({profile: {vehicleType: 'Any', vehicleNumber: 'ABC-1234', vehicleDetails: 'Toyota sedan',
  operatingArea: 'Colombo', availableAreas: 'Western'}, drivingLicenceNumber: 'B1234567',
  evidence: {driving_licence: `registration_evidence/owner/2/driving_licence/${'a'.repeat(32)}.jpg`,
    selfie: `registration_evidence/owner/2/selfie/${'b'.repeat(32)}.jpg`}, agreementVersion: '1.1', agreementAccepted: true});
async function state(status) {
  await env.withSecurityRulesDisabled(ctx => updateDoc(doc(ctx.firestore(), 'users/owner'), {driverUpgradeStatus: status}));
}

test('eligible owner requests draft through immutable operation only', async () => {
  const ref = doc(db(), 'users/owner/application_operations/start');
  await assertSucceeds(setDoc(ref, command('start_driver_upgrade')));
  await assertFails(updateDoc(ref, {status: 'succeeded'}));
  await assertFails(setDoc(doc(db('other'), 'users/owner/application_operations/forged'),
    {...command('start_driver_upgrade'), actorUid: 'other'}));
  await assertFails(setDoc(doc(db(), 'registration_applications/owner'), {purpose: 'driver_upgrade', registrationStatus: 'draft'}));
  assert.equal((await getDoc(doc(db(), 'users/owner'))).data().accountType, 'tourist');
});
test('pending and existing upgrade states cannot start a duplicate draft', async () => {
  for (const status of ['draft', 'pending_review', 'correction_required', 'rejected', 'approved']) {
    await state(status);
    await assertFails(setDoc(doc(db(), `users/owner/application_operations/start-${status}`), command('start_driver_upgrade')));
  }
});
test('only editable current upgrade revision accepts submission with current agreement', async () => {
  for (const status of ['draft', 'correction_required', 'rejected']) {
    await state(status);
    await assertSucceeds(setDoc(doc(db(), `users/owner/application_operations/submit-${status}`), command('submit_driver_upgrade', payload())));
  }
  for (const status of ['pending_review', 'approved']) {
    await state(status);
    await assertFails(setDoc(doc(db(), `users/owner/application_operations/submit-${status}`), command('submit_driver_upgrade', payload())));
  }
  await state('draft');
  for (const patch of [{agreementVersion: '1.0'}, {agreementAccepted: false}, {reviewedBy: 'admin'}, {identitySourceRevision: 1}]) {
    await assertFails(setDoc(doc(db(), 'users/owner/application_operations/bad'), command('submit_driver_upgrade', {...payload(), ...patch})));
  }
  await assertFails(setDoc(doc(db(), 'users/owner/application_operations/stale'),
    {...command('submit_driver_upgrade', payload()), expectedRevision: 0}));
  for (const field of ['vehicleType', 'vehicleNumber', 'vehicleDetails', 'operatingArea', 'availableAreas']) {
    const p = payload(); delete p.profile[field];
    await assertFails(setDoc(doc(db(), `users/owner/application_operations/missing-${field}`), command('submit_driver_upgrade', p)));
  }
  for (const field of ['driving_licence', 'selfie']) {
    const p = payload(); delete p.evidence[field];
    await assertFails(setDoc(doc(db(), `users/owner/application_operations/missing-${field}`), command('submit_driver_upgrade', p)));
  }
});
test('upgrade cannot bypass profile reauthentication or inject entitlement/decision fields', async () => {
  await state('draft');
  for (const field of ['phoneNumber', 'fullName', 'accountType', 'accountStatus', 'identityVerificationStatus', 'paymentStatus',
    'membershipStatus', 'membershipPlan', 'driverRegistrationNumber', 'reviewedBy', 'agreementAcceptedAt']) {
    const p = payload(); p.profile[field] = 'forged';
    await assertFails(setDoc(doc(db(), `users/owner/application_operations/forged-${field}`), command('submit_driver_upgrade', p)));
    await assertFails(updateDoc(doc(db(), 'users/owner'), {[field]: 'forged'}));
  }
  for (const field of ['driverUpgradeStatus', 'driverUpgradeSubmittedAt']) {
    await assertFails(updateDoc(doc(db(), 'users/owner'), {[field]: 'approved', updatedAt: serverTimestamp()}));
  }
  await assertFails(setDoc(doc(db(), 'users/owner/application_operations/self-approve'), command('approve')));
  await assertFails(setDoc(doc(db('support', {supportAdmin: true}), 'users/owner/application_operations/support-approve'),
    {...command('approve'), actorUid: 'support'}));
});
test('private upgrade and immutable history are owner/admin-readable but never client-writable', async () => {
  for (const path of ['registration_applications/owner', 'registration_applications/owner/submissions/2', 'registration_applications/owner/history/op']) {
    await env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(), path), {purpose: 'driver_upgrade'}));
    await assertSucceeds(getDoc(doc(db(), path)));
    await assertSucceeds(getDoc(doc(db('admin', {admin: true}), path)));
    await assertFails(getDoc(doc(db('other'), path)));
    await assertFails(getDoc(doc(db('support', {supportAdmin: true}), path)));
    await assertFails(updateDoc(doc(db(), path), {registrationStatus: 'approved'}));
  }
  await assertFails(setDoc(doc(db(), 'identity_registry/fake'), {uid: 'owner'}));
  await assertFails(setDoc(doc(db(), 'system_config/driver_registration_counter'), {nextRegistrationNumber: 1}));
});
