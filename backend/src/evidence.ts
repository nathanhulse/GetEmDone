import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import { Actor, DomainError } from "./domain.js";

export interface PrivateObjectStore {
  put(key: string, value: Uint8Array): Promise<void>;
  get(key: string): Promise<Uint8Array | undefined>;
  delete(key: string): Promise<void>;
}

export class MemoryPrivateObjectStore implements PrivateObjectStore {
  readonly objects = new Map<string, Uint8Array>();
  async put(key: string, value: Uint8Array): Promise<void> { this.objects.set(key, Uint8Array.from(value)); }
  async get(key: string): Promise<Uint8Array | undefined> { return this.objects.get(key); }
  async delete(key: string): Promise<void> { this.objects.delete(key); }
}

export interface EvidenceRecord {
  id: string;
  householdId: string;
  childMemberId: string;
  objectKey: string;
  contentType: "image/jpeg" | "image/png" | "audio/mp4";
  byteCount: number;
  createdAt: Date;
  expiresAt: Date;
  deletedAt?: Date;
}

interface EncryptedEnvelope {
  version: 1;
  nonce: string;
  tag: string;
  ciphertext: string;
}

export class EncryptedEvidenceVault {
  private readonly records = new Map<string, EvidenceRecord>();

  constructor(
    private readonly store: PrivateObjectStore,
    private readonly encryptionKey: Uint8Array,
    private readonly maximumBytes = 5 * 1024 * 1024
  ) {
    if (encryptionKey.byteLength !== 32) throw new Error("Evidence encryption key must be 256 bits");
  }

  async save(input: {
    actor: Actor;
    id: string;
    childMemberId: string;
    contentType: EvidenceRecord["contentType"];
    plaintext: Uint8Array;
    now: Date;
    expiresAt: Date;
  }): Promise<EvidenceRecord> {
    if (input.actor.role !== "child" || input.actor.memberId !== input.childMemberId) {
      throw new DomainError(403, "ROLE_FORBIDDEN", "Only the owning child can add evidence");
    }
    if (input.plaintext.byteLength === 0 || input.plaintext.byteLength > this.maximumBytes) {
      throw new DomainError(413, "EVIDENCE_SIZE_INVALID", "Evidence size is not allowed");
    }
    if (input.expiresAt <= input.now) throw new DomainError(400, "RETENTION_INVALID", "Evidence expiry must be in the future");
    if (this.records.has(input.id)) throw new DomainError(409, "EVIDENCE_EXISTS", "Evidence identifier already exists");

    const objectKey = `${input.actor.householdId}/${input.childMemberId}/${input.id}.enc`;
    const aad = Buffer.from(`${input.actor.householdId}:${input.childMemberId}:${input.id}:${input.contentType}`);
    const nonce = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", this.encryptionKey, nonce);
    cipher.setAAD(aad);
    const ciphertext = Buffer.concat([cipher.update(input.plaintext), cipher.final()]);
    const envelope: EncryptedEnvelope = {
      version: 1,
      nonce: nonce.toString("base64url"),
      tag: cipher.getAuthTag().toString("base64url"),
      ciphertext: ciphertext.toString("base64url")
    };
    await this.store.put(objectKey, Buffer.from(JSON.stringify(envelope)));
    const record: EvidenceRecord = {
      id: input.id,
      householdId: input.actor.householdId,
      childMemberId: input.childMemberId,
      objectKey,
      contentType: input.contentType,
      byteCount: input.plaintext.byteLength,
      createdAt: input.now,
      expiresAt: input.expiresAt
    };
    this.records.set(input.id, record);
    return structuredClone(record);
  }

  async read(actor: Actor, evidenceId: string, now: Date): Promise<Uint8Array> {
    const record = this.authorizedRecord(actor, evidenceId);
    if (record.deletedAt) throw new DomainError(410, "EVIDENCE_DELETED", "Evidence was deleted");
    if (record.expiresAt <= now) throw new DomainError(410, "EVIDENCE_EXPIRED", "Evidence has expired");
    const stored = await this.store.get(record.objectKey);
    if (!stored) throw new DomainError(410, "EVIDENCE_UNAVAILABLE", "Evidence is unavailable");
    const envelope = JSON.parse(Buffer.from(stored).toString("utf8")) as EncryptedEnvelope;
    const decipher = createDecipheriv("aes-256-gcm", this.encryptionKey, Buffer.from(envelope.nonce, "base64url"));
    decipher.setAAD(Buffer.from(`${record.householdId}:${record.childMemberId}:${record.id}:${record.contentType}`));
    decipher.setAuthTag(Buffer.from(envelope.tag, "base64url"));
    return Buffer.concat([decipher.update(Buffer.from(envelope.ciphertext, "base64url")), decipher.final()]);
  }

  async delete(actor: Actor, evidenceId: string, now: Date): Promise<void> {
    const record = this.authorizedRecord(actor, evidenceId);
    if (actor.role === "child" && actor.memberId !== record.childMemberId) throw new DomainError(404, "NOT_FOUND", "Evidence not found");
    await this.store.delete(record.objectKey);
    record.deletedAt = now;
    this.records.set(record.id, record);
  }

  async purgeExpired(now: Date): Promise<number> {
    let deleted = 0;
    for (const record of this.records.values()) {
      if (!record.deletedAt && record.expiresAt <= now) {
        await this.store.delete(record.objectKey);
        record.deletedAt = now;
        deleted += 1;
      }
    }
    return deleted;
  }

  getRecord(actor: Actor, evidenceId: string): EvidenceRecord {
    return structuredClone(this.authorizedRecord(actor, evidenceId));
  }

  private authorizedRecord(actor: Actor, evidenceId: string): EvidenceRecord {
    const record = this.records.get(evidenceId);
    if (!record || record.householdId !== actor.householdId) throw new DomainError(404, "NOT_FOUND", "Evidence not found");
    if (actor.role === "child" && record.childMemberId !== actor.memberId) throw new DomainError(404, "NOT_FOUND", "Evidence not found");
    return record;
  }
}

