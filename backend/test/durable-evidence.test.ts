import assert from "node:assert/strict";
import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { buildProductionApp } from "../src/app.js";
import { EncryptedEvidenceVault, FilesystemPrivateObjectStore, SQLiteEvidenceMetadataRepository } from "../src/evidence.js";
import type { Actor } from "../src/domain.js";

const child: Actor = { accountId: "acct_child", householdId: "home_a", memberId: "child_a", role: "child" };
const parent: Actor = { accountId: "acct_parent", householdId: "home_a", memberId: "parent_a", role: "owner" };
const now = new Date("2026-09-09T12:00:00Z");

test("filesystem objects and SQLite metadata survive restart, read, and deletion", async t => {
  const root = await mkdtemp(join(tmpdir(), "getemdone-evidence-"));
  t.after(async () => { await import("node:fs/promises").then(fs => fs.rm(root, { recursive: true, force: true })); });
  const databasePath = join(root, "evidence.sqlite");
  const objectRoot = join(root, "objects");
  const key = Buffer.alloc(32, 19);

  const firstMetadata = new SQLiteEvidenceMetadataRepository(databasePath);
  const first = new EncryptedEvidenceVault(new FilesystemPrivateObjectStore(objectRoot), key, 1024, firstMetadata);
  const plaintext = Buffer.from("restart-safe-private-photo");
  const record = await first.save({ actor: child, id: "ev_restart", childMemberId: "child_a", contentType: "image/jpeg", plaintext, now, expiresAt: new Date("2026-09-10T12:00:00Z") });
  firstMetadata.close();
  assert.equal((await readFile(join(objectRoot, record.objectKey))).includes(plaintext), false);

  const secondMetadata = new SQLiteEvidenceMetadataRepository(databasePath);
  const second = new EncryptedEvidenceVault(new FilesystemPrivateObjectStore(objectRoot), key, 1024, secondMetadata);
  assert.deepEqual(Buffer.from(await second.read(parent, record.id, now)), plaintext);
  await second.delete(parent, record.id, now);
  secondMetadata.close();

  const thirdMetadata = new SQLiteEvidenceMetadataRepository(databasePath);
  const third = new EncryptedEvidenceVault(new FilesystemPrivateObjectStore(objectRoot), key, 1024, thirdMetadata);
  await assert.rejects(third.read(parent, record.id, now), (error: unknown) => typeof error === "object" && error !== null && "code" in error && error.code === "EVIDENCE_DELETED");
  assert.equal(await new FilesystemPrivateObjectStore(objectRoot).get(record.objectKey), undefined);
  thirdMetadata.close();
});

test("filesystem object keys cannot escape the private root", async () => {
  const root = await mkdtemp(join(tmpdir(), "getemdone-object-root-"));
  const store = new FilesystemPrivateObjectStore(root);
  await assert.rejects(store.put("../outside", Buffer.from("secret")), /Invalid private object key/);
});

test("production composition fails closed when durable evidence configuration is missing or invalid", () => {
  assert.throws(() => buildProductionApp({}), /DATABASE_PATH is required/);
  assert.throws(() => buildProductionApp({ DATABASE_PATH: ":memory:" }), /EVIDENCE_OBJECT_ROOT is required/);
  assert.throws(() => buildProductionApp({ DATABASE_PATH: ":memory:", EVIDENCE_OBJECT_ROOT: "/tmp/evidence" }), /EVIDENCE_ENCRYPTION_KEY_BASE64 is required/);
  assert.throws(() => buildProductionApp({ DATABASE_PATH: ":memory:", EVIDENCE_OBJECT_ROOT: "/tmp/evidence", EVIDENCE_ENCRYPTION_KEY_BASE64: "bad" }), /32 bytes/);
});
