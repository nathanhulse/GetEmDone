import assert from "node:assert/strict";
import { test } from "node:test";
import { Actor, DomainError } from "../src/domain.js";
import { EncryptedEvidenceVault, MemoryPrivateObjectStore } from "../src/evidence.js";

const child: Actor = { accountId: "acct_child", householdId: "home_a", memberId: "child_a", role: "child" };
const parent: Actor = { accountId: "acct_parent", householdId: "home_a", memberId: "parent_a", role: "owner" };
const outsider: Actor = { accountId: "acct_out", householdId: "home_b", memberId: "parent_b", role: "owner" };
const now = new Date("2026-09-09T12:00:00Z");

function fixture() {
  const store = new MemoryPrivateObjectStore();
  const vault = new EncryptedEvidenceVault(store, Buffer.alloc(32, 7));
  return { store, vault };
}

test("evidence is encrypted at rest and decrypts for household guardian", async () => {
  const { store, vault } = fixture();
  const plaintext = Buffer.from("pretend-jpeg-private-child-photo");
  const record = await vault.save({ actor: child, id: "ev_1", childMemberId: "child_a", contentType: "image/jpeg", plaintext, now, expiresAt: new Date("2026-09-10T12:00:00Z") });
  const stored = store.objects.get(record.objectKey);
  assert.ok(stored);
  assert.equal(Buffer.from(stored).includes(plaintext), false);
  assert.deepEqual(Buffer.from(await vault.read(parent, record.id, now)), plaintext);
});

test("cross-household evidence access is concealed", async () => {
  const { vault } = fixture();
  await vault.save({ actor: child, id: "ev_2", childMemberId: "child_a", contentType: "image/jpeg", plaintext: Buffer.from("photo"), now, expiresAt: new Date("2026-09-10T12:00:00Z") });
  await assert.rejects(vault.read(outsider, "ev_2", now), (error: unknown) => error instanceof DomainError && error.status === 404);
});

test("expired evidence cannot be viewed and purge verifies object removal", async () => {
  const { store, vault } = fixture();
  const record = await vault.save({ actor: child, id: "ev_3", childMemberId: "child_a", contentType: "image/png", plaintext: Buffer.from("photo"), now, expiresAt: new Date("2026-09-09T13:00:00Z") });
  const afterExpiry = new Date("2026-09-09T13:00:01Z");
  await assert.rejects(vault.read(parent, record.id, afterExpiry), (error: unknown) => error instanceof DomainError && error.code === "EVIDENCE_EXPIRED");
  assert.equal(await vault.purgeExpired(afterExpiry), 1);
  assert.equal(store.objects.has(record.objectKey), false);
});

test("deletion is idempotent and makes evidence unavailable", async () => {
  const { store, vault } = fixture();
  const record = await vault.save({ actor: child, id: "ev_4", childMemberId: "child_a", contentType: "audio/mp4", plaintext: Buffer.from("audio"), now, expiresAt: new Date("2026-09-10T12:00:00Z") });
  await vault.delete(parent, record.id, now);
  await vault.delete(parent, record.id, now);
  assert.equal(store.objects.has(record.objectKey), false);
  await assert.rejects(vault.read(parent, record.id, now), (error: unknown) => error instanceof DomainError && error.code === "EVIDENCE_DELETED");
});

test("size limits and child ownership are enforced", async () => {
  const { vault } = fixture();
  await assert.rejects(vault.save({ actor: parent, id: "ev_5", childMemberId: "child_a", contentType: "image/jpeg", plaintext: Buffer.from("photo"), now, expiresAt: new Date("2026-09-10T12:00:00Z") }), (error: unknown) => error instanceof DomainError && error.status === 403);
  const tinyVault = new EncryptedEvidenceVault(new MemoryPrivateObjectStore(), Buffer.alloc(32, 1), 2);
  await assert.rejects(tinyVault.save({ actor: child, id: "ev_6", childMemberId: "child_a", contentType: "image/jpeg", plaintext: Buffer.from("large"), now, expiresAt: new Date("2026-09-10T12:00:00Z") }), (error: unknown) => error instanceof DomainError && error.status === 413);
});

