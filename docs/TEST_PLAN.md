# GetEmDone Test Plan

## Purpose

Prove that GetEmDone reliably restricts only the intended child devices and distractions, restores access when authorized, preserves essential access, and fails safely without disrupting a parent's work or the household network.

## Product surfaces in scope

- Parent iOS app: household setup, recurring chores, evidence review, approval, overrides, device and policy management.
- Child iOS/iPadOS app: today's chores, evidence capture, status, restriction messaging, recovery flow.
- Screen Time extensions: schedule monitoring, app/web shielding, policy application, and shield actions/configuration.
- Backend and push: household membership, chore state, evidence, signed approvals, audit events, notification delivery.
- Internet filtering: child-specific safety and chore-time policies.
- Optional Apple TV control through explicitly supported router integrations.

Out of scope until separately approved: arbitrary-router support, cellular shutdown, tvOS app/profile control, proprietary network hardware, and claims of bypass-proof enforcement.

## Release invariants

These are blocking requirements for every production build:

1. A parent device is never restricted merely because it belongs to the household.
2. Phone, emergency communication, and configured essential apps remain available.
3. A policy cannot affect an unassigned device.
4. Parent approval or a valid recovery mechanism removes chore-time restrictions.
5. Always-on safety filtering and temporary chore-time filtering remain independently configurable.
6. Loss of backend, push, DNS, or router connectivity cannot broaden a restriction to other devices.
7. Evidence is private to the household, access-controlled, encrypted in transit and at rest, and expires according to policy.
8. Unsupported routers are rejected clearly; the app never attempts speculative network changes.

## Test environments

Maintain a device matrix covering:

- Current iOS/iPadOS major release, previous major release, and latest beta during its beta cycle.
- Parent/child Family Sharing accounts and a non-child test account.
- Fresh install, upgrade, reinstall, revoked authorization, and restored-device scenarios.
- Wi-Fi, cellular, offline, poor connectivity, delayed push, time-zone change, daylight-saving transition, and manual clock manipulation.
- At least one physical parent iPhone, one physical child iPhone, and one physical iPad. Simulator tests supplement but do not replace physical-device tests for Screen Time extensions.
- Each certified router firmware version plus a real Apple TV on the current and previous supported tvOS versions.

Use synthetic households and non-sensitive evidence in all development and CI environments.

## Automated test suites

### Unit tests

Test deterministic business logic without Apple frameworks or network dependencies:

- Recurrence calculation: weekdays, skipped days, holidays, time zones, DST, midnight boundaries, leap day.
- Chore state transitions: scheduled, started, submitted, approved, rejected, waived, expired, reset.
- Unlock rules: all-required versus progressive access; partial approval; temporary parent override; expiration.
- Policy composition: always-allowed apps, safety policy, chore-time policy, child/device assignment, precedence.
- Idempotency: duplicate submission, approval, push, webhook, router command, and retry.
- Signed offline approval/recovery codes: validation, household/device binding, expiry, replay prevention, clock skew.
- Evidence retention/deletion calculation and authorization checks.
- Domain/category rule matching, allow-list precedence, malformed rules, and shared-domain exceptions.
- Router capability negotiation and explicit unsupported-state handling.
- Audit event generation without sensitive payload leakage.

Required result: all unit suites pass; changed core policy code has branch tests for allowed, blocked, expired, unauthorized, and indeterminate states.

### API and integration tests

- Parent and child can access only their own household resources.
- A child cannot self-approve, change the schedule, assign devices, or issue router commands.
- Removed household members lose access immediately; tokens and cached approvals are invalidated as designed.
- Concurrent parent decisions converge deterministically.
- Evidence upload handles cancellation, retry, duplicate requests, oversized files, invalid media, and interrupted connections.
- Approval persists before notifications or device commands are sent; retries do not relock an approved day.
- Push loss/delay is recoverable through foreground refresh and signed offline approval.
- Backend outage, partial outage, rate limiting, and stale cache produce an explicit state and safe recovery.
- Router credentials/tokens are encrypted, scoped, refreshable, and revocable; secrets never appear in logs.

### UI and accessibility tests

- Golden path: create household, authorize controls, add child, select apps, create chores, submit evidence, approve, unlock.
- Parent can preview exactly which child, devices, apps, sites, and Apple TVs will be affected before activation.
- Prominent actions work: Unlock for 30 minutes, Unlock for today, Skip today, Lock again, emergency/recovery unlock.
- Ambiguous device names require confirmation and a reversible connection test.
- Unsupported, offline, stale, pending, approved, rejected, and partially unlocked states are distinguishable in words—not color alone.
- Destructive and high-impact actions require confirmation and state their scope.
- Dynamic Type, VoiceOver labels/order, Reduce Motion, contrast, keyboard navigation where applicable, localization expansion, and landscape/iPad layouts.
- Permission denial and revoked-permission flows explain how to recover without dead ends.
- Screenshot tests cover core states but do not replace behavioral assertions.

### Screen Time extension tests

Run on physical devices with production-like Family Controls authorization:

- Morning schedule applies while the apps are closed and after device restart.
- Selected application/category/web-domain tokens are shielded; unselected and always-allowed targets remain usable.
- Shield configuration names the reason and provides an approved path back to the chore experience.
- Approval removes shields promptly through push, foreground refresh, and offline-code paths.
- Tomorrow's restrictions reset locally without requiring a server wake-up.
- Extension memory/time limits are respected; malformed or unavailable shared state cannot crash or broaden the shield set.
- App update, extension update, OS update, authorization revocation, Family Sharing changes, and uninstall/reinstall have defined outcomes.
- Multiple children/devices do not share opaque selection tokens or policy state accidentally.

### Internet-filter tests

- Safety and chore-time rule layers can be enabled, disabled, and tested independently.
- Allow-listed school, authentication, health, communication, and parent-selected services remain reachable.
- Category/domain changes propagate within the documented time; DNS cache behavior is measured.
- Existing sessions and streams behave as documented; the UI never claims an immediate stop if it cannot guarantee one.
- VPN, Private Relay, encrypted DNS, cellular fallback, captive portals, and work/school management profiles produce clear compatibility states.
- Filter outage/degradation follows the chosen fail-safe policy, is visible to the parent, and does not affect unassigned devices.
- False-positive regression set includes common school, work, video-call, smart-home, and sign-in services.

### Supported-router and Apple TV tests

Each router model/firmware combination must pass certification before appearing as supported:

- Authentication, token refresh/revocation, least privilege, and account unlink.
- Discovery maps stable identifiers to devices and tolerates duplicate/cryptic names.
- Parent confirms an Apple TV using a short reversible pause test.
- Pause/unpause is idempotent, survives app restarts, and does not target other household devices.
- Active stream behavior and time-to-enforcement are measured and disclosed.
- Router reboot, WAN outage, LAN outage, firmware update, changed IP/MAC behavior, Apple TV sleep/wake, Ethernet/Wi-Fi switch, and renamed device.
- Parent override restores access within the product SLO or presents a router-native recovery instruction.
- API/schema/rate-limit changes fail closed to automation but open with respect to unrelated household traffic: no broad network mutation.

Certification artifacts: model, hardware revision, firmware, region, integration/API version, date, test results, known limitations, rollback instructions, and owner. Re-certify on firmware/API changes; remotely disable a broken integration without changing household-wide DNS.

## Failure and safety scenarios

Manually exercise these before every external tranche:

| Scenario | Expected outcome |
| --- | --- |
| Parent approves while child is offline | Approval is durable; child unlocks on next sync or via a valid offline code. |
| Push is delayed or duplicated | Foreground refresh works; duplicate events are harmless. |
| Backend is unavailable at reset time | Essential access remains; cached local schedule behaves predictably; parent sees status. |
| Extension reads corrupt/missing state | It uses a narrow documented fallback, never “block everything.” |
| Router integration loses authorization | Only router automation stops; parent receives reconnection guidance. |
| Wrong Apple TV selected | Confirmation test and immediate undo prevent persistent impact. |
| Parent needs shared TV | One-tap timed override works without approving chores. |
| Child changes time zone/clock | Schedule cannot be silently defeated or extended indefinitely. |
| Household member/device is removed | Its tokens and policy assignments are revoked promptly. |
| Evidence upload fails | Chore progress is retained; retry is clear; no duplicate media. |
| Parent loses phone | Recovery uses authenticated account/device procedures, not a child-known static PIN. |

Run a “parent workday” regression: parent phone, laptop, videoconferencing, VPN, printer, smart-home devices, and streaming remain unaffected while every child policy is exercised.

## Privacy and security verification

- Complete data-flow and threat-model reviews before external testing and when adding router/filter providers.
- Collect the minimum child data; do not use evidence for advertising, profiling, or model training.
- Verify parent consent and household authorization; document COPPA/child-privacy and regional review requirements with counsel.
- Photo/audio metadata is stripped unless needed; evidence has short configurable retention and verified deletion from primary storage and backups per policy.
- Audit all reads, approvals, overrides, membership changes, and device assignments; do not log photos, domain histories, app selections, tokens, or recovery codes.
- Perform authorization/IDOR, token theft, replay, upload validation, notification privacy, local shared-container, keychain, backup, and screenshot exposure tests.
- Conduct dependency/SCA, secret scanning, static analysis, transport-security validation, and an independent penetration test before broad launch.
- App privacy labels, privacy policy, in-app disclosures, retention behavior, and actual telemetry must agree.

## Performance and reliability targets

Set final SLOs from beta measurements. Initial release gates:

- Chore and approval API success: at least 99.9% monthly, excluding declared maintenance.
- Parent approval visible to online child device: p95 under 10 seconds; recovery path offered after 30 seconds.
- Router unpause on a healthy certified integration: p95 under 15 seconds.
- Crash-free sessions: at least 99.8%; extension crash/hang regression is release-blocking.
- No confirmed cross-household data exposure or unintended parent/unassigned-device restriction.

## TestFlight tranches

1. **Internal dogfood (5–15 adults, synthetic child accounts):** checklist, schedules, app selection, shields, approval, recovery. No router integration by default.
2. **Staff family pilot (10–25 households):** real child devices with written consent, evidence retention controls, support playbook, telemetry validation.
3. **Closed iOS beta (50–100 households):** varied devices/OS versions; measure setup completion, unlock latency, false blocks, support contacts, and week-four retention.
4. **Router certification beta (10–20 households per router/firmware):** Apple TV only, explicit compatibility agreement, instant kill switch, direct support channel.
5. **Expanded beta (250–500 households):** only after entitlement confirmation, privacy/security review, SLO attainment, and zero unresolved severity-1 safety defects.

Every tranche has an owner, start/end date, entry gates, feedback channel, incident contact, remote feature flags, rollback/kill-switch drill, and exit report. Do not expose photo evidence or network controls until the preceding tranche passes.

## Defect severity and exit criteria

- **S0/Critical:** cross-household exposure, unintended broad network outage, essential-access block, irrecoverable lock. Stop rollout immediately.
- **S1/High:** parent cannot unlock, wrong child/device affected, evidence privacy failure, systematic bypass. Freeze promotion.
- **S2/Medium:** recoverable feature failure or material UX confusion. Must have accepted mitigation and owner.
- **S3/Low:** cosmetic/minor inconvenience. May ship if triaged.

A tranche exits only when all planned tests pass, no open S0/S1 defects remain, S2 risk is explicitly accepted, instrumentation is verified, recovery has been rehearsed, and observed metrics meet its stated gates.
