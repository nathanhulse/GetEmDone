import Fastify from "fastify";
import { Actor, DomainError, HouseholdRepository } from "./domain.js";
import { SQLiteHouseholdRepository } from "./sqlite-repository.js";
import { EncryptedEvidenceVault, FilesystemPrivateObjectStore, MemoryPrivateObjectStore, SQLiteEvidenceMetadataRepository } from "./evidence.js";
import { jwtAuthenticatorFromEnvironment, type ActorAuthenticator } from "./auth.js";

export function buildApp(
  repository: HouseholdRepository = process.env.DATABASE_PATH ? new SQLiteHouseholdRepository(process.env.DATABASE_PATH) : new HouseholdRepository(),
  evidenceVault = new EncryptedEvidenceVault(new MemoryPrivateObjectStore(), evidenceKey()),
  authenticator: ActorAuthenticator = jwtAuthenticatorFromEnvironment()
) {
  const app = Fastify({ logger: false, bodyLimit: 7 * 1024 * 1024 });

  app.setErrorHandler((error, request, reply) => {
    if (error instanceof DomainError) {
      return reply.status(error.status).type("application/problem+json").send({
        code: error.code, title: error.message, status: error.status, requestId: request.id
      });
    }
    request.log.error({ err: error }, "request failed");
    return reply.status(500).type("application/problem+json").send({ code: "INTERNAL", title: "Request failed", status: 500, requestId: request.id });
  });

  app.decorateRequest("actor");
  app.addHook("preHandler", async request => {
    if (request.url.startsWith("/health/")) return;
    request.actor = await authenticator.authenticate(request.headers);
  });

  app.get("/health/live", async () => ({ status: "ok" }));
  app.get("/health/ready", async () => ({ status: "ready" }));

  app.post<{ Params: { id: string } }>("/v1/occurrences/:id/submit", async (request, reply) => {
    const result = repository.submit(request.actor, request.params.id, header(request.headers["idempotency-key"]) ?? "");
    return reply.send(result);
  });

  app.post<{ Params: { id: string }; Body: { submissionVersion: number; decision: "approve" | "redo"; note?: string } }>("/v1/occurrences/:id/decisions", async (request, reply) => {
    const body = request.body;
    if (!body || !Number.isInteger(body.submissionVersion) || !["approve", "redo"].includes(body.decision)) {
      throw new DomainError(400, "INVALID_BODY", "A valid decision and submission version are required");
    }
    return reply.send(repository.decide(request.actor, request.params.id, body.submissionVersion, body.decision, body.note, header(request.headers["idempotency-key"]) ?? ""));
  });

  app.get<{ Querystring: { after?: string } }>("/v1/changes", async request => {
    const after = Number.parseInt(request.query.after ?? "0", 10);
    return repository.listChanges(request.actor, Number.isFinite(after) ? after : 0);
  });

  app.post<{ Params: { id: string }; Body: { childMemberId: string; contentType: "image/jpeg" | "image/png" | "audio/mp4"; base64: string; expiresAt: string } }>("/v1/evidence/:id", async (request, reply) => {
    const body = request.body;
    if (!body?.childMemberId || !["image/jpeg", "image/png", "audio/mp4"].includes(body.contentType) || !body.base64 || Number.isNaN(Date.parse(body.expiresAt))) {
      throw new DomainError(400, "INVALID_BODY", "Valid evidence metadata and content are required");
    }
    const record = await evidenceVault.save({ actor: request.actor, id: request.params.id, childMemberId: body.childMemberId, contentType: body.contentType, plaintext: Buffer.from(body.base64, "base64"), now: new Date(), expiresAt: new Date(body.expiresAt) });
    return reply.status(201).send({ ...record, objectKey: undefined });
  });

  app.get<{ Params: { id: string } }>("/v1/evidence/:id/content", async (request, reply) => {
    const record = evidenceVault.getRecord(request.actor, request.params.id);
    const content = await evidenceVault.read(request.actor, request.params.id, new Date());
    return reply.type(record.contentType).header("cache-control", "private, no-store").send(Buffer.from(content));
  });

  app.delete<{ Params: { id: string } }>("/v1/evidence/:id", async (request, reply) => {
    await evidenceVault.delete(request.actor, request.params.id, new Date());
    return reply.status(204).send();
  });

  return { app, repository, evidenceVault };
}

export function buildProductionApp(environment: NodeJS.ProcessEnv = process.env) {
  const databasePath = requiredEnvironment(environment, "DATABASE_PATH");
  const objectRoot = requiredEnvironment(environment, "EVIDENCE_OBJECT_ROOT");
  const encodedKey = requiredEnvironment(environment, "EVIDENCE_ENCRYPTION_KEY_BASE64");
  const key = Buffer.from(encodedKey, "base64");
  if (key.byteLength !== 32) throw new Error("EVIDENCE_ENCRYPTION_KEY_BASE64 must decode to 32 bytes");
  const metadataPath = environment.EVIDENCE_METADATA_DATABASE_PATH ?? databasePath;
  const repository = new SQLiteHouseholdRepository(databasePath);
  const metadata = new SQLiteEvidenceMetadataRepository(metadataPath);
  const vault = new EncryptedEvidenceVault(new FilesystemPrivateObjectStore(objectRoot), key, 5 * 1024 * 1024, metadata);
  return buildApp(repository, vault, jwtAuthenticatorFromEnvironment(environment));
}

function evidenceKey(): Uint8Array {
  const encoded = process.env.EVIDENCE_ENCRYPTION_KEY_BASE64;
  if (!encoded) return Buffer.alloc(32, 0); // Development only; production startup validates its secret externally.
  const key = Buffer.from(encoded, "base64");
  if (key.byteLength !== 32) throw new Error("EVIDENCE_ENCRYPTION_KEY_BASE64 must decode to 32 bytes");
  return key;
}

function header(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function requiredEnvironment(environment: NodeJS.ProcessEnv, name: string): string {
  const value = environment[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}

declare module "fastify" {
  interface FastifyRequest { actor: Actor; }
}
