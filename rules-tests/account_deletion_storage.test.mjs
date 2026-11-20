import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {before, after, beforeEach, test} from 'node:test';
import {initializeTestEnvironment, assertSucceeds, assertFails} from '@firebase/rules-unit-testing';
import {doc, setDoc} from 'firebase/firestore';
import {ref, uploadBytes, getMetadata, deleteObject} from 'firebase/storage';

let env;
function endpoint(name) {
  const value = process.env[name];
  assert.match(value ?? '', /^(localhost|127\.0\.0\.1):[0-9]+$/);
  const [host, port] = value.split(':'); return {host, port: Number(port)};
}
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-ceylon-travel',
    firestore: {...endpoint('FIRESTORE_EMULATOR_HOST'), rules: await readFile(new URL('../firestore.rules', import.meta.url), 'utf8')},
    storage: {...endpoint('FIREBASE_STORAGE_EMULATOR_HOST'), rules: await readFile(new URL('../storage.rules', import.meta.url), 'utf8')},
  });
});
after(async () => { if (env) await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); await env.clearStorage(); });
const storage = (uid = 'owner', claims = {}) => env.authenticatedContext(uid, claims).storage();
const bytes = new Uint8Array([255, 216, 255, 217]);
const paymentPath = (uid = 'owner', paymentId = 'pay', file = 'c'.repeat(32)) =>
  `payment_evidence/${uid}/${paymentId}/${file}.jpg`;
const paymentMetadata = (uid = 'owner', paymentId = 'pay', extra = {}) => ({
  contentType: 'image/jpeg', customMetadata: {
    ownerUid: uid, paymentId, evidenceType: 'payment_slip', width: '1000', height: '800', ...extra,
  },
});
async function seedPendingRegistrationPayment(overrides = {}) {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(), 'users/owner'), {
      accountType: 'driver', status: 'active', accountStatus: 'pending_approval',
      registrationStatus: 'approved', identityVerificationStatus: 'verified',
      paymentStatus: 'pending', membershipStatus: 'pending', currentRegistrationPaymentId: 'pay',
      ...overrides.user,
    });
    await setDoc(doc(ctx.firestore(), `users/owner/payments/${overrides.paymentId ?? 'pay'}`), {
      paymentType: 'registration', status: 'pending', claimSubmitted: false, ...overrides.payment,
    });
  });
}

test('valid pending registration payment slip upload is allowed within the two-document budget', async () => {
  await seedPendingRegistrationPayment();
  const path = paymentPath();
  await assertSucceeds(uploadBytes(ref(storage(), path), bytes, paymentMetadata()));
  await assertSucceeds(getMetadata(ref(storage(), path)));
});

test('payment slip upload rejects wrong owner, payment identity, state, claim and malformed metadata', async () => {
  await seedPendingRegistrationPayment();
  await assertFails(uploadBytes(ref(storage('other'), paymentPath()), bytes, paymentMetadata()));
  await assertFails(uploadBytes(ref(storage(), paymentPath('owner', 'other')), bytes, paymentMetadata('owner', 'other')));
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(), 'users/owner/payments/trip'), {
      paymentType: 'trip', status: 'pending', claimSubmitted: false,
    });
    await setDoc(doc(ctx.firestore(), 'users/owner/payments/claimed'), {
      paymentType: 'registration', status: 'pending', claimSubmitted: true,
    });
    await setDoc(doc(ctx.firestore(), 'users/owner/payments/rejected'), {
      paymentType: 'registration', status: 'rejected', claimSubmitted: false,
    });
  });
  for (const [paymentId, userPatch] of [
    ['trip', {currentRegistrationPaymentId: 'trip'}],
    ['claimed', {currentRegistrationPaymentId: 'claimed'}],
    ['rejected', {currentRegistrationPaymentId: 'rejected'}],
  ]) {
    await env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(), 'users/owner'), {
      accountType: 'driver', status: 'active', accountStatus: 'pending_approval', registrationStatus: 'approved',
      identityVerificationStatus: 'verified', paymentStatus: 'pending', membershipStatus: 'pending',
      currentRegistrationPaymentId: paymentId, ...userPatch,
    }));
    await assertFails(uploadBytes(ref(storage(), paymentPath('owner', paymentId)), bytes, paymentMetadata('owner', paymentId)));
  }
  await seedPendingRegistrationPayment();
  await assertFails(uploadBytes(ref(storage(), 'payment_evidence/owner/pay/not-a-hash.jpg'), bytes, paymentMetadata()));
  await assertFails(uploadBytes(ref(storage(), paymentPath()), bytes, paymentMetadata('owner', 'pay', {extra: 'not-allowed'})));
  await assertFails(uploadBytes(ref(storage(), paymentPath()), new Uint8Array(2097153), paymentMetadata()));
});

test('deleted owner cannot read private evidence with stale token; primary admin review stays protected', async () => {
  for (const prefix of ['driver_evidence', 'registration_evidence', 'payment_evidence']) {
    const path = prefix === 'payment_evidence' ? prefix + '/owner/pay/' + 'a'.repeat(32) + '.jpg'
      : prefix + '/owner/1/selfie/' + 'a'.repeat(32) + '.jpg';
    await env.withSecurityRulesDisabled(async ctx => {
      await setDoc(doc(ctx.firestore(), 'account_deletion_blocks/owner'), {blockedAt: new Date()});
      await uploadBytes(ref(ctx.storage(), path), bytes, {contentType: 'image/jpeg'});
    });
    await assertFails(getMetadata(ref(storage(), path)));
    await assertFails(getMetadata(ref(storage('other'), path)));
    await assertFails(getMetadata(ref(storage('support', {supportAdmin: true}), path)));
    await assertSucceeds(getMetadata(ref(storage('admin', {admin: true}), path)));
    await assertFails(deleteObject(ref(storage('admin', {admin: true}), path)));
  }
});
test('approved/completed deletion prevents evidence uploads despite stale eligibility fields', async () => {
  for (const status of ['approved', 'completed']) {
    await env.withSecurityRulesDisabled(async ctx => {
      await setDoc(doc(ctx.firestore(), 'account_deletion_blocks/owner'), {blockedAt: new Date()});
      await setDoc(doc(ctx.firestore(), 'users/owner'), {
        accountType: 'driver', status: 'active', accountStatus: 'active', registrationStatus: 'approved',
        currentRegistrationPaymentId: 'pay', applicationRevision: 1, deletionStatus: status,
      });
      await setDoc(doc(ctx.firestore(), 'users/owner/payments/pay'), {
        paymentType: 'registration', status: 'pending', claimSubmitted: false,
      });
    });
    await assertFails(uploadBytes(ref(storage(), 'payment_evidence/owner/pay/' + 'b'.repeat(32) + '.jpg'), bytes, {
      contentType: 'image/jpeg', customMetadata: {ownerUid: 'owner', paymentId: 'pay',
        evidenceType: 'payment_slip', width: '1000', height: '800'},
    }));
    await assertFails(uploadBytes(ref(storage(), 'registration_evidence/owner/2/selfie/' + 'b'.repeat(32) + '.jpg'), bytes, {
      contentType: 'image/jpeg', customMetadata: {ownerUid: 'owner', applicationRevision: '2',
        evidenceType: 'selfie', width: '1000', height: '800'},
    }));
  }
});
