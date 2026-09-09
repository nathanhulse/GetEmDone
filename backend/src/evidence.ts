import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { dirname, resolve, sep } from "node:path";
import { DatabaseSync } from "node:sqlite";
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

export class FilesystemPrivateObjectStore implements PrivateObjectStore {
  private readonly root: string;

  constructor(root: string) {
    if (!root.trim()) throw new Error("Evidence object root is required");
    this.root = resolve(root);
  }

  async put(key: string, value: Uint8Array): Promise<void> {
    const destination = this.pathFor(key);
    await mkdir(dirname(destination), { recursive: true, mode: 0o700 });
    const temporary = `${destination}.${randomBytes(12).toString("hex")}.tmp`;
    await writeFile(temporary, value, { mode: 0o600, flag: "wx" });
    await rename(temporary, destination);
  }

  async get(key: string): Promise<Uint8Array | undefined> {
    try {
      return await readFile(this.pathFor(key));
    } catch (error) {
      if (isMissing(error)) return undefined;
      throw error;
    }
  }

  async delete(key: string): Promise<void> {
    await rm(this.pathFor(key), { force: true });
  }

  private pathFor(key: string): string {
    if (!key || key.includes("\\") || key.split("/").some(part => !part || part === "." || part === "..")) {
      throw new Error("Invalid private object key");
    }
    const candidate = resolve(this.root, key);
    if (!candidate.startsWith(`${this.root}${sep}`)) throw new Error("Private object key escapes storage root");
    return candidate;
  }
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

export interface EvidenceMetadataRepository {
  get(id: string): EvidenceRecord | undefined;
  insert(record: EvidenceRecord): void;
  update(record: EvidenceRecord): void;
  list(): EvidenceRecord[];
}

export class MemoryEvidenceMetadataRepository implements EvidenceMetadataRepository {
  private readonly records = new Map<string, EvidenceRecord>();
  get(id: string): EvidenceRecord | undefined { return cloneRecord(this.records.get(id)); }
  insert(record: EvidenceRecord): void {
    if (this.records.has(record.id)) throw new DomainError(409, "EVIDENCE_EXISTS", "Evidence identifier already exists");
    this.records.set(record.id, cloneRecord(record)!);
  }
  update(record: EvidenceRecord): void { this.records.set(record.id, cloneRecord(record)!); }
  list(): EvidenceRecord[] { return [...this.records.values()].map(record => cloneRecord(record)!); }
}

export class SQLiteEvidenceMetadataRepository implements EvidenceMetadataRepository {
  private readonly database: DatabaseSync;

  constructor(path: string) {
    if (!path.trim()) throw new Error("Evidence metadata database path is required");
    this.database = new DatabaseSync(path);
    this.database.exec(`
      PRAGMA journal_mode = WAL;
      CREATE TABLE IF NOT EXISTS evidence_metadata (
        id TEXT PRIMARY KEY,
        household_id TEXT NOT NULL,
        child_member_id TEXT NOT NULL,
        object_key TEXT NOT NULL UNIQUE,
        content_type TEXT NOT NULL,
        byte_count INTEGER NOT NULL CHECK (byte_count > 0),
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        deleted_at TEXT
      );
      CREATE INDEX IF NOT EXISTS evidence_expiry ON evidence_metadata(expires_at) WHERE deleted_at IS NULL;
    `);
  }

  get(id: string): EvidenceRecord | undefined {
    return decodeRow(this.database.prepare("SELECT * FROM evidence_metadata WHERE id = ?").get(id) as EvidenceRow | undefined);
  }

  insert(record: EvidenceRecord): void {
    try {
      this.database.prepare(`INSERT INTO evidence_metadata
        (id, household_id, child_member_id, object_key, content_type, byte_count, created_at, expires_at, deleted_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`)
        .run(record.id, record.householdId, record.childMemberId, record.objectKey, record.contentType, record.byteCount, record.createdAt.toISOString(), record.expiresAt.toISOString(), record.deletedAt?.toISOString() ?? null);
    } catch (error) {
      if (String(error).includes("UNIQUE constraint failed")) throw new DomainError(409, "EVIDENCE_EXISTS", "Evidence identifier already exists");
      throw error;
    }
  }

  update(record: EvidenceRecord): void {
    this.database.prepare("UPDATE evidence_metadata SET deleted_at = ? WHERE id = ?")
      .run(record.deletedAt?.toISOString() ?? null, record.id);
  }

  list(): EvidenceRecord[] {
    return (this.database.prepare("SELECT * FROM evidence_metadata").all() as unknown as EvidenceRow[]).map(row => decodeRow(row)!);
  }

  close(): void { this.database.close(); }
}

interface EncryptedEnvelope {
  version: 1;
  nonce: string;
  tag: string;
  ciphertext: string;
}

export class EncryptedEvidenceVault {
  constructor(
    private readonly store: PrivateObjectStore,
    private readonly encryptionKey: Uint8Array,
    private readonly maximumBytes = 5 * 1024 * 1024,
    private readonly records: EvidenceMetadataRepository = new MemoryEvidenceMetadataRepository()
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
    if (this.records.get(input.id)) throw new DomainError(409, "EVIDENCE_EXISTS", "Evidence identifier already exists");

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
    try {
      this.records.insert(record);
    } catch (error) {
      await this.store.delete(objectKey);
      throw error;
    }
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
    this.records.update(record);
  }

  async purgeExpired(now: Date): Promise<number> {
    let deleted = 0;
    for (const record of this.records.list()) {
      if (!record.deletedAt && record.expiresAt <= now) {
        await this.store.delete(record.objectKey);
        record.deletedAt = now;
        this.records.update(record);
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

interface EvidenceRow {
  id: string;
  household_id: string;
  child_member_id: string;
  object_key: string;
  content_type: EvidenceRecord["contentType"];
  byte_count: number;
  created_at: string;
  expires_at: string;
  deleted_at: string | null;
}

function decodeRow(row: EvidenceRow | undefined): EvidenceRecord | undefined {
  if (!row) return undefined;
  const record: EvidenceRecord = {
    id: row.id,
    householdId: row.household_id,
    childMemberId: row.child_member_id,
    objectKey: row.object_key,
    contentType: row.content_type,
    byteCount: row.byte_count,
    createdAt: new Date(row.created_at),
    expiresAt: new Date(row.expires_at)
  };
  if (row.deleted_at) record.deletedAt = new Date(row.deleted_at);
  return record;
}

function cloneRecord(record: EvidenceRecord | undefined): EvidenceRecord | undefined {
  return record ? structuredClone(record) : undefined;
}

function isMissing(error: unknown): boolean {
  return typeof error === "object" && error !== null && "code" in error && error.code === "ENOENT";
}
