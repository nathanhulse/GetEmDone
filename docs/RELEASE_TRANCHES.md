# GetEmDone Release Tranches

Tranches are gated by evidence, not calendar promises. Each tranche should be releasable behind feature flags and should not make later router work a dependency of reliable phone enforcement.

## Tranche 0 — Feasibility and entitlement

**Outcome:** Prove the critical Apple enforcement loop and validate distribution eligibility.

**Build:**

- Minimal parent/child authorization spike using FamilyControls.
- Opaque app/category selection, ManagedSettings shield, local DeviceActivity schedule, and removal.
- Test matrix for supported iOS/iPadOS versions, reboot, app termination, date boundary, and authorization revocation.
- Family Controls entitlement request and App Review narrative.
- Threat model, child-data inventory, consent/retention outline, and architecture decision records.
- Router API discovery only; no customer promise.

**Exit gates:**

- Entitlement path is credible and documented.
- Lock/unlock/reset works repeatably on physical devices.
- Essential/recovery design review passes.
- No architecture requires identifying selected apps outside Apple's protected representation.

## Tranche 1 — Internal phone-only vertical slice

**Outcome:** A team household can complete a full daily cycle.

**Build:**

- Parent and child roles, household linking, one child/device.
- Recurring checklist, child checkoff, submission, parent approval/rejection.
- Local reset, signed day grant, push plus foreground refresh.
- Parent temporary override and authenticated Unlock All.
- Basic activity history and enforcement-health state.
- Instrumentation excluding child evidence and selected-app identities.

**Exit gates:**

- End-to-end cycle passes on supported device matrix.
- Approval operations are idempotent under retries and reordered messages.
- UI never reports unlocked without local enforcement confirmation.
- Internal recovery drill succeeds from offline, revoked-auth, and delayed-push states.

## Tranche 2 — Private family alpha

**Outcome:** Validate daily usefulness and failure recovery in real households.

**Build:**

- Multiple children and optional co-guardian.
- Photo, audio, and practice-timer evidence with encrypted upload and automatic retention.
- Offline chore entry and locally verifiable parent unlock code.
- Notifications, quiet controls, duplicate suppression, and accessible core flows.
- Time-zone/travel handling, schedule edit boundaries, and privacy deletion/export.
- In-app diagnostics and support bundle with automatic redaction.

**Exit gates:**

- At least 20 households complete two weeks of testing.
- 80% complete initial setup without live intervention.
- 95% of healthy online approvals apply within 10 seconds in controlled testing.
- Recovery-required product failures affect fewer than 5% of chore cycles.
- No unresolved critical privacy, security, accessibility, or unintended-device restriction defects.

## Tranche 3 — Public iOS beta

**Outcome:** Harden the phone-first product at broader scale.

**Build:**

- Polished onboarding, safety preview, shield messaging, and subscription/account lifecycle if required.
- Reliability dashboards for authorization, local schedules, push/grant application, crashes, and recovery.
- Data-subject/guardian flows, operational runbooks, incident handling, and support tooling with strict roles.
- Compatibility gates for new OS releases and remote feature flags/kill switches.
- Store listing that accurately states scope and limitations.

**Exit gates:**

- Crash-free session and latency targets sustained for four weeks.
- Zero known paths that unintentionally target an unenrolled device.
- Deletion, account recovery, consent, and incident-response exercises pass.
- App Review approval obtained with Family Controls functionality intact.

## Tranche 4 — Apple TV adapter lab

**Outcome:** Prove optional, safe Apple TV pause with one supported router ecosystem.

**Selection criteria:** Documented and commercially permitted API; stable authentication; per-device pause/resume; confirmation or reliable readback; credential revocation; meaningful installed base; no whole-network mutation required.

**Build:**

- Adapter capability contract, secret storage, token refresh/revocation, command idempotency, and status readback.
- Guided authorization, device discovery, mandatory reversible pause test, assignment, and disconnect.
- TV-only overrides and independent phone/TV status.
- Adapter-specific integration simulator, fault injection, and feature kill switch.

**Exit gates:**

- Legal/API access is explicit; no reliance on reverse-engineered private endpoints.
- Correct-device pause/resume and readback meet a published success target in diverse test networks.
- Token expiry, router offline, device rename/IP change, app termination, and command retry fail safely.
- Test proves no DNS/DHCP/firewall-wide change and no collateral household outage.

## Tranche 5 — Limited Apple TV beta

**Outcome:** Offer Apple TV control to compatible volunteer households without weakening the core product.

**Build:**

- Compatibility checker and waitlist for unsupported routers.
- Per-adapter diagnostics, status-page communication, kill switch, and guided manual recovery.
- Parent Is Watching time-boxed override.
- Clear shared-device limitation and phone-only fallback.

**Exit gates:**

- At least 50 compatible households complete four weeks.
- Pause/resume reliability meets adapter-specific launch threshold.
- No confirmed whole-network outages caused by the adapter.
- Support burden and authorization churn are commercially sustainable.

## Tranche 6 — General iOS launch and selective adapter expansion

**Outcome:** Ship a dependable chore-enforcement product; expand routers one verified adapter at a time.

**Launch scope:**

- iPhone/iPad chore scheduling, app/category shielding, evidence, parent decisions, overrides, offline recovery, privacy controls, and transparent health.
- Apple TV pause only for adapters that independently pass Tranches 4–5; all others remain unavailable or waitlisted.

**Operational gates:**

- On-call ownership, rollback/kill-switch procedures, support playbooks, privacy/security response, and OS-release qualification are active.
- Public compatibility and limitation documentation matches runtime behavior.
- Metrics segment phone enforcement from each router adapter so one integration cannot mask another's reliability.

## Deferred candidates

These require a new PRD and discovery tranche:

- Android enforcement.
- Service-specific Apple TV/streaming DNS filtering.
- Additional smart TVs, consoles, or arbitrary routers.
- Automated evidence classification.
- School/teacher workflows, rewards marketplaces, or behavioral scoring.
- Proprietary network hardware.

## Cross-tranche test suites

- **Enforcement:** schedule boundary, reboot, termination, OS update, authorization change, selected-app edit, overlapping override.
- **Distributed state:** offline devices, delayed/dropped/duplicate push, reordered decisions, clock skew, stale/replayed grants.
- **Safety:** essential availability, wrong account/device, parent recovery, grant expiry, deletion, co-guardian removal.
- **Evidence:** permission denial, large/invalid media, interrupted upload, replacement, retention deletion, unauthorized access.
- **Router:** wrong-device prevention, pause-test cleanup, IP/hostname change, token expiry, router reboot, absent Apple TV, partial outage.
- **UX/accessibility:** first-run comprehension, status truthfulness, VoiceOver, Dynamic Type, reduced motion, localization, DST/travel.
- **Security/privacy:** household isolation, role escalation, secret leakage, signed-grant tampering/replay, audit integrity, support access.

## Build handoff convention

Each implementation tranche begins with:

- Accepted scope and explicit non-goals.
- User flows and screen states linked to `UX_REQUIREMENTS.md`.
- API/state contracts and signed-grant threat model.
- Acceptance tests written before feature-complete review.
- Feature flags, telemetry schema, recovery path, rollback owner, and privacy impact noted in the tranche issue.

Each tranche ends with a demo on physical devices, automated-test results, accessibility evidence, unresolved-risk register, and go/no-go decision against its exit gates.
