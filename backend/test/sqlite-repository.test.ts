import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { SQLiteHouseholdRepository } from "../src/sqlite-repository.js";

const child = { accountId: "acct_child", householdId: "home_a", memberId: "child_a", role: "child" as const };

test("SQLite repository survives restart with changes and idempotency", () => {
  const path = join(mkdtempSync(join(tmpdir(), "getemdone-")), "backend.sqlite");
  const key = randomUUID();
  const first = new SQLiteHouseholdRepository(path);
  first.seed({ id: "occ_durable", householdId: "home_a", childMemberId: "child_a", title: "Piano", state: "open", submissionVersion: 0, version: 1 });
  first.submit(child, "occ_durable", key);
  first.close();

  const restored = new SQLiteHouseholdRepository(path);
  assert.equal(restored.getOccurrence(child, "occ_durable").state, "submitted");
  assert.equal(restored.listChanges(child, 0).changes.length, 1);
  restored.submit(child, "occ_durable", key);
  assert.equal(restored.listChanges(child, 0).changes.length, 1);
  restored.close();
});
