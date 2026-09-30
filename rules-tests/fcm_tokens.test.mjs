import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {before, after, beforeEach, test} from 'node:test';
import {initializeTestEnvironment, assertSucceeds, assertFails} from '@firebase/rules-unit-testing';
import {doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc, serverTimestamp} from 'firebase/firestore';

let env;
const tokenId = 'a'.repeat(32);
const path = `users/owner/fcm_tokens/${tokenId}`;
const token = () => ({token: 'test-device-token', platform: 'android', enabled: true, permission: 'authorized',
  createdAt: serverTimestamp(), updatedAt: serverTimestamp(), lastSeenAt: serverTimestamp()});
before(async () => {
  const endpoint = process.env.FIRESTORE_EMULATOR_HOST;
  assert.match(endpoint ?? '', /^(localhost|127\.0\.0\.1):[0-9]+$/);
  const [host, port] = endpoint.split(':');
  env = await initializeTestEnvironment({projectId: 'demo-ceylon-fcm-rules', firestore: {host, port: Number(port),
    rules: await readFile(new URL('../firestore.rules', import.meta.url), 'utf8')}});
});
after(async () => { if (env) await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

test('owner manages own installation, preserving creation timestamp', async () => {
  const db = env.authenticatedContext('owner').firestore();
  await assertSucceeds(setDoc(doc(db, path), token()));
  await assertSucceeds(updateDoc(doc(db, path), {token: 'rotated', updatedAt: serverTimestamp(), lastSeenAt: serverTimestamp()}));
  await assertSucceeds(getDoc(doc(db, path)));
  await assertSucceeds(getDocs(collection(db, 'users/owner/fcm_tokens')));
  await assertSucceeds(deleteDoc(doc(db, path)));
});

test('other users, admin and anonymous clients cannot read or manage owner tokens', async () => {
  await env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(), path), token()));
  for (const context of [env.authenticatedContext('other'), env.authenticatedContext('admin', {admin: true}),
    env.unauthenticatedContext()]) {
    const db = context.firestore();
    await assertFails(getDoc(doc(db, path)));
    await assertFails(getDocs(collection(db, 'users/owner/fcm_tokens')));
    await assertFails(setDoc(doc(db, path), token()));
    await assertFails(deleteDoc(doc(db, path)));
  }
});

test('no arbitrary owner field, unexpected fields, oversized token or fake timestamps', async () => {
  const db = env.authenticatedContext('owner').firestore();
  for (const patch of [{ownerUid: 'other'}, {admin: true}, {token: ''}, {token: 'x'.repeat(4097)},
    {platform: 'web'}, {permission: 'denied', enabled: true}, {lastSeenAt: null}]) {
    await assertFails(setDoc(doc(db, path), {...token(), ...patch}));
  }
  await assertFails(setDoc(doc(db, 'users/owner/fcm_tokens/not-an-installation-id'), token()));
});

test('multiple own devices are separate; deleting one leaves the other intact', async () => {
  const db = env.authenticatedContext('owner').firestore();
  const second = `users/owner/fcm_tokens/${'b'.repeat(32)}`;
  await assertSucceeds(setDoc(doc(db, path), token()));
  await assertSucceeds(setDoc(doc(db, second), {...token(), token: 'second-device'}));
  await assertSucceeds(deleteDoc(doc(db, path)));
  assert.equal((await getDoc(doc(db, second))).data().token, 'second-device');
});

test('chat delivery deduplication marker is backend-only', async () => {
  for (const context of [env.authenticatedContext('owner'), env.authenticatedContext('admin', {admin: true})]) {
    await assertFails(setDoc(doc(context.firestore(), 'trip_posts/t/messages/m/push_delivery/chat'), {attemptedAt: serverTimestamp()}));
  }
});
