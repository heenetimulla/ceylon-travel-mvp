import {strict as assert} from "node:assert";
import {test} from "node:test";
import {readDriverEvidence} from "../src/driver_evidence";

const path = `driver_evidence/driver/4/nic/${"a".repeat(32)}.jpg`;
const metadata = {contentType: "image/jpeg", size: "150000", timeCreated: "2026-09-22T12:00:00.000Z", generation: "12",
  metadata: {ownerUid: "driver", applicationRevision: "4", evidenceType: "nic", width: "1800", height: "1200"}};

test("evidence metadata uses object facts and contains no binary, original filename or public URL", async () => {
  const records = await readDriverEvidence("driver", 4, {nic: path}, async () => metadata);
  assert.equal(records.length, 1);
  assert.deepEqual(Object.keys(records[0]).sort(), ["storagePath", "evidenceType", "mimeType", "compressedSizeBytes",
    "width", "height", "uploadedAt", "applicationRevision", "generation"].sort());
  assert.equal(records[0].compressedSizeBytes, 150000);
  assert.equal(records[0].uploadedAt.toDate().toISOString(), metadata.timeCreated);
  assert.equal(records[0].storagePath, path);
});

test("another applicant, revision, type or arbitrary URL is rejected before accessing Storage", async () => {
  for (const value of [path.replace('/driver/', '/other/'), path.replace('/4/', '/3/'), path.replace('/nic/', '/selfie/'),
    'https://example.com/photo.jpg', path + '/extra']) {
    let reads = 0;
    await assert.rejects(readDriverEvidence("driver", 4, {nic: value}, async () => { reads++; return metadata; }));
    assert.equal(reads, 0);
  }
});

test("server refuses wrong type, excessive size, forged ownership and invalid dimensions", async () => {
  for (const value of [{...metadata, contentType: "application/zip"}, {...metadata, size: "2097153"},
    {...metadata, metadata: {...metadata.metadata, ownerUid: "other"}},
    {...metadata, metadata: {...metadata.metadata, width: "99999"}}, {...metadata, timeCreated: "invalid"}]) {
    await assert.rejects(readDriverEvidence("driver", 4, {nic: path}, async () => value));
  }
});

test("selfie has its own lower size and dimension ceiling", async () => {
  const selfie = path.replace('/nic/', '/selfie/');
  const value = {...metadata, size: "1572865", metadata: {...metadata.metadata, evidenceType: "selfie", width: "1600"}};
  await assert.rejects(readDriverEvidence("driver", 4, {selfie}, async () => value));
  const records = await readDriverEvidence("driver", 4, {selfie}, async () => ({...value, size: "150000"}));
  assert.equal(records[0].evidenceType, "selfie");
});
