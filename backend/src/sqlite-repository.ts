import { DatabaseSync } from "node:sqlite";
import { Actor, HouseholdRepository, Occurrence, RepositoryState } from "./domain.js";

export class SQLiteHouseholdRepository extends HouseholdRepository {
  private readonly database: DatabaseSync;

  constructor(path: string) {
    const database = new DatabaseSync(path);
    database.exec(`
      PRAGMA journal_mode = WAL;
      PRAGMA foreign_keys = ON;
      CREATE TABLE IF NOT EXISTS repository_state (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        state_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    `);
    const row = database.prepare("SELECT state_json FROM repository_state WHERE singleton = 1").get() as { state_json: string } | undefined;
    super(row ? JSON.parse(row.state_json) as RepositoryState : undefined);
    this.database = database;
  }

  override seed(occurrence: Occurrence): void {
    super.seed(occurrence);
    this.flush();
  }

  override submit(actor: Actor, occurrenceId: string, key: string): Occurrence {
    const result = super.submit(actor, occurrenceId, key);
    this.flush();
    return result;
  }

  override decide(actor: Actor, occurrenceId: string, submissionVersion: number, decision: "approve" | "redo", note: string | undefined, key: string): Occurrence {
    const result = super.decide(actor, occurrenceId, submissionVersion, decision, note, key);
    this.flush();
    return result;
  }

  close(): void { this.database.close(); }

  private flush(): void {
    this.database.prepare(`
      INSERT INTO repository_state (singleton, state_json, updated_at) VALUES (1, ?, ?)
      ON CONFLICT(singleton) DO UPDATE SET state_json = excluded.state_json, updated_at = excluded.updated_at
    `).run(JSON.stringify(this.exportState()), new Date().toISOString());
  }
}
