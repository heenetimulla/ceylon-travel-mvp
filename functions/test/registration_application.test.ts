import {strict as assert} from "node:assert";
import {test} from "node:test";
import {DocumentData, FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {processRegistrationOperation} from "../src/registration_application";
import {processDriverOperation, registryKey, normalizeIdentity} from "../src/driver_administration";
import {publicProfile} from "../src/public_profiles";

// Optimistic transactional contract fake: all reads precede writes and create is immutable.
class Store {
  docs = new Map<string, DocumentData>();
  revision = 0;
  commitTime = Timestamp.fromDate(new Date('2026-09-23T10:00:00Z'));
  // Model server transforms at commit, not client-provided date values.
  resolve(value: any): any {
    if (value instanceof FieldValue && value.isEqual(FieldValue.serverTimestamp())) return this.commitTime;
    if (value instanceof Timestamp || value == null || typeof value !== 'object') return value;
    if (Array.isArray(value)) return value.map((entry) => this.resolve(entry));
    return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, this.resolve(entry)]));
  }
  doc(path: string): any {
    return {path, id: path.split('/').at(-1), get: async () => this.snapshot(path),
      collection: (name: string) => ({doc: (id: string) => this.doc(`${path}/${name}/${id}`)})};
  }
  snapshot(path: string) { const value = this.docs.get(path); return {exists: value !== undefined, data: () => value && {...value}}; }
  async runTransaction<T>(body: (tx: any) => Promise<T>): Promise<T> {
    for (;;) {
      const revision = this.revision, writes: Array<() => void> = [];
      const result = await body({
        get: async (ref: {path: string}) => { assert.equal(writes.length, 0); return this.snapshot(ref.path); },
        create: (ref: {path: string}, data: DocumentData) => writes.push(() => { assert.ok(!this.docs.has(ref.path)); this.docs.set(ref.path, this.resolve(data)); }),
        set: (ref: {path: string}, data: DocumentData) => writes.push(() => this.docs.set(ref.path, this.resolve(data))),
        update: (ref: {path: string}, data: DocumentData) => writes.push(() => { assert.ok(this.docs.has(ref.path)); this.docs.set(ref.path, {...this.docs.get(ref.path), ...this.resolve(data)}); }),
      });
      if (revision !== this.revision) continue;
      if (writes.length) {
        this.commitTime = Timestamp.fromMillis(this.commitTime.toMillis() + 1000);
        writes.forEach((write) => write()); this.revision++;
      }
      return result;
    }
  }
  get db() { return this as unknown as Firestore; }
}
const secret = 'test-fixture-only-not-production-secret-32-bytes';
const deps = {secret, principal: async (uid: string) => ({uid, admin: uid === 'admin'}),
  evidenceMetadata: async (path: string) => {
    const [, uid, revision, type] = path.split('/');
    return {contentType: 'image/jpeg', size: '100000', generation: '1', timeCreated: '2026-09-22T10:00:00Z',
      metadata: {ownerUid: uid, applicationRevision: revision, evidenceType: type, width: '1200', height: '800'}};
  }};
function applicant(store: Store, uid: string, driver = false) {
  store.docs.set(`users/${uid}`, {uid, accountType: driver ? 'driver' : 'tourist', email: `${uid}@example.com`,
    fullName: 'Applicant', phoneNumber: '0771234567', city: 'Colombo', status: 'active', registrationStatus: 'draft',
    accountStatus: 'pending_approval', applicationRevision: 0, averageRating: 4, completedTripsCount: 7});
}
function payload(uid: string, driver = false, revision = 1): DocumentData {
  return {profile: {fullName: 'Applicant', phoneNumber: '0771234567', city: 'Colombo',
    ...(driver ? {vehicleType: 'Small Car', vehicleNumber: 'ABC-1234', operatingArea: 'Colombo', availableAreas: 'Western'} : {})},
  nicNumber: '901234567V', ...(driver ? {drivingLicenceNumber: 'B1234567'} : {}),
  evidence: Object.fromEntries((driver ? ['nic', 'driving_licence', 'selfie'] : ['nic', 'selfie'])
    .map((type) => [type, `registration_evidence/${uid}/${revision}/${type}/${'a'.repeat(32)}.jpg`])),
  agreementVersion: '1.0', agreementAccepted: true};
}
function enqueue(store: Store, uid: string, id: string, action: string, data: DocumentData = {}, actor = uid, reason = '', revision?: number) {
  store.docs.set(`users/${uid}/application_operations/${id}`, {actorUid: actor, action, payload: data, reason,
    status: 'pending', expectedRevision: revision ?? store.docs.get(`users/${uid}`)!.applicationRevision});
  store.revision++;
}
async function run(store: Store, uid: string, id: string) {
  await processRegistrationOperation(store.db, uid, id, deps);
  return store.docs.get(`users/${uid}/application_operations/${id}`)!;
}
async function submit(store: Store, uid: string, driver = false) {
  enqueue(store, uid, 'submit', 'submit_application', payload(uid, driver));
  return run(store, uid, 'submit');
}

test('Tourist and driver submission store trusted agreement, required evidence and immutable private history', async () => {
  for (const driver of [false, true]) {
    const store = new Store(); applicant(store, 'owner', driver);
    assert.equal((await submit(store, 'owner', driver)).status, 'succeeded');
    const user = store.docs.get('users/owner')!, app = store.docs.get('registration_applications/owner')!;
    assert.equal(user.registrationStatus, 'pending_review'); assert.equal(user.accountStatus, 'pending_approval');
    assert.equal(user.applicationRevision, 1); assert.equal(user.nicNumber, undefined); assert.equal(user.evidence, undefined);
    assert.equal(app.agreementVersion, '1.0'); assert.ok(app.agreementAcceptedAt.isEqual(store.commitTime));
    assert.ok(user.applicationSubmittedAt instanceof Timestamp);
    assert.ok(user.applicationSubmittedAt.isEqual(app.submittedAt));
    assert.ok(user.applicationSubmittedAt.isEqual(store.docs.get('registration_applications/owner/history/submit')!.createdAt));
    assert.equal(app.evidence.length, driver ? 3 : 2); assert.equal(app.evidence[0].applicationRevision, 1);
    assert.deepEqual(app, store.docs.get('registration_applications/owner/submissions/1'));
    await run(store, 'owner', 'submit');
    assert.equal([...store.docs.keys()].filter((key) => key.startsWith('registration_applications/owner/history/')).length, 1);
  }
});
test('Missing documents/agreement, forged fields and Tourist DL cannot submit', async () => {
  for (const change of [(p: DocumentData) => { delete p.evidence.selfie; }, (p: DocumentData) => { p.agreementAccepted = false; },
    (p: DocumentData) => { p.agreementVersion = '0'; }, (p: DocumentData) => { p.profile.accountType = 'driver'; },
    (p: DocumentData) => { p.profile.email = 'other@example.com'; }, (p: DocumentData) => { p.drivingLicenceNumber = 'B1234567'; },
    (p: DocumentData) => { p.profile.applicationSubmittedAt = Timestamp.fromMillis(1); },
    (p: DocumentData) => { p.applicationSubmittedAt = Timestamp.fromMillis(1); }]) {
    const store = new Store(); applicant(store, 'owner'); const data = payload('owner'); change(data);
    enqueue(store, 'owner', 'bad', 'submit_application', data);
    assert.equal((await run(store, 'owner', 'bad')).status, 'failed');
    assert.equal(store.docs.get('users/owner')!.registrationStatus, 'draft');
    assert.equal(store.docs.has('registration_applications/owner'), false);
  }
});
test('NIC is unique across Tourist/Driver and legacy HMAC claims; duplicate response reveals no owner', async () => {
  const store = new Store(); applicant(store, 'tourist'); applicant(store, 'driver', true);
  await submit(store, 'tourist');
  const duplicate = await submit(store, 'driver', true);
  assert.equal(duplicate.errorCode, 'identity-unavailable');
  assert.match(duplicate.errorMessage, /This NIC number is already registered/);
  assert.ok(!duplicate.errorMessage.includes('tourist'));
  assert.equal(store.docs.has('driver_verifications/driver'), false);
  const old = new Store(); applicant(old, 'new');
  old.docs.set(`identity_registry/${registryKey(secret, 'nic', normalizeIdentity('nic', '901234567V'))}`, {uid: 'legacy'});
  assert.equal((await submit(old, 'new')).errorCode, 'identity-unavailable');
});
test('Concurrent duplicate applications claim identity once with no partial second licence', async () => {
  const store = new Store(); applicant(store, 'one'); applicant(store, 'two', true);
  enqueue(store, 'one', 's1', 'submit_application', payload('one'));
  enqueue(store, 'two', 's2', 'submit_application', payload('two', true));
  const results = await Promise.all([run(store, 'one', 's1'), run(store, 'two', 's2')]);
  assert.equal(results.filter((r) => r.status === 'succeeded').length, 1);
  assert.equal(results.filter((r) => r.errorCode === 'identity-unavailable').length, 1);
});
test('Duplicate licence is rejected even with a distinct NIC', async () => {
  const store = new Store(); applicant(store, 'one', true); applicant(store, 'two', true); await submit(store, 'one', true);
  const other = payload('two', true); other.nicNumber = '199923456789';
  enqueue(store, 'two', 'submit', 'submit_application', other);
  assert.match((await run(store, 'two', 'submit')).errorMessage, /This Driving Licence number is already registered/);
});
test('Only primary admin reviews; Tourist activates but driver identity approval does not grant membership/payment', async () => {
  for (const driver of [false, true]) {
    const store = new Store(); applicant(store, 'owner', driver); await submit(store, 'owner', driver);
    for (const actor of ['owner', 'stranger', 'support-only']) {
      enqueue(store, 'owner', actor, 'approve', {}, actor);
      assert.equal((await run(store, 'owner', actor)).errorCode, 'permission-denied');
    }
    enqueue(store, 'owner', 'approve', 'approve', {}, 'admin');
    assert.equal((await run(store, 'owner', 'approve')).status, 'succeeded');
    const user = store.docs.get('users/owner')!;
    assert.equal(user.registrationStatus, 'approved'); assert.equal(user.identityVerificationStatus, 'verified');
    assert.equal(user.accountStatus, driver ? 'pending_approval' : 'active');
    assert.equal(user.paymentStatus, driver ? 'pending' : undefined); assert.equal(user.membershipStatus, driver ? 'pending' : undefined);
    assert.equal(user.averageRating, 4); assert.equal(user.completedTripsCount, 7);
    const audit = store.docs.get('registration_applications/owner/history/approve')!;
    assert.equal(audit.actorUid, 'admin'); assert.equal(audit.previousValue, 'pending_review'); assert.equal(audit.newValue, 'approved');
    if (driver) {
      store.docs.set('users/owner/driver_operations/activate', {actorUid: 'admin', status: 'pending', action: 'activate_membership', payload: {}, expectedRevision: user.driverAdminRevision});
      await processDriverOperation(store.db, 'owner', 'activate', deps);
      assert.equal(store.docs.get('users/owner/driver_operations/activate')!.errorCode, 'payment-required');
    }
  }
});
test('Reason required; rejected/correction resubmission increments revision and preserves prior agreement/history', async () => {
  for (const action of ['reject', 'request_correction']) {
    const store = new Store(); applicant(store, 'owner'); await submit(store, 'owner');
    const original = store.docs.get('registration_applications/owner/submissions/1')!;
    const firstSubmittedAt = store.docs.get('users/owner')!.applicationSubmittedAt as Timestamp;
    const originalHistory = store.docs.get('registration_applications/owner/history/submit')!;
    enqueue(store, 'owner', 'missing-reason', action, {}, 'admin');
    assert.equal((await run(store, 'owner', 'missing-reason')).status, 'failed');
    enqueue(store, 'owner', 'review', action, {}, 'admin', 'Please replace the unclear photo.');
    assert.equal((await run(store, 'owner', 'review')).status, 'succeeded');
    assert.equal(store.docs.get('registration_applications/owner')!.reason, 'Please replace the unclear photo.');
    assert.ok(store.docs.get('users/owner')!.applicationSubmittedAt.isEqual(firstSubmittedAt));
    enqueue(store, 'owner', 'resubmit', 'submit_application', payload('owner', false, 2));
    assert.equal((await run(store, 'owner', 'resubmit')).status, 'succeeded');
    assert.equal(store.docs.get('users/owner')!.applicationRevision, 2);
    assert.equal(store.docs.get('users/owner')!.registrationStatus, 'pending_review');
    const latest = store.docs.get('users/owner')!.applicationSubmittedAt as Timestamp;
    assert.ok(latest.toMillis() > firstSubmittedAt.toMillis());
    assert.ok(latest.isEqual(store.docs.get('registration_applications/owner/submissions/2')!.submittedAt));
    assert.ok(latest.isEqual(store.docs.get('registration_applications/owner/history/resubmit')!.createdAt));
    assert.deepEqual(store.docs.get('registration_applications/owner/submissions/1'), original);
    assert.deepEqual(store.docs.get('registration_applications/owner/history/submit'), originalHistory);
    await run(store, 'owner', 'resubmit');
    assert.ok(store.docs.get('users/owner')!.applicationSubmittedAt.isEqual(latest));
    enqueue(store, 'owner', 'obsolete', 'approve', {}, 'admin', '', 1);
    assert.equal((await run(store, 'owner', 'obsolete')).errorCode, 'stale-state');
  }
});
test('Public projection excludes all application identity, agreement, evidence, payment and registry fields', () => {
  const sensitive = {nicNumber: 'secret', drivingLicenceNumber: 'secret', evidence: ['private'], selfiePath: 'private',
    nicDocumentPath: 'private', paymentEvidence: 'private', adminNotes: 'secret', nicRegistryKey: 'hmac', licenceRegistryKey: 'hmac',
    agreementVersion: '1.0', registrationStatus: 'pending_review'};
  const publicData = publicProfile('owner', sensitive);
  for (const key of Object.keys(sensitive)) assert.equal(publicData[key], undefined);
});

test('Approval rechecks reserved identity ownership without disclosing the conflicting account', async () => {
  const store = new Store(); applicant(store, 'owner'); await submit(store, 'owner');
  const app = store.docs.get('registration_applications/owner')!;
  store.docs.set(`identity_registry/${app.nicRegistryKey}`, {uid: 'private-other-account'});
  enqueue(store, 'owner', 'approve', 'approve', {}, 'admin');
  const result = await run(store, 'owner', 'approve');
  assert.equal(result.errorCode, 'identity-unavailable');
  assert.ok(!result.errorMessage.includes('private-other-account'));
  assert.equal(store.docs.get('users/owner')!.registrationStatus, 'pending_review');
  assert.equal(store.docs.has('registration_applications/owner/history/approve'), false);
});

test('Concurrent review and delivery retries preserve one approval transition and immutable submitted revision', async () => {
  const store = new Store(); applicant(store, 'owner'); await submit(store, 'owner');
  const original = store.docs.get('registration_applications/owner/submissions/1');
  enqueue(store, 'owner', 'first', 'approve', {}, 'admin');
  enqueue(store, 'owner', 'second', 'approve', {}, 'admin');
  const results = await Promise.all([run(store, 'owner', 'first'), run(store, 'owner', 'second')]);
  assert.equal(results.filter((r) => r.status === 'succeeded').length, 1);
  await run(store, 'owner', 'first'); await run(store, 'owner', 'second');
  assert.equal([...store.docs.entries()].filter(([path, value]) =>
    path.startsWith('registration_applications/owner/history/') && value.action === 'application_approved').length, 1);
  assert.deepEqual(store.docs.get('registration_applications/owner/submissions/1'), original);
  assert.equal(store.docs.get('users/owner')!.accountStatus, 'active');
});
