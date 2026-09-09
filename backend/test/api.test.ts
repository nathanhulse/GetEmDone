import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { test } from "node:test";
import { buildApp } from "../src/app.js";

const parent = { "x-test-account-id": "acct_parent", "x-test-household-id": "home_a", "x-test-member-id": "parent_a", "x-test-role": "owner" };
const child = { "x-test-account-id": "acct_child", "x-test-household-id": "home_a", "x-test-member-id": "child_a", "x-test-role": "child" };

test("child submit and parent approval synchronize as ordered changes", async () => {
  const { app, repository } = buildApp();
  repository.seed({ id: "occ_1", householdId: "home_a", childMemberId: "child_a", title: "Make bed", state: "open", submissionVersion: 0, version: 1 });
  const submitted = await app.inject({ method: "POST", url: "/v1/occurrences/occ_1/submit", headers: { ...child, "idempotency-key": randomUUID() } });
  assert.equal(submitted.statusCode, 200);
  assert.equal(submitted.json().state, "submitted");
  const approved = await app.inject({ method: "POST", url: "/v1/occurrences/occ_1/decisions", headers: { ...parent, "idempotency-key": randomUUID() }, payload: { submissionVersion: 1, decision: "approve" } });
  assert.equal(approved.statusCode, 200);
  assert.equal(approved.json().state, "approved");
  const changes = await app.inject({ method: "GET", url: "/v1/changes?after=0", headers: parent });
  assert.deepEqual(changes.json().changes.map((change: { type: string }) => change.type), ["occurrence.submitted", "occurrence.approved"]);
  await app.close();
});

test("idempotent retry returns original response and does not duplicate changes", async () => {
  const { app, repository } = buildApp();
  repository.seed({ id: "occ_2", householdId: "home_a", childMemberId: "child_a", title: "Piano", state: "open", submissionVersion: 0, version: 1 });
  const key = randomUUID();
  const first = await app.inject({ method: "POST", url: "/v1/occurrences/occ_2/submit", headers: { ...child, "idempotency-key": key } });
  const retry = await app.inject({ method: "POST", url: "/v1/occurrences/occ_2/submit", headers: { ...child, "idempotency-key": key } });
  assert.deepEqual(retry.json(), first.json());
  const changes = await app.inject({ method: "GET", url: "/v1/changes", headers: parent });
  assert.equal(changes.json().changes.length, 1);
  await app.close();
});

test("authorization prevents cross-household and child review", async () => {
  const { app, repository } = buildApp();
  repository.seed({ id: "occ_3", householdId: "home_a", childMemberId: "child_a", title: "Bed", state: "submitted", submissionVersion: 1, version: 2 });
  const review = await app.inject({ method: "POST", url: "/v1/occurrences/occ_3/decisions", headers: { ...child, "idempotency-key": randomUUID() }, payload: { submissionVersion: 1, decision: "approve" } });
  assert.equal(review.statusCode, 403);
  const outsider = await app.inject({ method: "POST", url: "/v1/occurrences/occ_3/submit", headers: { ...child, "x-test-household-id": "home_b", "idempotency-key": randomUUID() } });
  assert.equal(outsider.statusCode, 404);
  await app.close();
});

test("reuse of idempotency key with different input is rejected", async () => {
  const { app, repository } = buildApp();
  repository.seed({ id: "occ_4", householdId: "home_a", childMemberId: "child_a", title: "Bed", state: "submitted", submissionVersion: 1, version: 2 });
  const key = randomUUID();
  await app.inject({ method: "POST", url: "/v1/occurrences/occ_4/decisions", headers: { ...parent, "idempotency-key": key }, payload: { submissionVersion: 1, decision: "redo" } });
  const reused = await app.inject({ method: "POST", url: "/v1/occurrences/occ_4/decisions", headers: { ...parent, "idempotency-key": key }, payload: { submissionVersion: 1, decision: "approve" } });
  assert.equal(reused.statusCode, 409);
  assert.equal(reused.json().code, "IDEMPOTENCY_KEY_REUSED");
  await app.close();
});

