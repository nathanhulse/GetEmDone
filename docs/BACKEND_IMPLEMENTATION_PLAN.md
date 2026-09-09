# GetEmDone Backend Implementation Plan

Status: implementation-ready proposal  
Scope: household synchronization through private evidence lifecycle  
Last reviewed: 2026-09-09

Implementation note: `backend/src/evidence.ts` now provides the tested encrypted-vault contract with household authorization, AES-256-GCM authenticated encryption, size limits, retention expiry, idempotent deletion, and verified purge behavior. The in-memory private object store is a test adapter; production must supply private S3-compatible storage and an externally managed rotating encryption key.

## 1. Decision and boundaries

Build a small TypeScript service on the current Node.js LTS runtime, backed by PostgreSQL and private S3-compatible object storage.

Recommended production components:

- Node.js LTS + TypeScript in strict mode.
- Fastify for HTTP routing, validation hooks, request limits, and structured logging.
- PostgreSQL for household, occurrence, command, audit, and outbox data.
- `pg` plus checked-in SQL migrations; avoid an ORM initially.
- AWS SDK S3 client for private evidence objects and presigned upload/download URLs.
- `jose` for Apple identity-token verification and server-signed policy/grant envelopes.
- Node's built-in `node:test` runner for unit and integration tests.

This is a better fit than adding a Swift server target: it starts quickly in GitHub Actions, has mature identity/object-storage libraries, keeps migrations explicit, and does not tie server deployment to Xcode. The service should live under `backend/` in this repository so API contracts and iOS DTOs change in the same pull request.

The first backend does **not** apply Screen Time shields, store Apple's opaque Family Activity selections, analyze evidence, send router commands, or decide whether a chore was performed well. It coordinates household state. The child device remains responsible for local enforcement; a parent's explicit decision remains authoritative.

## 2. Deployment shape

Start as one stateless service and one worker process from the same codebase:

```text
iOS parent/child apps
        |
        | HTTPS bearer token
        v
 Fastify API ---------- PostgreSQL
        |                    |
        | presigned URLs     +-- transactional outbox
        v                    |
 private object store       v
                       worker -> APNs / object deletion
```

The API and worker may initially run in one container with separate commands. Do not introduce queues, Redis, microservices, GraphQL, or Kubernetes before load requires them. PostgreSQL advisory locking and `FOR UPDATE SKIP LOCKED` are sufficient for the initial outbox worker.

Local development and CI use PostgreSQL in a service container and a local S3-compatible emulator only for object-lifecycle contract tests. Most evidence tests use an in-memory fake implementing the same object-store interface.

## 3. Identity, enrollment, and sessions

### Sign in with Apple

1. The app obtains a Sign in with Apple authorization code and identity token.
2. `POST /v1/auth/apple/exchange` verifies issuer, audience, signature, nonce, expiry, and authorization-code exchange with Apple.
3. The service creates or resolves an `account` by Apple's stable subject scoped to the app's Services ID.
4. The service returns a 15-minute access token and a rotating, opaque refresh token.
5. Only a salted SHA-256 digest of the refresh token is stored. Rotation revokes the prior token family on reuse detection.

Access tokens contain only `session_id`, `account_id`, issued/expiry times, audience, and key ID. Household role is loaded from the database on each authorized request so a removed guardian does not retain stale privileges.

### Household enrollment

- The first authenticated adult creates a household and becomes `owner`.
- An owner creates a single-use invitation with role `guardian` or `child`, a 15-minute expiry, and a random 128-bit secret.
- Invitation secrets are shown as a QR/deep link and stored only as hashes.
- Redeeming a child invitation binds an authenticated account and a generated app installation ID to a child member.
- Family Controls authorization is still performed locally through Apple. Backend membership never implies Screen Time authorization.
- Adding/removing a guardian, enrolling a child device, viewing evidence, exporting data, and household deletion require recent authentication (default: Sign in with Apple within the previous 10 minutes or successful platform reauthentication).

### Roles

| Action | Owner | Guardian | Child |
|---|---:|---:|---:|
| Manage household/guardians | Yes | No | No |
| Create/edit/archive routines | Yes | Yes | No |
| Enroll/remove child devices | Yes | Yes | No |
| Submit own occurrences/evidence | No | No | Yes, self only |
| View own evidence | Yes | Yes | Yes, self only |
| Review/approve/request redo | Yes | Yes | No |
| Delete evidence | Yes | Yes | Replace own pending evidence only |
| Issue access grant | Yes | Yes | No |
| View audit activity | Yes | Yes | Own child-facing events only |
| Export/delete household | Yes | No | No |

Every resource query includes `household_id`; authorization must not rely on an unverified path identifier. Database repositories accept an authorization scope object, not a bare resource ID. Child requests additionally constrain `member_id` and enrolled `device_id`.

## 4. Persistence model

All identifiers are server-generated UUIDv7 values serialized with opaque prefixes (`hh_`, `mem_`, `dev_`, `tpl_`, `occ_`, `ev_`, `dec_`, `grant_`). Store UUID values natively; prefixes exist only at the API boundary.

Core tables:

- `accounts`: Apple subject, status, created/deleted timestamps.
- `sessions`: account, refresh-token digest, token family, expiry, revoked timestamp.
- `households`: name, IANA timezone, evidence retention days, monotonically increasing `sync_version`.
- `memberships`: household, account, role (`owner`, `guardian`, `child`), display name, status.
- `devices`: household, child member, installation public key, APNs environment/token ciphertext, capabilities, last seen, revoked timestamp.
- `chore_templates`: household, assigned child, title/detail, evidence type, recurrence JSON, due local minutes, minimum timer seconds, position, active/archive state, resource version.
- `chore_occurrences`: household, child, template, `local_date`, timezone, state, submission version, timestamps, unique `(template_id, local_date)`.
- `evidence`: household, occurrence, submission version, kind, object key, media type, byte count, checksum, upload state, retention expiry, deletion timestamps.
- `decisions`: occurrence, submission version, guardian, result, note, created timestamp; unique `(occurrence_id, submission_version)`.
- `access_grants`: child/device, scope, not-before/expiry, nonce, signing key, revoked timestamp.
- `idempotency_records`: household, actor, key, route, request hash, status, response body, expiry.
- `audit_events`: household, actor, subject child, action, resource type/id, safe metadata, timestamp.
- `outbox_events`: aggregate/version, event type, safe payload, delivery attempts, next attempt, completed timestamp.
- `deletion_jobs`: household/evidence target, phase, attempt count, verification timestamp.

The current iOS `Chore` model mixes a reusable definition with today's progress. Before integration, split it into `ChoreTemplate` and `ChoreOccurrence`. Never synchronize `HouseholdSnapshot` wholesale; doing so would create last-writer-wins data loss and ambiguous daily rollover.

Occurrence identity is household-local date plus template ID. The backend materializes today and a short look-ahead window using the household's IANA timezone. A transaction and the unique constraint make materialization safe to retry. The API returns the exact `localDate`, `timezone`, and occurrence IDs; clients do not invent occurrence IDs from UTC.

## 5. HTTP conventions

- Base path: `/v1`; JSON uses camelCase and RFC 3339 UTC timestamps.
- All authenticated calls use `Authorization: Bearer <access-token>`.
- Commands require `Idempotency-Key`, a random UUID generated once and retained through retries.
- Mutable resources expose integer `version` and `ETag: "<version>"`; updates require `If-Match`.
- Errors use `application/problem+json` with stable `code`, `title`, `status`, `requestId`, and optional field errors. No child names, evidence keys, or tokens appear in errors/logs.
- Collection pagination uses opaque cursors. Default 50, maximum 100.
- Request JSON maximum is 256 KiB. Evidence bytes never pass through the API.
- APNs payloads contain resource ID and version only. A notification is a refresh hint, not an approval or grant.

Idempotency behavior:

1. Begin transaction and lock/create `(actor_id, route, idempotency_key)`.
2. Hash the canonical command body and relevant path parameters.
3. If a completed record has the same hash, return its original status/body.
4. If the key exists with another hash, return `409 IDEMPOTENCY_KEY_REUSED`.
5. Perform state transition, audit append, outbox append, and idempotency response in one transaction.
6. Retain command records for 30 days. Evidence-upload initiation records persist until the associated evidence is deleted.

## 6. Minimal API schema

### Authentication and enrollment

```text
POST   /v1/auth/apple/exchange
POST   /v1/auth/refresh
POST   /v1/auth/logout
POST   /v1/households
POST   /v1/households/{householdId}/invitations
POST   /v1/invitations/{token}/redeem
POST   /v1/children/{childId}/devices
DELETE /v1/devices/{deviceId}
```

Example device enrollment command:

```json
{
  "installationId": "client-generated-uuid",
  "name": "Maya's iPhone",
  "platform": "ios",
  "publicKey": "base64url-spki",
  "capabilities": ["familyControls", "photoEvidence"],
  "apns": { "environment": "sandbox", "token": "hex-token" }
}
```

The server returns `deviceId`, membership summary, `syncCursor`, and the current signing-key set. A platform-generated installation key is held in Keychain/Secure Enclave where available.

### Routines and daily synchronization

```text
GET    /v1/households/{householdId}/bootstrap
GET    /v1/households/{householdId}/changes?after={cursor}
POST   /v1/children/{childId}/chore-templates
PATCH  /v1/chore-templates/{templateId}
POST   /v1/chore-templates/{templateId}/archive
POST   /v1/chore-templates/reorder
GET    /v1/children/{childId}/days/{yyyy-mm-dd}
```

`bootstrap` returns household settings, caller membership, authorized children, active templates, today's occurrences, active grants, and a signed opaque sync cursor. `changes` returns ordered typed changes and a new cursor. If the cursor is expired, it returns `410 SYNC_CURSOR_EXPIRED` and the client repeats bootstrap.

Template create body:

```json
{
  "assignedChildId": "mem_...",
  "title": "Practice piano",
  "detail": "20 focused minutes",
  "evidenceRequirement": { "kind": "timer", "minimumSeconds": 1200 },
  "recurrence": { "kind": "weekly", "weekdays": [1, 2, 3, 4, 5, 6, 7] },
  "dueLocalMinutes": 480,
  "position": 3
}
```

Server response objects include `id`, `version`, `createdAt`, and `updatedAt`. Recurrence weekday numbering must be defined as ISO 8601 Monday=1 through Sunday=7; map explicitly from Foundation Calendar values.

### Completion, evidence, and review

```text
POST   /v1/occurrences/{occurrenceId}/check-in
POST   /v1/occurrences/{occurrenceId}/timer-sessions
POST   /v1/occurrences/{occurrenceId}/evidence-uploads
POST   /v1/evidence/{evidenceId}/complete
DELETE /v1/evidence/{evidenceId}
POST   /v1/occurrences/{occurrenceId}/submit
POST   /v1/occurrences/{occurrenceId}/decisions
GET    /v1/children/{childId}/review-queue
```

Upload initiation body:

```json
{
  "kind": "photo",
  "contentType": "image/jpeg",
  "byteCount": 842119,
  "sha256": "base64url-digest",
  "submissionVersion": 2
}
```

Response:

```json
{
  "evidenceId": "ev_...",
  "upload": {
    "method": "PUT",
    "url": "short-lived-presigned-url",
    "requiredHeaders": { "content-type": "image/jpeg" },
    "expiresAt": "2026-09-09T15:05:00Z"
  },
  "maximumBytes": 5242880
}
```

The client uploads directly, then calls `complete`. Completion validates object existence, exact length, media type, checksum, ownership, and submission version before marking it ready. `submit` succeeds only if the occurrence's evidence rule is satisfied. Replacing pending evidence increments `submissionVersion`, invalidates old review URLs, and queues the replaced object for deletion.

Decision command:

```json
{
  "submissionVersion": 2,
  "decision": "approve",
  "note": null
}
```

Allowed decisions are `approve` and `redo`. The server rejects a decision for an old submission version with `409 SUBMISSION_CHANGED`. Approval, decision/audit creation, access-grant derivation, sync-version increment, and APNs outbox append occur atomically.

### Evidence viewing and deletion

```text
POST   /v1/evidence/{evidenceId}/view-session
DELETE /v1/evidence/{evidenceId}
PATCH  /v1/households/{householdId}/evidence-policy
POST   /v1/households/{householdId}/exports
DELETE /v1/households/{householdId}
GET    /v1/deletion-jobs/{jobId}
```

`view-session` requires a guardian or the owning child, recent guardian authentication for guardians, and evidence that is not expired/deleting. It returns a single-object GET URL valid for at most 60 seconds. Do not proxy media through logs/CDNs with public caching.

### Device synchronization and reports

```text
GET    /v1/devices/{deviceId}/policy
POST   /v1/devices/{deviceId}/policy-acknowledgements
POST   /v1/devices/{deviceId}/enforcement-reports
POST   /v1/children/{childId}/access-grants
POST   /v1/access-grants/{grantId}/redemptions
PUT    /v1/devices/{deviceId}/push-token
```

Policy responses are signed envelopes with monotonic `policyVersion`, device audience, effective local date/timezone, required occurrence IDs, active grants, issued/expiry times, and key ID. They contain no evidence and no Apple Family Activity tokens.

### Health and operations

```text
GET /health/live
GET /health/ready
```

Readiness checks database connectivity and migration compatibility, not third-party APNs/Object Store availability. Production metrics use bounded household-hashed labels; never label by member, device, evidence, chore title, or raw household ID.

## 7. State machines and conflict rules

Occurrence states:

```text
open -> ready -> submitted -> approved
  ^        ^         |
  |        +---------+-- redo
  +--------------------- reset/replace before review
```

- Only the assigned child may move `open` toward `ready` and `submitted`.
- Only an owner/guardian may decide a submitted occurrence.
- Approval is terminal for that occurrence/day except an explicit, audited guardian reversal added in a later tranche.
- Redo increments `submissionVersion`, preserves the decision audit record, moves state to `open` or `ready` according to retained non-media evidence, and deletes/replaces media according to policy.
- Timer sessions record server receipt and client monotonic elapsed duration. They demonstrate elapsed time, not continuous attention; suspicious values may be shown to a guardian but must not silently reject a child.
- Two guardians racing to decide use the occurrence version. The first valid decision wins; the second receives `409 ALREADY_DECIDED` with the current representation.
- Client offline commands retain their original idempotency key. A stale `If-Match` returns the latest resource plus a conflict code; clients must not silently overwrite it.

## 8. Evidence security and privacy

### Collection and transport

- Accept only configured media types (`image/jpeg`, `image/heic` initially); reject executable/polyglot and malformed content after upload validation.
- Strip EXIF/GPS metadata on-device before upload. The server should independently decode and re-encode accepted images in an isolated worker before making them reviewable.
- Compress images on-device; default maximum 5 MiB and maximum 12 megapixels. No video or audio in the first backend tranche.
- Use TLS 1.2+ and presigned URLs scoped to one object, method, expected content type/length, and five-minute maximum lifetime.
- Object keys are random and contain no household/member/chore names.

### Encryption and key separation

- Object storage uses server-side encryption with a customer-managed KMS key, bucket public access disabled, versioning disabled unless deletion semantics are explicitly updated, and lifecycle rules as defense in depth.
- Database volumes/backups are encrypted by the hosting provider. Sensitive APNs/router tokens use application-envelope encryption with a separate KMS key.
- Evidence metadata and object access are always authorized through the database; possession of an evidence ID is insufficient.
- Production, staging, and development use separate accounts, buckets, databases, signing keys, and Apple push credentials.
- Service identities receive only needed prefixes/actions. The API can create presigned operations; the deletion worker can delete; analytics and support cannot read objects.

Client-side end-to-end evidence encryption is deferred because parent-device key distribution, multiple guardians, recovery, and server-side media validation substantially expand risk. This decision must be disclosed accurately: evidence is encrypted in transit and at rest, but the service operator can technically decrypt it under tightly controlled access.

### Retention and deletion

- Default evidence retention: 24 hours after final decision; parent options: immediately after decision, 24 hours, or 7 days. Seven days is the initial hard maximum.
- Unfinished uploads expire and are deleted within 1 hour.
- Replaced evidence is queued for deletion immediately.
- Evidence metadata enters `deleting`, access is denied immediately, and an outbox deletion job removes the object. On success, retain a non-sensitive tombstone (`id`, deletion reason/time, checksum prefix if required for reconciliation) for 30 days, then purge it.
- Daily sweeps select expired rows; object-store lifecycle rules independently purge objects older than 8 days and unfinished multipart uploads older than 1 day.
- Household deletion immediately revokes sessions/devices and disables evidence access, then deletes objects and operational rows. Backups age out under a documented maximum (target 35 days), are not restored into production without replaying deletion tombstones, and are inaccessible for ordinary support.
- `deletion_jobs` expose progress without object keys. A verifier reconciles database rows, bucket inventory, and deletion tombstones. Release acceptance requires tests proving deletion from primary storage and documented backup expiry.

### Logging, support, and incident constraints

- Log request IDs, route templates, status, duration, actor role, and pseudonymous rotating household hash only.
- Never log authorization headers, Apple tokens, refresh tokens, invitation secrets, presigned URLs, APNs tokens, child names, chore titles/notes, raw request bodies, media hashes, or object keys.
- Support has no default evidence access. Any future exceptional-access path requires guardian consent, recent staff authentication, time-bound elevation, reason, and immutable audit.
- Evidence is never used for advertising, model training, biometric analysis, or automated chore judgment.
- Add rate limits per IP, session, household, and sensitive action; enrollment, invitation redemption, evidence viewing, and auth exchange receive stricter limits.

## 9. Transactional synchronization and notifications

Every successful mutation increments `households.sync_version` and writes a typed change row/outbox event in the same PostgreSQL transaction. Change payloads contain safe resource snapshots or tombstones. A child only receives changes for itself; guardians receive household-scoped changes.

The client algorithm is:

1. Apply an optimistic local mutation with a durable command ID.
2. Send it with the same `Idempotency-Key` until a definitive response arrives.
3. Pull `changes` from its durable cursor on foreground, push, and periodic refresh.
4. Apply changes in cursor order and atomically persist the new cursor.
5. Reconcile local shields from the signed policy, never directly from a push payload.

The outbox worker coalesces redundant APNs refresh events per device/version, retries transient errors with exponential backoff and jitter, and permanently disables invalid push tokens. Push failure never rolls back an approved decision; foreground/manual sync retrieves it.

## 10. Repository layout and migration discipline

```text
backend/
  package.json
  package-lock.json
  tsconfig.json
  src/
    api/
    auth/
    domain/
    evidence/
    persistence/
    policy/
    worker/
  migrations/
    0001_initial.sql
  test/
    unit/
    integration/
    contract/
  openapi/
    getemdone-v1.yaml
```

- Commit `package-lock.json`; CI uses `npm ci`.
- Pin the Node major in `.nvmrc`, `package.json#engines`, container base image digest, and GitHub Actions setup.
- SQL migrations are append-only after merge. CI applies all migrations to an empty database and upgrades a fixture from the previous release.
- Generate Swift DTOs or validate handwritten DTOs against the checked-in OpenAPI document. The OpenAPI compatibility test fails on an unreviewed breaking change.
- Production deploy runs migrations as a separate gated job before rolling out compatible application code. Prefer expand/backfill/contract changes across releases.

## 11. Test plan

### Unit tests (every pull request)

- Role/ownership authorization matrix for every command and query.
- Occurrence state transitions, old-submission rejection, and two-guardian races.
- ISO weekday mapping, household-local dates, DST spring/fall boundaries, timezone changes, and look-ahead materialization.
- Idempotency replay, mismatched request hashes, concurrent duplicate commands, and expiry.
- Retention deadline calculation for all policy options.
- Evidence type, size, checksum, ownership, and submission-version validation.
- JWT/session expiry, refresh rotation, reuse detection, invitation expiry/single use.
- Policy/grant signature, audience, expiry, version monotonicity, nonce redemption, and key rotation.
- Log redaction tests using malicious names, notes, tokens, and presigned URLs.

### PostgreSQL integration tests (every pull request)

- Migrate a blank database and verify constraints/indexes.
- Repository queries cannot cross household or child boundaries.
- Approval transaction atomically writes decision, grant, audit, sync change, and outbox event.
- Rollback at each injected failure leaves no partial approval.
- Concurrent materialization creates one occurrence.
- Concurrent idempotent commands return one canonical response.
- Outbox leasing/retry is safe across two workers.
- Session/invitation hashes and encrypted token columns never store plaintext fixtures.

### Object-store contract tests (every pull request or nightly if runtime is high)

- Upload URL cannot read, list, overwrite another key, exceed size, or outlive expiry.
- Download URL reads only one authorized object and expires in 60 seconds.
- Incomplete, replaced, expired, guardian-deleted, and household-deleted evidence becomes inaccessible immediately and is physically removed.
- Length/checksum/media mismatch never becomes reviewable.
- Lifecycle configuration matches the seven-day product maximum plus cleanup margin.

### HTTP/API tests (every pull request)

- OpenAPI request/response conformance and stable problem codes.
- Missing/stale `If-Match`, missing/reused idempotency key, payload limits, invalid cursors, and pagination.
- Child cannot enumerate siblings, approve itself, request another child's URL, or change retention.
- Guardian from household A cannot access household B even with valid resource IDs.
- Revoked device/session loses access immediately.
- No sensitive values appear in captured structured logs or APNs payloads.

### iOS contract and end-to-end tests

- Decode every server fixture into Swift DTOs and round-trip command fixtures.
- Offline completion queues once, retries with the same key, and converges after another device changes state.
- Parent approval reaches child through push refresh and through foreground polling when push is dropped.
- Evidence upload interruption resumes/restarts without duplicate review items.
- Evidence replacement invalidates the guardian's previously opened review session.
- Account/device revocation and expired sync cursor force safe rebootstrap.

### Security/reliability gates before family pilot

- Dependency audit, secret scanning, static analysis, and container vulnerability scan.
- Automated authorization test coverage for every route.
- Restore drill proving deletion tombstones are replayed before a backup can serve traffic.
- Failure injection for database restart, object-store timeout, APNs failure, worker crash after external side effect, and clock skew.
- Load test the target approval SLO: p95 API response below 500 ms and child policy availability below 10 seconds under expected pilot load.
- Independent threat-model review covering child bypass, guardian account takeover, cross-household access, media leakage, and deletion guarantees.

## 12. GitHub Actions and delivery

Add a separate `Backend CI` workflow on pull requests and `main`:

1. Use a pinned Node LTS and `npm ci`.
2. Run formatting check, ESLint, `tsc --noEmit`, and unit tests.
3. Start PostgreSQL as a GitHub Actions service; apply migrations and run integration/API tests.
4. Run object-store contract tests against a pinned emulator/container.
5. Validate OpenAPI and run Swift fixture decoding in the existing iOS job.
6. Build the production container with a pinned base digest and scan it.
7. Upload JUnit/coverage artifacts; require both `Backend CI` and `Build and unit test` before merge.

Deployment should initially be continuous to a data-isolated staging environment after `main` passes. Production remains manually approved and uses workload identity/OIDC rather than long-lived cloud keys in GitHub. A deployment records Git SHA, migration version, image digest, and operator. Rollback deploys the prior compatible image; migrations follow expand/contract rules and are not destructively rolled back.

Do not enable production evidence uploads until bucket public-access tests, KMS policies, retention/deletion workers, deletion verification, privacy disclosures, and guardian-consent flows all pass.

## 13. Implementation tranches and acceptance gates

### Backend A — foundation and contracts

- Scaffold TypeScript/Fastify, PostgreSQL, migrations, OpenAPI, health endpoints, request IDs, safe logging, and Backend CI.
- Implement repositories and authorization scope primitives.
- Gate: clean migration, cross-household isolation tests, lint/type/unit/integration CI green.

### Backend B — identity and household enrollment

- Apple exchange adapter (fake in tests), rotating sessions, households, invitations, roles, and device enrollment/revocation.
- Gate: complete authorization matrix, replay/rate-limit tests, no plaintext credentials, recent-auth enforcement.

### Backend C — routines and local-first sync

- Templates, occurrence materialization, bootstrap/change cursor, optimistic concurrency, idempotency, audit, and transactional outbox.
- Split iOS template/occurrence models and add durable command queue.
- Gate: DST/timezone/concurrency tests and two-device convergence with dropped/reordered delivery.

### Backend D — submissions, review, and signed policy

- Check-in/timer submission, guardian decisions, access grants, signed device policy, APNs refresh worker, and enforcement reports.
- Gate: atomic approval tests, dropped-push fallback, grant/audience/replay tests, child self-approval denial.

### Backend E — private photo evidence

- Direct upload, validation/re-encoding worker, view sessions, replacement, retention controls, deletion jobs, household deletion, and export metadata.
- Gate: object access isolation, physical deletion verification, log-redaction suite, restore/deletion drill, and privacy/security review.

Family TestFlight should begin only after Backend D is stable with non-media evidence. Photo evidence can then be enabled behind a server-side household feature flag after Backend E passes its privacy gates. This keeps the highest-sensitivity data out of early infrastructure testing.

## 14. Explicit deferred decisions

- Hosting vendor, region, and managed PostgreSQL/object-store products.
- Whether applicable child-privacy law requires verified parental consent beyond household invitation and Apple family authorization; obtain counsel before public beta.
- End-to-end evidence encryption and multi-guardian recovery design.
- Audio/video evidence.
- Router credential storage and adapter execution.
- Admin/support console.
- Long-term analytics warehouse.

These deferrals do not block implementation through household sync. They do block collecting real child evidence publicly if the privacy, consent, region, and deletion commitments are unresolved.
