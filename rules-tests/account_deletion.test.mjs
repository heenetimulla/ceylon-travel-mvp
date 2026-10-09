import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {before, after, beforeEach, test} from 'node:test';
import {initializeTestEnvironment, assertSucceeds, assertFails} from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp} from 'firebase/firestore';

let env;
const fresh = () => Math.floor(Date.now() / 1000);
const db = (uid = 'owner', claims = {}) => env.authenticatedContext(uid, claims).firestore();
const requestPath = 'account_deletion_requests/owner';
const request = () => ({
  requesterUid: 'owner', status: 'pending', reason: '', revision: 1,
  requestedAt: serverTimestamp(), updatedAt: serverTimestamp(), reviewedBy: null,
  reviewedAt: null, completionAt: null, processingStage: null, userMessage: null,
});
const operation = (actorUid, action = 'approve') => ({
  actorUid, action, expectedRevision: 1, note: 'Private review', userMessage: '', status: 'pending', createdAt: serverTimestamp(),
});
before(async () => {
  const endpoint = process.env.FIRESTORE_EMULATOR_HOST;
  assert.match(endpoint ?? '', /^(localhost|127\.0\.0\.1):[0-9]+$/);
  const [host, port] = endpoint.split(':');
  env = await initializeTestEnvironment({projectId: 'demo-ceylon-deletion', firestore: {
    host, port: Number(port), rules: await readFile(new URL('../firestore.rules', import.meta.url), 'utf8'),
  }});
});
after(async () => { if (env) await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(), 'users/owner'), {
      uid: 'owner', accountType: 'tourist', fullName: 'Owner', status: 'active',
      accountStatus: 'active', registrationStatus: 'approved',
    });
    await setDoc(doc(ctx.firestore(), 'users/other'), {
      uid: 'other', accountType: 'tourist', fullName: 'Other', status: 'active',
      accountStatus: 'active', registrationStatus: 'approved',
    });
  });
});
test('owner creates and reads only own request with recent reauthentication', async () => {
  await assertFails(setDoc(doc(db(), requestPath), request()));
  await assertFails(setDoc(doc(db('owner', {auth_time: fresh() - 600}), requestPath), request()));
  await assertFails(setDoc(doc(db('owner', {auth_time: fresh() + 600}), requestPath), request()));
  await assertSucceeds(setDoc(doc(db('owner', {auth_time: fresh()}), requestPath), request()));
  await assertSucceeds(getDoc(doc(db(), requestPath)));
  await assertFails(getDoc(doc(db('other'), requestPath)));
  await assertFails(setDoc(doc(db('other', {auth_time: fresh()}), requestPath), request()));
});
test('duplicate pending and owner approval/completion are denied', async () => {
  const owner = db('owner', {auth_time: fresh()});
  await assertSucceeds(setDoc(doc(owner, requestPath), request()));
  await assertFails(setDoc(doc(owner, requestPath), request()));
  for (const status of ['approved', 'completed', 'rejected', 'needs_clarification']) {
    await assertFails(updateDoc(doc(owner, requestPath), {status, updatedAt: serverTimestamp()}));
  }
  await assertFails(deleteDoc(doc(owner, requestPath)));
  await assertFails(setDoc(doc(owner, requestPath + '/operations/self'), operation('owner', 'complete')));
});
test('clarification resubmission increments revision without replacing trusted review metadata', async () => {
  await env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(), requestPath), {
    ...request(), status: 'needs_clarification', revision: 2, reviewedBy: 'admin', reviewedAt: serverTimestamp(),
  }));
  const ref = doc(db('owner', {auth_time: fresh()}), requestPath);
  await assertSucceeds(updateDoc(ref, {status: 'pending', reason: 'Please proceed', revision: 3, updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(ref, {reviewedBy: 'owner', reviewedAt: serverTimestamp()}));
});
test('support-only cannot review; primary admin can enqueue but cannot directly complete', async () => {
  await assertFails(setDoc(doc(db('support', {supportAdmin: true}), requestPath + '/operations/support'), operation('support')));
  const admin = db('admin', {admin: true});
  await assertSucceeds(setDoc(doc(admin, requestPath + '/operations/admin'), operation('admin')));
  await assertFails(setDoc(doc(admin, requestPath), {...request(), status: 'completed'}));
  await assertFails(setDoc(doc(admin, requestPath + '/private/cleanup'), {requestRevision: 1}));
});
test('private notes, cleanup, audit, payment and membership records remain protected', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(), requestPath + '/operations/admin'), operation('admin'));
    await setDoc(doc(ctx.firestore(), requestPath + '/private/cleanup'), {note: 'Private'});
  });
  for (const uid of ['owner', 'other', 'support']) {
    const client = db(uid, uid === 'support' ? {supportAdmin: true} : {});
    await assertFails(getDoc(doc(client, requestPath + '/operations/admin')));
    await assertFails(getDoc(doc(client, requestPath + '/private/cleanup')));
    for (const path of ['users/owner/payments/p', 'users/owner/admin_history/h',
      'driver_registration_registry/1', 'identity_registry/id', 'account_deletion_blocks/owner']) {
      await assertFails(setDoc(doc(client, path), {status: 'completed'}));
      await assertFails(deleteDoc(doc(client, path)));
    }
  }
});
test('completion blocks stale sessions despite restored active profile fields; shared history survives', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(), 'account_deletion_blocks/owner'), {blockedAt: serverTimestamp()});
    await setDoc(doc(ctx.firestore(), requestPath), {...request(), status: 'completed'});
    await setDoc(doc(ctx.firestore(), 'trip_posts/shared'), {
      creatorId: 'other', acceptedDriverId: 'owner', status: 'completed',
    });
  });
  const owner = db('owner', {auth_time: fresh(), admin: true});
  await assertSucceeds(getDoc(doc(owner, requestPath)));
  await assertFails(getDoc(doc(owner, 'users/owner')));
  await assertFails(getDoc(doc(owner, 'trip_posts/shared')));
  await assertFails(updateDoc(doc(owner, 'users/owner'), {fullName: 'Restored', updatedAt: serverTimestamp()}));
  await assertFails(setDoc(doc(owner, 'users/owner/fcm_tokens/' + 'a'.repeat(32)), {
    token: 'token', platform: 'android', enabled: true, permission: 'authorized',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(), lastSeenAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(owner, 'trip_posts/new'), {creatorId: 'owner', status: 'open'}));
  await assertFails(setDoc(doc(owner, requestPath + '/operations/restore'), operation('owner')));
  await assertSucceeds(getDoc(doc(db('other'), 'trip_posts/shared')));
  await assertFails(deleteDoc(doc(db('other'), 'trip_posts/shared')));
});
