import Fastify from "fastify";
import { Actor, DomainError, HouseholdRepository } from "./domain.js";

export function buildApp(repository = new HouseholdRepository()) {
  const app = Fastify({ logger: false, bodyLimit: 256 * 1024 });

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
    const accountId = header(request.headers["x-test-account-id"]);
    const householdId = header(request.headers["x-test-household-id"]);
    const memberId = header(request.headers["x-test-member-id"]);
    const role = header(request.headers["x-test-role"]);
    if (!accountId || !householdId || !memberId || !["owner", "guardian", "child"].includes(role ?? "")) {
      throw new DomainError(401, "UNAUTHENTICATED", "Authentication is required");
    }
    request.actor = { accountId, householdId, memberId, role: role as Actor["role"] };
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

  return { app, repository };
}

function header(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

declare module "fastify" {
  interface FastifyRequest { actor: Actor; }
}
