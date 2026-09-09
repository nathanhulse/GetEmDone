import assert from "node:assert/strict";
import { generateKeyPairSync, randomUUID } from "node:crypto";
import { test } from "node:test";
import { exportJWK, SignJWT } from "jose";
import { buildApp } from "../src/app.js";
import { buildJWTAuthenticator, jwtAuthenticatorFromEnvironment } from "../src/auth.js";

const issuer = "https://identity.getemdone.test";
const audience = "getemdone-api";

async function fixture() {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const jwk = await exportJWK(publicKey);
  const keyId = "test-2026-09";
  jwk.kid = keyId;
  jwk.alg = "ES256";
  jwk.use = "sig";
  const authenticator = buildJWTAuthenticator({ issuer, audience, jwks: { keys: [jwk] } });
  const token = (claims: Record<string, unknown> = {}, options: { issuer?: string; audience?: string; expiresIn?: string } = {}) =>
    new SignJWT({ household_id: "home_a", member_id: "parent_a", role: "owner", ...claims })
      .setProtectedHeader({ alg: "ES256", kid: keyId })
      .setSubject("acct_parent")
      .setIssuer(options.issuer ?? issuer)
      .setAudience(options.audience ?? audience)
      .setIssuedAt()
      .setExpirationTime(options.expiresIn ?? "5m")
      .sign(privateKey);
  return { authenticator, token, jwk };
}

test("valid bearer claims establish the actor and preserve household isolation", async () => {
  const { authenticator, token } = await fixture();
  const { app, repository } = buildApp(undefined, undefined, authenticator);
  repository.seed({ id: "occ_auth", householdId: "home_b", childMemberId: "child_b", title: "Bed", state: "open", submissionVersion: 0, version: 1 });
  const response = await app.inject({ method: "POST", url: "/v1/occurrences/occ_auth/submit", headers: { authorization: `Bearer ${await token({ role: "child", member_id: "child_a" })}`, "idempotency-key": randomUUID() } });
  assert.equal(response.statusCode, 404);
  await app.close();
});

test("production authentication ignores spoofed test headers", async () => {
  const { authenticator } = await fixture();
  const { app } = buildApp(undefined, undefined, authenticator);
  const response = await app.inject({ method: "GET", url: "/v1/changes", headers: { "x-test-account-id": "acct", "x-test-household-id": "home", "x-test-member-id": "member", "x-test-role": "owner" } });
  assert.equal(response.statusCode, 401);
  assert.equal(response.json().code, "UNAUTHENTICATED");
  await app.close();
});

test("invalid issuer, audience, expiry, signature, role, and missing claims are rejected", async t => {
  const { authenticator, token } = await fixture();
  const other = await fixture();
  const cases = [
    ["issuer", await token({}, { issuer: "https://attacker.invalid" })],
    ["audience", await token({}, { audience: "another-api" })],
    ["expiry", await token({}, { expiresIn: "-1s" })],
    ["signature", await other.token()],
    ["role", await token({ role: "administrator" })],
    ["household", await token({ household_id: undefined })]
  ] as const;
  for (const [name, jwt] of cases) {
    await t.test(name, async () => {
      const { app } = buildApp(undefined, undefined, authenticator);
      const response = await app.inject({ method: "GET", url: "/v1/changes", headers: { authorization: `Bearer ${jwt}` } });
      assert.equal(response.statusCode, 401);
      assert.equal(response.json().code, "UNAUTHENTICATED");
      await app.close();
    });
  }
});

test("malformed bearer schemes and tokens are rejected", async () => {
  const { authenticator } = await fixture();
  for (const authorization of [undefined, "Basic abc", "Bearer", "Bearer not-a-jwt", "Bearer one two"]) {
    const { app } = buildApp(undefined, undefined, authenticator);
    const response = await app.inject({ method: "GET", url: "/v1/changes", headers: authorization ? { authorization } : {} });
    assert.equal(response.statusCode, 401);
    await app.close();
  }
});

test("environment configuration is mandatory and validates JWKS", () => {
  assert.throws(() => jwtAuthenticatorFromEnvironment({}), /required/);
  assert.throws(() => jwtAuthenticatorFromEnvironment({ AUTH_JWT_ISSUER: issuer, AUTH_JWT_AUDIENCE: audience, AUTH_JWKS_BASE64: "%%%" }), /JWKS/);
});
