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
  agreementVersion: '1.1', agreementAccepted: true};
}
function enqueue(store: Store, uid: string, id: string, action: string, data: DocumentData = {}, actor = uid, reason = '', revision?: number) {
  store.docs.set(`users/${uid}/application_operations/${id}`, {actorUid: actor, action, payload: data, reason,
    status: 'pending', expectedRevision: revision ?? store.docs.get(`users/${uid}`)!.applicationRevision ?? 0});
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
    assert.equal(app.agreementVersion, '1.1'); assert.ok(app.agreementAcceptedAt.isEqual(store.commitTime));
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

async function approvedTourist(store: Store, uid = 'owner', nic = '901234567V') {
  applicant(store, uid);
  const initial = payload(uid); initial.nicNumber = nic;
  enqueue(store, uid, 'original', 'submit_application', initial);
  assert.equal((await run(store, uid, 'original')).status, 'succeeded');
  // An existing v1.0 acceptance must remain reviewable and immutable after rollout.
  for (const path of [`registration_applications/${uid}`, `registration_applications/${uid}/submissions/1`]) {
    store.docs.set(path, {...store.docs.get(path), agreementVersion: '1.0'});
  }
  enqueue(store, uid, 'original-review', 'approve', {}, 'admin');
  assert.equal((await run(store, uid, 'original-review')).status, 'succeeded');
}
async function beginUpgrade(store: Store, uid = 'owner') {
  enqueue(store, uid, 'upgrade-draft', 'start_driver_upgrade');
  return run(store, uid, 'upgrade-draft');
}
function upgradePayload(uid = 'owner', revision = 2): DocumentData {
  return {profile: {vehicleType: 'Any', vehicleNumber: 'ABC-1234', vehicleDetails: 'Toyota sedan, four seats',
    operatingArea: 'Colombo', availableAreas: 'Western'}, drivingLicenceNumber: 'B1234567',
    evidence: Object.fromEntries(['driving_licence', 'selfie'].map(type =>
      [type, `registration_evidence/${uid}/${revision}/${type}/${'b'.repeat(32)}.jpg`])),
    agreementVersion: '1.1', agreementAccepted: true};
}

test('Same-UID driver upgrade draft/submission preserves Tourist access, v1.0 history and verified NIC source', async () => {
  const store = new Store(); await approvedTourist(store);
  const original = store.docs.get('registration_applications/owner/submissions/1');
  const originalUser = store.docs.get('users/owner')!;
  assert.equal((await beginUpgrade(store)).status, 'succeeded');
  assert.equal(store.docs.get('users/owner')!.driverUpgradeStatus, 'draft');
  assert.equal(store.docs.get('registration_applications/owner')!.identitySourceRevision, 1);
  enqueue(store, 'owner', 'upgrade-submit', 'submit_driver_upgrade', upgradePayload());
  assert.equal((await run(store, 'owner', 'upgrade-submit')).status, 'succeeded');
  const user = store.docs.get('users/owner')!, app = store.docs.get('registration_applications/owner')!;
  assert.equal(user.uid, 'owner'); assert.equal(user.accountType, 'tourist');
  assert.equal(user.registrationStatus, 'approved'); assert.equal(user.accountStatus, 'active');
  assert.equal(user.identityVerificationStatus, 'verified'); assert.equal(user.driverUpgradeStatus, 'pending_review');
  assert.equal(user.applicationRevision, 2);
  for (const field of ['phoneNumber', 'fullName', 'email', 'averageRating', 'completedTripsCount', 'applicationSubmittedAt']) {
    assert.deepEqual(user[field], originalUser[field]);
  }
  for (const field of ['paymentStatus', 'membershipPlan', 'membershipStatus', 'driverRegistrationNumber', 'nicNumber', 'vehicleType']) {
    assert.equal(user[field], undefined);
  }
  assert.equal(app.purpose, 'driver_upgrade'); assert.equal(app.targetAccountType, 'driver');
  assert.equal(app.accountType, 'tourist'); assert.equal(app.agreementVersion, '1.1');
  assert.ok(app.agreementAcceptedAt.isEqual(app.submittedAt));
  const nic = app.evidence.find((e: DocumentData) => e.evidenceType === 'nic');
  assert.equal(nic.reusedFromApplicationRevision, 1); assert.equal(nic.applicationRevision, 1);
  assert.ok(nic.storagePath.startsWith('registration_evidence/owner/1/nic/'));
  for (const type of ['selfie', 'driving_licence']) {
    assert.equal(app.evidence.find((e: DocumentData) => e.evidenceType === type).applicationRevision, 2);
  }
  assert.deepEqual(store.docs.get('registration_applications/owner/submissions/1'), original);
  assert.equal(store.docs.has('driver_verifications/owner'), false);
  assert.equal([...store.docs.keys()].filter(k => /^users\/[^/]+$/.test(k)).length, 1);
  assert.equal(store.docs.has('system_config/driver_registration_counter'), false);
  await run(store, 'owner', 'upgrade-submit');
  assert.equal([...store.docs.keys()].filter(k => k === 'registration_applications/owner/history/upgrade-submit').length, 1);
});

test('Concurrent draft creation and duplicate submission are safe; existing drivers and inactive applicants cannot upgrade', async () => {
  const store = new Store(); await approvedTourist(store);
  enqueue(store, 'owner', 'draft-a', 'start_driver_upgrade'); enqueue(store, 'owner', 'draft-b', 'start_driver_upgrade');
  const results = await Promise.all([run(store, 'owner', 'draft-a'), run(store, 'owner', 'draft-b')]);
  assert.equal(results.filter(r => r.status === 'succeeded').length, 1);
  assert.equal(results.filter(r => r.errorCode === 'upgrade-locked').length, 1);
  enqueue(store, 'owner', 'send-a', 'submit_driver_upgrade', upgradePayload());
  assert.equal((await run(store, 'owner', 'send-a')).status, 'succeeded');
  enqueue(store, 'owner', 'send-b', 'submit_driver_upgrade', upgradePayload('owner', 3));
  assert.equal((await run(store, 'owner', 'send-b')).errorCode, 'submission-locked');
  for (const patch of [{accountType: 'driver'}, {accountStatus: 'suspended'}, {registrationStatus: 'pending_review'}]) {
    const denied = new Store(); await approvedTourist(denied);
    denied.docs.set('users/owner', {...denied.docs.get('users/owner'), ...patch});
    assert.equal((await beginUpgrade(denied)).status, 'failed');
  }
});

test('Upgrade requires new DL/selfie, vehicle data, licence and current agreement; cannot forge profile/admin fields', async () => {
  const mutations = [
    (p: DocumentData) => { delete p.drivingLicenceNumber; },
    (p: DocumentData) => { delete p.evidence.driving_licence; },
    (p: DocumentData) => { delete p.evidence.selfie; },
    (p: DocumentData) => { p.evidence.selfie = `registration_evidence/owner/1/selfie/${'a'.repeat(32)}.jpg`; },
    (p: DocumentData) => { p.agreementVersion = '1.0'; },
    (p: DocumentData) => { p.agreementAccepted = false; },
    (p: DocumentData) => { p.nicNumber = '199923456789'; },
    ...['vehicleType', 'vehicleNumber', 'vehicleDetails', 'operatingArea', 'availableAreas'].map(field =>
      (p: DocumentData) => { delete p.profile[field]; }),
    ...['accountType', 'accountStatus', 'fullName', 'phoneNumber', 'email', 'paymentStatus', 'membershipPlan', 'driverRegistrationNumber'].map(field =>
      (p: DocumentData) => { p.profile[field] = 'forged'; }),
    (p: DocumentData) => { p.reviewedBy = 'admin'; },
    (p: DocumentData) => { p.identitySourceRevision = 0; },
  ];
  for (const mutate of mutations) {
    const store = new Store(); await approvedTourist(store); await beginUpgrade(store);
    const data = upgradePayload(); mutate(data);
    enqueue(store, 'owner', 'bad', 'submit_driver_upgrade', data);
    assert.equal((await run(store, 'owner', 'bad')).status, 'failed');
    assert.equal(store.docs.get('users/owner')!.driverUpgradeStatus, 'draft');
    assert.equal(store.docs.has('registration_applications/owner/submissions/2'), false);
  }
});

test('Correction/rejection resubmits a new immutable upgrade revision without altering the Tourist account', async () => {
  for (const action of ['reject', 'request_correction']) {
    const store = new Store(); await approvedTourist(store); await beginUpgrade(store);
    enqueue(store, 'owner', 'upgrade-submit', 'submit_driver_upgrade', upgradePayload());
    await run(store, 'owner', 'upgrade-submit');
    const original = store.docs.get('registration_applications/owner/submissions/2');
    enqueue(store, 'owner', 'no-reason', action, {}, 'admin');
    assert.equal((await run(store, 'owner', 'no-reason')).status, 'failed');
    enqueue(store, 'owner', 'review', action, {}, 'admin', 'Please replace the licence image.');
    assert.equal((await run(store, 'owner', 'review')).status, 'succeeded');
    const app = store.docs.get('registration_applications/owner')!;
    assert.equal(app.reason, 'Please replace the licence image.');
    assert.equal(app.registrationStatus, action === 'reject' ? 'rejected' : 'correction_required');
    enqueue(store, 'owner', 'resubmit-upgrade', 'submit_driver_upgrade', upgradePayload('owner', 3));
    assert.equal((await run(store, 'owner', 'resubmit-upgrade')).status, 'succeeded');
    assert.equal(store.docs.get('users/owner')!.driverUpgradeStatus, 'pending_review');
    assert.equal(store.docs.get('users/owner')!.applicationRevision, 3);
    assert.equal(store.docs.get('users/owner')!.accountStatus, 'active');
    assert.equal(store.docs.get('users/owner')!.registrationStatus, 'approved');
    assert.deepEqual(store.docs.get('registration_applications/owner/submissions/2'), original);
    assert.equal(store.docs.get('registration_applications/owner/submissions/1')!.agreementVersion, '1.0');
    enqueue(store, 'owner', 'stale', 'request_correction', {}, 'admin', 'Stale review', 2);
    assert.equal((await run(store, 'owner', 'stale')).errorCode, 'stale-state');
  }
});

test('Primary admin approves upgrade on the same UID; applicant and support cannot decide', async () => {
  const store = new Store(); await approvedTourist(store); await beginUpgrade(store);
  enqueue(store, 'owner', 'upgrade-submit', 'submit_driver_upgrade', upgradePayload()); await run(store, 'owner', 'upgrade-submit');
  const original = store.docs.get('users/owner')!;
  const submission = store.docs.get('registration_applications/owner/submissions/2');
  const touristSubmission = store.docs.get('registration_applications/owner/submissions/1');
  store.docs.set('users/owner/support_history/retained', {example: 'unchanged'});
  for (const actor of ['owner', 'stranger', 'support-only']) {
    enqueue(store, 'owner', `approval-${actor}`, 'approve', {}, actor);
    assert.equal((await run(store, 'owner', `approval-${actor}`)).errorCode, 'permission-denied');
  }
  enqueue(store, 'owner', 'approval-admin', 'approve', {}, 'admin');
  assert.equal((await run(store, 'owner', 'approval-admin')).status, 'succeeded');
  const user = store.docs.get('users/owner')!;
  assert.equal(user.uid, 'owner'); assert.equal(user.accountType, 'driver');
  assert.equal(user.registrationStatus, 'approved'); assert.equal(user.driverUpgradeStatus, 'approved');
  assert.equal(user.identityVerificationStatus, 'verified'); assert.equal(user.accountStatus, 'pending_approval');
  assert.equal(user.paymentStatus, 'pending'); assert.equal(user.membershipStatus, 'pending');
  assert.equal(user.vehicleType, 'Any'); assert.equal(user.driverAdminRevision, 1);
  for (const field of ['membershipPlan', 'driverRegistrationNumber', 'registrationFeePaidLkr', 'currentRegistrationPaymentId']) {
    assert.equal(user[field], undefined);
  }
  for (const field of ['fullName', 'phoneNumber', 'email', 'city', 'averageRating', 'completedTripsCount']) {
    assert.deepEqual(user[field], original[field]);
  }
  assert.deepEqual(store.docs.get('registration_applications/owner/submissions/2'), submission);
  assert.deepEqual(store.docs.get('registration_applications/owner/submissions/1'), touristSubmission);
  assert.deepEqual(store.docs.get('users/owner/support_history/retained'), {example: 'unchanged'});
  assert.equal([...store.docs.keys()].filter(p => /^users\/[^/]+$/.test(p)).length, 1);
  assert.equal(store.docs.get('driver_verifications/owner')!.identityVerificationStatus, 'verified');
  const audit = store.docs.get('users/owner/admin_history/application_approval-admin')!;
  assert.equal(audit.targetUid, 'owner'); assert.equal(audit.actorUid, 'admin');
  assert.equal(audit.previousAccountType, 'tourist'); assert.equal(audit.resultingAccountType, 'driver');
  assert.equal(audit.applicationRevision, 2); assert.equal(audit.purpose, 'driver_upgrade');
  const size = store.docs.size;
  await run(store, 'owner', 'approval-admin'); assert.equal(store.docs.size, size);
  enqueue(store, 'owner', 'replay-new-id', 'approve', {}, 'admin');
  assert.equal((await run(store, 'owner', 'replay-new-id')).status, 'failed');
  store.docs.set('users/owner/driver_operations/activate', {actorUid: 'admin', status: 'pending', action: 'activate_membership', payload: {}, expectedRevision: 1});
  await processDriverOperation(store.db, 'owner', 'activate', deps);
  assert.equal(store.docs.get('users/owner/driver_operations/activate')!.errorCode, 'payment-required');
  enqueue(store, 'owner', 'forged-owner', 'submit_driver_upgrade', upgradePayload(), 'stranger');
  assert.equal((await run(store, 'owner', 'forged-owner')).errorCode, 'permission-denied');
});

test('Upgrade approval fails closed for stale, malformed, ineligible and conflicting identity records', async () => {
  const changes: Array<(s: Store) => void> = [
    s => { s.docs.delete('users/owner'); },
    s => { s.docs.get('users/owner')!.accountStatus = 'suspended'; },
    s => { s.docs.get('users/owner')!.accountType = 'driver'; },
    s => { s.docs.get('registration_applications/owner')!.purpose = 'registration'; },
    s => { s.docs.get('registration_applications/owner')!.applicationRevision = 1; },
    s => { s.docs.get('users/owner')!.driverUpgradeStatus = 'rejected'; },
    s => { s.docs.get('registration_applications/owner')!.profile = {}; },
    ...['drivingLicenceNumber', 'agreementAcceptedAt', 'identitySourceRevision'].map(field => (s: Store) => {
      for (const path of ['registration_applications/owner', 'registration_applications/owner/submissions/2']) delete s.docs.get(path)![field];
    }),
    s => { for (const path of ['registration_applications/owner', 'registration_applications/owner/submissions/2']) s.docs.get(path)!.agreementVersion = '1.0'; },
    s => { for (const path of ['registration_applications/owner', 'registration_applications/owner/submissions/2']) s.docs.get(path)!.agreementAcceptedAt = 'not-a-timestamp'; },
    ...['vehicleType', 'vehicleNumber', 'vehicleDetails', 'operatingArea', 'availableAreas'].map(field => (s: Store) => {
      for (const path of ['registration_applications/owner', 'registration_applications/owner/submissions/2']) delete s.docs.get(path)!.profile[field];
    }),
    ...['driving_licence', 'selfie'].map(kind => (s: Store) => {
      for (const path of ['registration_applications/owner', 'registration_applications/owner/submissions/2']) {
        s.docs.get(path)!.evidence = s.docs.get(path)!.evidence.filter((e: DocumentData) => e.evidenceType !== kind);
      }
    }),
    ...['nicRegistryKey', 'licenceRegistryKey'].map(field => (s: Store) => {
      s.docs.get(`identity_registry/${s.docs.get('registration_applications/owner')![field]}`)!.uid = 'private-other-owner';
    }),
  ];
  for (const change of changes) {
    const store = new Store(); await approvedTourist(store); await beginUpgrade(store);
    enqueue(store, 'owner', 'upgrade-submit', 'submit_driver_upgrade', upgradePayload()); await run(store, 'owner', 'upgrade-submit');
    enqueue(store, 'owner', 'approve', 'approve', {}, 'admin'); change(store);
    const result = await run(store, 'owner', 'approve');
    assert.equal(result.status, 'failed'); assert.ok(!result.errorMessage.includes('private-other-owner'));
    assert.equal(store.docs.has('driver_verifications/owner'), false);
    assert.equal(store.docs.has('registration_applications/owner/history/approve'), false);
  }
});

test('Upgrade approval revalidates Storage metadata and concurrent approvals commit only once', async () => {
  const store = new Store(); await approvedTourist(store); await beginUpgrade(store);
  enqueue(store, 'owner', 'upgrade-submit', 'submit_driver_upgrade', upgradePayload()); await run(store, 'owner', 'upgrade-submit');
  enqueue(store, 'owner', 'bad-storage', 'approve', {}, 'admin');
  await processRegistrationOperation(store.db, 'owner', 'bad-storage', {...deps,
    evidenceMetadata: async path => ({...await deps.evidenceMetadata(path), generation: 'changed'})});
  assert.equal(store.docs.get('users/owner/application_operations/bad-storage')!.errorCode, 'invalid-evidence');
  enqueue(store, 'owner', 'stale', 'approve', {}, 'admin', '', 1);
  assert.equal((await run(store, 'owner', 'stale')).errorCode, 'stale-state');
  enqueue(store, 'owner', 'one', 'approve', {}, 'admin'); enqueue(store, 'owner', 'two', 'approve', {}, 'admin');
  const results = await Promise.all([run(store, 'owner', 'one'), run(store, 'owner', 'two')]);
  assert.equal(results.filter(r => r.status === 'succeeded').length, 1);
  assert.equal([...store.docs.entries()].filter(([path, value]) => path.startsWith('users/owner/admin_history/') && value.action === 'driver_upgrade_approved').length, 1);
});

test('Disabled primary admin cannot approve and legacy Tourist upgrade establishes current driver gates', async () => {
  const store = new Store(); applicant(store, 'owner');
  const user = store.docs.get('users/owner')!;
  delete user.registrationStatus; delete user.accountStatus; delete user.applicationRevision;
  assert.equal((await beginUpgrade(store)).status, 'succeeded');
  const data = upgradePayload('owner', 1); data.nicNumber = '901234567V';
  data.evidence.nic = `registration_evidence/owner/1/nic/${'a'.repeat(32)}.jpg`;
  enqueue(store, 'owner', 'submit-upgrade', 'submit_driver_upgrade', data);
  assert.equal((await run(store, 'owner', 'submit-upgrade')).status, 'succeeded');
  enqueue(store, 'owner', 'disabled', 'approve', {}, 'admin');
  await processRegistrationOperation(store.db, 'owner', 'disabled', {...deps,
    principal: async uid => ({uid, admin: true, disabled: true})});
  assert.equal(store.docs.get('users/owner/application_operations/disabled')!.errorCode, 'permission-denied');
  enqueue(store, 'owner', 'approve-upgrade', 'approve', {}, 'admin');
  assert.equal((await run(store, 'owner', 'approve-upgrade')).status, 'succeeded');
  assert.equal(store.docs.get('users/owner')!.registrationStatus, 'approved');
  assert.equal(store.docs.get('users/owner')!.accountStatus, 'pending_approval');
  assert.equal(store.docs.get('users/owner')!.identityVerificationStatus, 'verified');
  assert.equal(store.docs.get('users/owner')!.paymentStatus, 'pending');
});

test('Upgrade DL claims are globally unique under concurrent submissions and do not leak the conflicting UID', async () => {
  const store = new Store(); await approvedTourist(store, 'one'); await approvedTourist(store, 'two', '199923456789');
  await beginUpgrade(store, 'one'); await beginUpgrade(store, 'two');
  enqueue(store, 'one', 'send', 'submit_driver_upgrade', upgradePayload('one'));
  enqueue(store, 'two', 'send', 'submit_driver_upgrade', upgradePayload('two'));
  const results = await Promise.all([run(store, 'one', 'send'), run(store, 'two', 'send')]);
  assert.equal(results.filter(r => r.status === 'succeeded').length, 1);
  const denied = results.find(r => r.status === 'failed')!;
  assert.equal(denied.errorCode, 'identity-unavailable');
  assert.match(denied.errorMessage, /Driving Licence/);
  assert.ok(!denied.errorMessage.includes('one') && !denied.errorMessage.includes('two'));
});

test('NIC reuse verifies original registry ownership; legacy without approved identity must submit NIC evidence', async () => {
  const store = new Store(); await approvedTourist(store); await beginUpgrade(store);
  const source = store.docs.get('registration_applications/owner/submissions/1')!;
  store.docs.set(`identity_registry/${source.nicRegistryKey}`, {uid: 'secret-other-account'});
  enqueue(store, 'owner', 'send', 'submit_driver_upgrade', upgradePayload());
  const result = await run(store, 'owner', 'send');
  assert.equal(result.errorCode, 'identity-unavailable'); assert.ok(!result.errorMessage.includes('secret-other-account'));
  const legacy = new Store(); applicant(legacy, 'owner');
  const user = legacy.docs.get('users/owner')!; delete user.registrationStatus; delete user.applicationRevision; delete user.accountStatus;
  assert.equal((await beginUpgrade(legacy)).status, 'succeeded');
  const data = upgradePayload('owner', 1); data.nicNumber = '901234567V';
  data.evidence.nic = `registration_evidence/owner/1/nic/${'a'.repeat(32)}.jpg`;
  enqueue(legacy, 'owner', 'legacy-send', 'submit_driver_upgrade', data);
  assert.equal((await run(legacy, 'owner', 'legacy-send')).status, 'succeeded');
  assert.equal(legacy.docs.get('users/owner')!.registrationStatus, undefined);
  assert.equal(legacy.docs.get('registration_applications/owner')!.evidence.length, 3);
});

test('malformed approval values and mismatched upgrade head fail closed', async () => {
  for (const patch of [{registrationStatus: null}, {accountStatus: null}]) {
    const store = new Store(); await approvedTourist(store);
    store.docs.set('users/owner', {...store.docs.get('users/owner'), ...patch});
    assert.equal((await beginUpgrade(store)).status, 'failed');
  }
  const store = new Store(); await approvedTourist(store); await beginUpgrade(store);
  store.docs.set('registration_applications/owner', {...store.docs.get('registration_applications/owner'), applicationRevision: 0});
  enqueue(store, 'owner', 'mismatch', 'submit_driver_upgrade', upgradePayload());
  assert.equal((await run(store, 'owner', 'mismatch')).errorCode, 'stale-state');
  assert.equal(store.docs.has('registration_applications/owner/submissions/2'), false);
});
