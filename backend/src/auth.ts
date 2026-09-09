import type { IncomingHttpHeaders } from "node:http";
import { createLocalJWKSet, jwtVerify, type JSONWebKeySet } from "jose";
import { Actor, DomainError, type Role } from "./domain.js";

const roles = new Set<Role>(["owner", "guardian", "child"]);

export interface ActorAuthenticator {
  authenticate(headers: IncomingHttpHeaders): Promise<Actor>;
}

export interface JWTAuthenticationConfiguration {
  issuer: string;
  audience: string;
  jwks: JSONWebKeySet;
}

export function buildJWTAuthenticator(configuration: JWTAuthenticationConfiguration): ActorAuthenticator {
  if (!configuration.issuer || !configuration.audience || configuration.jwks.keys.length === 0) {
    throw new Error("JWT issuer, audience, and at least one verification key are required");
  }
  const verificationKey = createLocalJWKSet(configuration.jwks);

  return {
    async authenticate(headers) {
      const authorization = header(headers.authorization);
      const match = authorization?.match(/^Bearer ([^\s]+)$/i);
      if (!match?.[1]) throw unauthenticated();

      try {
        const { payload } = await jwtVerify(match[1], verificationKey, {
          issuer: configuration.issuer,
          audience: configuration.audience,
          algorithms: ["ES256", "RS256"],
          requiredClaims: ["sub", "household_id", "member_id", "role"]
        });
        const accountId = payload.sub;
        const householdId = stringClaim(payload.household_id);
        const memberId = stringClaim(payload.member_id);
        const role = stringClaim(payload.role);
        if (!accountId || !householdId || !memberId || !role || !roles.has(role as Role)) throw unauthenticated();
        return { accountId, householdId, memberId, role: role as Role };
      } catch (error) {
        if (error instanceof DomainError) throw error;
        throw unauthenticated();
      }
    }
  };
}

/** Explicit test-only identity injection. Never selected from NODE_ENV. */
export function buildTestHeaderAuthenticator(): ActorAuthenticator {
  return {
    async authenticate(headers) {
      const accountId = header(headers["x-test-account-id"]);
      const householdId = header(headers["x-test-household-id"]);
      const memberId = header(headers["x-test-member-id"]);
      const role = header(headers["x-test-role"]);
      if (!accountId || !householdId || !memberId || !role || !roles.has(role as Role)) throw unauthenticated();
      return { accountId, householdId, memberId, role: role as Role };
    }
  };
}

export function jwtAuthenticatorFromEnvironment(environment: NodeJS.ProcessEnv = process.env): ActorAuthenticator {
  const issuer = environment.AUTH_JWT_ISSUER;
  const audience = environment.AUTH_JWT_AUDIENCE;
  const encodedJWKS = environment.AUTH_JWKS_BASE64;
  if (!issuer || !audience || !encodedJWKS) {
    throw new Error("AUTH_JWT_ISSUER, AUTH_JWT_AUDIENCE, and AUTH_JWKS_BASE64 are required");
  }

  let jwks: JSONWebKeySet;
  try {
    jwks = JSON.parse(Buffer.from(encodedJWKS, "base64url").toString("utf8")) as JSONWebKeySet;
  } catch {
    throw new Error("AUTH_JWKS_BASE64 must contain a base64url-encoded JWKS document");
  }
  if (!Array.isArray(jwks.keys)) throw new Error("AUTH_JWKS_BASE64 must contain a JWKS document");
  return buildJWTAuthenticator({ issuer, audience, jwks });
}

function unauthenticated(): DomainError {
  return new DomainError(401, "UNAUTHENTICATED", "Authentication is required");
}

function stringClaim(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function header(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}
