import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {before, after, beforeEach, test} from 'node:test';
import {initializeTestEnvironment, assertSucceeds, assertFails} from '@firebase/rules-unit-testing';
import {doc, setDoc, updateDoc} from 'firebase/firestore';
import {ref, uploadBytes, getMetadata, listAll, deleteObject} from 'firebase/storage';

let env;
let sequence = 0;
const objectPath = (uid, revision, type) => `registration_evidence/${uid}/${revision}/${type}/${(++sequence).toString(16).padStart(32, '0')}.jpg`;
const metadata = (type, revision = 2) => ({contentType: 'image/jpeg', customMetadata: {
  ownerUid: 'owner', applicationRevision: String(revision), evidenceType: type, width: '1000', height: '800',
}});
function endpoint(name) {
  const value = process.env[name];
  assert.match(value ?? '', /^(localhost|127\.0\.0\.1):[0-9]+$/);
  const [host, port] = value.split(':'); return {host, port: Number(port)};
}
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-ceylon-upgrade-storage',
    firestore: {...endpoint('FIRESTORE_EMULATOR_HOST'), rules: await readFile(new URL('../firestore.rules', import.meta.url), 'utf8')},
    storage: {...endpoint('FIREBASE_STORAGE_EMULATOR_HOST'), rules: await readFile(new URL('../storage.rules', import.meta.url), 'utf8')},
  });
});
after(async () => { if (env) await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(), 'users/owner'), {
    uid: 'owner', accountType: 'tourist', status: 'active', accountStatus: 'active', registrationStatus: 'approved',
    applicationRevision: 1, driverUpgradeStatus: 'draft',
  }));
});
const storage = (uid = 'owner', claims = {}) => env.authenticatedContext(uid, claims).storage();
// Rule tests validate object policy, not image decoding (covered by Flutter compression tests).
const bytes = new Uint8Array([255, 216, 255, 217]);
test('upgrade DL/selfie owner uploads; owner/admin review; unrelated/support denied and no listing', async () => {
  for (const type of ['driving_licence', 'selfie']) {
    const path = objectPath('owner', 2, type);
    await assertSucceeds(uploadBytes(ref(storage(), path), bytes, metadata(type)));
    await assertSucceeds(getMetadata(ref(storage(), path)));
    await assertSucceeds(getMetadata(ref(storage('admin', {admin: true}), path)));
    // Missing admin claims must deny unrelated readers without property evaluation errors.
    // Check emulator output for evaluation warnings during manual verification.
    await assertFails(getMetadata(ref(storage('other', {}), path)));
    await assertFails(getMetadata(ref(storage('non-admin', {admin: false}), path)));
    await assertFails(getMetadata(ref(env.unauthenticatedContext().storage(), path)));
    await assertFails(getMetadata(ref(storage('support', {supportAdmin: true}), path)));
    await assertFails(listAll(ref(storage(), 'registration_evidence/owner/2')));
    await assertFails(uploadBytes(ref(storage(), path), bytes, metadata(type)));
    await assertFails(deleteObject(ref(storage(), path)));
  }
});
test('wrong owner/revision/type/size and non-editable state uploads are denied', async () => {
  await assertFails(uploadBytes(ref(storage(), objectPath('other', 2, 'selfie')), bytes, metadata('selfie')));
  await assertFails(uploadBytes(ref(storage(), objectPath('owner', 1, 'selfie')), bytes, metadata('selfie', 1)));
  await assertFails(uploadBytes(ref(storage(), objectPath('owner', 2, 'selfie')), bytes, {...metadata('selfie'), contentType: 'application/zip'}));
  await assertFails(uploadBytes(ref(storage(), objectPath('owner', 2, 'selfie')), new Uint8Array(1572865), metadata('selfie')));
  await assertFails(uploadBytes(ref(storage(), objectPath('owner', 2, 'driving_licence')), new Uint8Array(2097153), metadata('driving_licence')));
  for (const patch of [{ownerUid: 'other'}, {applicationRevision: '1'}, {evidenceType: 'nic'},
    {width: '1601'}, {height: '399'}, {extra: 'not-allowed'}]) {
    await assertFails(uploadBytes(ref(storage(), objectPath('owner', 2, 'selfie')), bytes,
      {...metadata('selfie'), customMetadata: {...metadata('selfie').customMetadata, ...patch}}));
  }
  await assertFails(uploadBytes(ref(storage(), objectPath('owner', 3, 'selfie')), bytes, metadata('selfie', 3)));
  for (const status of ['pending_review', 'approved']) {
    await env.withSecurityRulesDisabled(ctx => updateDoc(doc(ctx.firestore(), 'users/owner'), {driverUpgradeStatus: status}));
    await assertFails(uploadBytes(ref(storage(), objectPath('owner', 2, 'selfie')), bytes, metadata('selfie')));
  }
});

test('correction uploads use the upcoming revision; previous evidence stays private and immutable', async () => {
  const old = objectPath('owner', 2, 'selfie');
  await assertSucceeds(uploadBytes(ref(storage(), old), bytes, metadata('selfie')));
  await env.withSecurityRulesDisabled(ctx => updateDoc(doc(ctx.firestore(), 'users/owner'), {
    applicationRevision: 2, driverUpgradeStatus: 'correction_required',
  }));
  await assertSucceeds(uploadBytes(ref(storage(), objectPath('owner', 3, 'selfie')), bytes, metadata('selfie', 3)));
  await assertFails(uploadBytes(ref(storage(), objectPath('owner', 2, 'selfie')), bytes, metadata('selfie')));
  await assertSucceeds(getMetadata(ref(storage(), old)));
  await assertSucceeds(getMetadata(ref(storage('admin', {admin: true}), old)));
  await assertFails(getMetadata(ref(storage('other'), old)));
  await assertFails(deleteObject(ref(storage(), old)));
  await assertFails(uploadBytes(ref(storage(), old), bytes, metadata('selfie')));
});
