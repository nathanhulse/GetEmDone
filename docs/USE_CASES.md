# GetEmDone Use Cases

## Actors

- **Parent:** Authenticated guardian who configures policy and makes approval decisions.
- **Child:** Household member assigned chores and an authorized child device.
- **Child device:** iPhone or iPad enforcing Family Controls policy.
- **Router adapter:** Optional connector capable of pausing a specifically assigned Apple TV.
- **Service:** Synchronizes household state, notifications, evidence, audit events, and signed grants.

## UC-01 — Set up phone enforcement

**Preconditions:** Parent and child use supported Apple accounts/devices; required authorization is available.

**Flow:**

1. Parent creates a household and chooses Add Child.
2. Product explains what can and cannot be restricted.
3. Parent and child complete Apple's authorization flow.
4. Parent uses Apple's picker to select distracting apps/categories.
5. Parent reviews always-available essentials, reset time, and affected device.
6. Product performs a reversible shield test.
7. Parent confirms and activates.

**Acceptance:** The named child device is the only affected device; authorization and test results are visible; cancellation restores the prior state.

**Alternates:** Authorization denied or entitlement unavailable stops activation and gives corrective guidance without creating a misleading policy.

## UC-02 — Create recurring chores

**Flow:** Parent adds chores, chooses days, order, due time, and evidence/approval requirements, previews the child's day, and saves.

**Acceptance:** The next occurrence is unambiguous in the household time zone; edits are versioned; archived chores do not reappear.

## UC-03 — Start a new chore day

**Preconditions:** Active schedule and authorization exist.

**Flow:** A local schedule wakes at the configured boundary, invalidates yesterday's normal grant, applies selected shields, and presents today's list.

**Acceptance:** Reset does not require a server push; approved essentials remain accessible; the parent sees the current enforcement status after synchronization.

**Alternates:** If authorization is revoked or policy application fails, status becomes Needs Attention and the app never claims enforcement succeeded.

## UC-04 — Complete chores and request review

**Flow:** Child opens Today, completes each required method, reviews the submission, and taps Request Approval.

**Acceptance:** Incomplete requirements are identified before submission; evidence upload progress is visible; retries do not create duplicate requests; offline work is queued.

## UC-05 — Review evidence and approve

**Flow:** Parent opens the notification, reviews each item/evidence, approves eligible chores, then approves the day.

**Acceptance:** A signed, day-scoped, child-scoped grant is issued; the child sees approval; online shields are removed within the published latency target; audit history records the decision.

## UC-06 — Reject or request a redo

**Flow:** Parent selects an item, chooses Needs Redo, optionally adds a brief reason, and submits.

**Acceptance:** Only the rejected item reopens; other accepted work remains credited according to policy; child receives a respectful, actionable status; entertainment remains restricted.

## UC-07 — Approve while the child device is offline

**Flow:** Parent generates an offline unlock code with a visible scope and expiry. Child enters it on the managed device. The device verifies the signed code locally and applies the grant.

**Acceptance:** No network is required for verification; expired, modified, wrong-child, or replayed codes fail clearly; the result syncs when connectivity returns.

## UC-08 — Parent makes a temporary exception

**Flow:** Parent chooses a child/target and selects Unlock 30 Minutes, Until Time, For Today, or Skip Today; authenticates; confirms the preview.

**Acceptance:** Only selected targets change; expiry is visible on both devices; the normal schedule resumes automatically; override is audited.

## UC-09 — Parent immediately unlocks everything managed

**Flow:** From recovery, parent selects Unlock All Managed Targets, authenticates, confirms listed child devices/Apple TVs, and receives per-target results.

**Acceptance:** Child shields are removed locally or via signed grant; each router result is independently reported; failure of one target does not block recovery of another.

## UC-10 — Connect and assign an Apple TV

**Preconditions:** The household has a supported router/adapter and the parent can authorize it.

**Flow:** Parent selects router model, authorizes minimum access, reviews discovered devices, selects a candidate Apple TV, runs a short pause test, confirms the observed device, and assigns it to chore policy.

**Acceptance:** No DNS/DHCP or whole-network settings change; an unconfirmed device is never assigned; credentials are protected; disconnecting removes GetEmDone control without breaking connectivity.

## UC-11 — Pause and restore an assigned Apple TV

**Flow:** Chore mode sends a pause command for the assigned Apple TV. Approval or TV-specific override sends resume. UI waits for adapter confirmation.

**Acceptance:** The UI says Paused only after confirmation and otherwise says Pending/Failed; phone and TV grants may be independent; parent can retry or manually open router instructions.

**Alternates:** If the router is offline or its token expires, phone enforcement continues and router status becomes Needs Attention. General household internet is untouched.

## UC-12 — Parent watches a shared Apple TV

**Flow:** Parent chooses Parent Is Watching and grants TV-only access for a selected duration.

**Acceptance:** The Apple TV resumes without unlocking the child's phone; the end time is visible; it pauses again only when the grant expires and chore policy still requires it.

## UC-13 — Evidence upload fails

**Flow:** Upload stalls or loses connectivity. Child sees Saved on This Device, can retry/cancel/replace, and can continue other chores.

**Acceptance:** No data loss or duplicate media occurs; parent cannot approve missing required evidence as though it were present; queued media follows retention and encryption rules.

## UC-14 — Authorization is revoked or the app is removed

**Flow:** Product detects loss of authorization on foreground/system callback and updates household health.

**Acceptance:** Parent is notified once with repair steps; service does not claim the child is restricted; reauthorization does not silently change selected targets.

## UC-15 — Travel or time-zone change

**Flow:** Product detects a different local time zone and asks the parent whether schedules follow the household zone or travel zone when the difference affects the next reset.

**Acceptance:** No double reset or unexpectedly extended grant; the chosen basis is shown in schedule settings and audit history.

## UC-16 — Delete evidence or household data

**Flow:** Parent deletes an evidence item or household/account and authenticates. Product explains scope and any legally required delay, then processes deletion.

**Acceptance:** Active URLs are revoked, data is removed from user-facing systems promptly and backups per policy, adapter tokens are revoked, and deletion completion is recorded without retaining the deleted content.

## Abuse and misuse cases

### Wrong device assignment

The parent selects a work laptop instead of an Apple TV. Mitigation: device-type hints are not trusted; a reversible test and explicit physical confirmation are mandatory.

### Child attempts bypass

The child changes network, uses cellular/VPN, or deletes the app. Phone enforcement relies on Family Controls rather than home DNS; bypass detection is reported honestly, not promised as absolute. Apple TV enforcement applies only on the supported home network.

### Unauthorized adult accesses evidence

Mitigation: household isolation, recent parent authentication, private short-lived media URLs, access audit, minimal support access, and configurable auto-deletion.

### Stale approval unlocks the wrong day

Mitigation: every grant is signed and bound to household, child, policy version, local-day identifier, targets, issuance, and expiry; replay is rejected.

### Parent account is unavailable

Mitigation: configured co-guardian support, offline recovery code path, and a fail-safe expiry. Support cannot remotely inspect evidence or bypass guardian authentication casually.

