import {Timestamp} from "firebase-admin/firestore";

export type EvidenceMetadataReader = (path: string) => Promise<{
  contentType?: string; size?: string | number; timeCreated?: string; generation?: string | number;
  metadata?: {[key: string]: string};
}>;

export async function readPaymentEvidence(uid: string, paymentId: string, path: unknown, read: EvidenceMetadataReader) {
  const prefix = `payment_evidence/${uid}/${paymentId}/`;
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(paymentId) || typeof path !== "string" || !path.startsWith(prefix) ||
      !/^[a-f0-9]{32}\.jpg$/.test(path.slice(prefix.length))) throw new Error("Invalid payment slip path.");
  const object = await read(path), metadata = object.metadata ?? {};
  const size = Number(object.size), width = Number(metadata.width), height = Number(metadata.height);
  const date = new Date(object.timeCreated ?? "");
  if (object.contentType !== "image/jpeg" || !Number.isSafeInteger(size) || size <= 0 || size > 2097152 ||
      metadata.ownerUid !== uid || metadata.paymentId !== paymentId || metadata.evidenceType !== "payment_slip" ||
      !Number.isInteger(width) || !Number.isInteger(height) || Math.min(width, height) < 400 || Math.max(width, height) > 2000 ||
      !Number.isFinite(date.getTime()) || !object.generation) throw new Error("Invalid payment slip metadata.");
  return {storagePath: path, evidenceType: "payment_slip", paymentId, mimeType: "image/jpeg", compressedSizeBytes: size,
    width, height, uploadedAt: Timestamp.fromDate(date), generation: String(object.generation)};
}

/** Only server-read object facts are persisted, never client-supplied sizes/times or original filenames. */
export async function readDriverEvidence(uid: string, revision: number, input: unknown, read: EvidenceMetadataReader, namespace = "driver_evidence") {
  if (input == null) return [];
  if (typeof input !== "object" || Array.isArray(input)) throw new Error("Invalid evidence selection.");
  const entries = Object.entries(input);
  if (entries.length > 3) throw new Error("Invalid evidence selection.");
  const records = [];
  for (const [type, path] of entries) {
    if (!["nic", "driving_licence", "selfie"].includes(type) || typeof path !== "string") throw new Error("Invalid evidence selection.");
    const prefix = `${namespace}/${uid}/${revision}/${type}/`;
    if (!path.startsWith(prefix) || !/^[a-f0-9]{32}\.jpg$/.test(path.slice(prefix.length))) throw new Error("Evidence must belong to this application revision.");
    const object = await read(path), meta = object.metadata ?? {};
    const size = Number(object.size), width = Number(meta.width), height = Number(meta.height);
    const edge = type === "selfie" ? 1600 : 2000, limit = type === "selfie" ? 1572864 : 2097152;
    const date = new Date(object.timeCreated ?? "");
    if (object.contentType !== "image/jpeg" || !Number.isSafeInteger(size) || size <= 0 || size > limit ||
        meta.ownerUid !== uid || meta.applicationRevision !== String(revision) || meta.evidenceType !== type ||
        !Number.isInteger(width) || !Number.isInteger(height) || Math.min(width, height) < 400 || Math.max(width, height) > edge ||
        !Number.isFinite(date.getTime()) || !object.generation) throw new Error("Evidence is invalid or unavailable. Choose and upload another photo.");
    records.push({storagePath: path, evidenceType: type, mimeType: "image/jpeg", compressedSizeBytes: size,
      width, height, uploadedAt: Timestamp.fromDate(date), applicationRevision: revision, generation: String(object.generation)});
  }
  return records;
}
