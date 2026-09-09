import { createHash, randomUUID } from "node:crypto";

export type Role = "owner" | "guardian" | "child";
export type OccurrenceState = "open" | "submitted" | "approved";

export interface Actor {
  accountId: string;
  householdId: string;
  memberId: string;
  role: Role;
}

export interface Occurrence {
  id: string;
  householdId: string;
  childMemberId: string;
  title: string;
  state: OccurrenceState;
  submissionVersion: number;
  version: number;
  note?: string;
}

export interface Change {
  cursor: number;
  householdId: string;
  type: string;
  resourceId: string;
  version: number;
}

export interface RepositoryState {
  occurrences: Occurrence[];
  idempotency: Array<[string, { hash: string; response: unknown }]>;
  changes: Change[];
  cursor: number;
}

export class DomainError extends Error {
  constructor(public readonly status: number, public readonly code: string, message: string) {
    super(message);
  }
}

export class HouseholdRepository {
  private readonly occurrences = new Map<string, Occurrence>();
  private readonly idempotency = new Map<string, { hash: string; response: unknown }>();
  private readonly changes: Change[] = [];
  private cursor = 0;

  constructor(state?: RepositoryState) {
    for (const occurrence of state?.occurrences ?? []) this.occurrences.set(occurrence.id, structuredClone(occurrence));
    for (const [key, value] of state?.idempotency ?? []) this.idempotency.set(key, structuredClone(value));
    this.changes = structuredClone(state?.changes ?? []);
    this.cursor = state?.cursor ?? 0;
  }

  exportState(): RepositoryState {
    return {
      occurrences: [...this.occurrences.values()].map(value => structuredClone(value)),
      idempotency: [...this.idempotency.entries()].map(([key, value]) => [key, structuredClone(value)]),
      changes: structuredClone(this.changes),
      cursor: this.cursor
    };
  }

  seed(occurrence: Occurrence): void { this.occurrences.set(occurrence.id, structuredClone(occurrence)); }

  getOccurrence(actor: Actor, occurrenceId: string): Occurrence {
    const value = this.occurrences.get(occurrenceId);
    if (!value || value.householdId !== actor.householdId) throw new DomainError(404, "NOT_FOUND", "Occurrence not found");
    if (actor.role === "child" && value.childMemberId !== actor.memberId) throw new DomainError(404, "NOT_FOUND", "Occurrence not found");
    return structuredClone(value);
  }

  submit(actor: Actor, occurrenceId: string, key: string): Occurrence {
    if (actor.role !== "child") throw new DomainError(403, "ROLE_FORBIDDEN", "Only the assigned child can submit");
    return this.command(actor, "submit", occurrenceId, {}, key, () => {
      const current = this.getOccurrence(actor, occurrenceId);
      if (current.state === "submitted") return current;
      if (current.state !== "open") throw new DomainError(409, "INVALID_STATE", "Occurrence cannot be submitted");
      current.state = "submitted";
      current.submissionVersion += 1;
      current.version += 1;
      this.storeChange(current, "occurrence.submitted");
      return current;
    });
  }

  decide(actor: Actor, occurrenceId: string, submissionVersion: number, decision: "approve" | "redo", note: string | undefined, key: string): Occurrence {
    if (actor.role === "child") throw new DomainError(403, "ROLE_FORBIDDEN", "A guardian must review submissions");
    return this.command(actor, "decide", occurrenceId, { submissionVersion, decision, note }, key, () => {
      const current = this.getOccurrence(actor, occurrenceId);
      if (current.state !== "submitted") throw new DomainError(409, "ALREADY_DECIDED", "Occurrence is not awaiting review");
      if (current.submissionVersion !== submissionVersion) throw new DomainError(409, "SUBMISSION_CHANGED", "Submission changed before review");
      current.state = decision === "approve" ? "approved" : "open";
      if (note?.trim()) current.note = note.trim();
      current.version += 1;
      this.storeChange(current, decision === "approve" ? "occurrence.approved" : "occurrence.redo");
      return current;
    });
  }

  listChanges(actor: Actor, after: number): { changes: Change[]; cursor: number } {
    return {
      changes: this.changes.filter(change => change.householdId === actor.householdId && change.cursor > after),
      cursor: this.cursor
    };
  }

  private command<T>(actor: Actor, route: string, resourceId: string, body: unknown, key: string, action: () => T): T {
    if (!/^[0-9a-f-]{36}$/i.test(key)) throw new DomainError(400, "IDEMPOTENCY_REQUIRED", "A UUID idempotency key is required");
    const identity = `${actor.accountId}:${route}:${key}`;
    const hash = createHash("sha256").update(JSON.stringify({ resourceId, body })).digest("hex");
    const previous = this.idempotency.get(identity);
    if (previous) {
      if (previous.hash !== hash) throw new DomainError(409, "IDEMPOTENCY_KEY_REUSED", "Idempotency key was reused with different input");
      return structuredClone(previous.response) as T;
    }
    const response = action();
    this.idempotency.set(identity, { hash, response: structuredClone(response) });
    return response;
  }

  private storeChange(value: Occurrence, type: string): void {
    this.occurrences.set(value.id, structuredClone(value));
    this.cursor += 1;
    this.changes.push({ cursor: this.cursor, householdId: value.householdId, type, resourceId: value.id, version: value.version });
  }
}

export function makeId(prefix: string): string { return `${prefix}_${randomUUID()}`; }
