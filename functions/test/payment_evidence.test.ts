import {strict as assert} from 'node:assert';
import {test} from 'node:test';
import {readPaymentEvidence} from '../src/driver_evidence';

const path = `payment_evidence/owner/payment/${'a'.repeat(32)}.jpg`;
const metadata = () => ({contentType: 'image/jpeg', size: 200000, generation: '1', timeCreated: '2026-09-23T12:00:00Z',
  metadata: {ownerUid: 'owner', paymentId: 'payment', evidenceType: 'payment_slip', width: '2000', height: '1200'}});
test('Payment metadata is server-read and persisted through a safe allowlist', async () => {
  const result = await readPaymentEvidence('owner', 'payment', path, async () => ({...metadata(), downloadToken: 'secret', originalName: 'private-name'}));
  assert.equal(result.storagePath, path); assert.equal(result.compressedSizeBytes, 200000);
  assert.equal(result.evidenceType, 'payment_slip'); assert.equal(result.paymentId, 'payment');
  assert.ok(!JSON.stringify(result).includes('secret')); assert.ok(!JSON.stringify(result).includes('private-name'));
});
test('Wrong owner/payment path is denied before fetching any private object', async () => {
  let reads = 0;
  const reader = async () => { reads++; return metadata(); };
  await assert.rejects(readPaymentEvidence('other', 'payment', path, reader));
  await assert.rejects(readPaymentEvidence('owner', 'other', path, reader));
  await assert.rejects(readPaymentEvidence('owner', 'payment', 'https://public.example/slip', reader));
  assert.equal(reads, 0);
});
test('Oversized, unsupported and mismatched payment metadata fails closed', async () => {
  for (const object of [
    {...metadata(), contentType: 'image/png'}, {...metadata(), size: 2097153}, {...metadata(), size: 0},
    {...metadata(), generation: ''}, {...metadata(), timeCreated: 'bad'},
    {...metadata(), metadata: {...metadata().metadata, width: '2001'}},
    {...metadata(), metadata: {...metadata().metadata, ownerUid: 'other'}},
    {...metadata(), metadata: {...metadata().metadata, paymentId: 'other'}},
    {...metadata(), metadata: {...metadata().metadata, evidenceType: 'selfie'}},
  ]) await assert.rejects(readPaymentEvidence('owner', 'payment', path, async () => object));
});
