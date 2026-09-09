# GetEmDone UX Requirements

## Experience principles

1. **Chores first, networking invisible.** Use “pause the Family Room Apple TV,” never DNS, MAC filtering, WAN policy, or packet terminology in the primary flow.
2. **Name the target and consequence.** Every confirmation states whose device, which entertainment, when, and how to recover.
3. **Firm without shame.** Language describes state and next action; it does not score, taunt, compare siblings, or imply moral failure.
4. **Safe by construction.** Essential apps, parent devices, and unconfirmed network devices remain outside scope.
5. **Truthful status.** Distinguish requested, applying, active, failed, and unknown. Never display a green check based merely on a command being sent.
6. **Fast exceptions.** A parent can grant a bounded exception more quickly than editing the underlying schedule.
7. **Progress over surveillance.** Collect the least evidence possible and keep the parent as decision-maker.

## Information architecture

### Parent app

- **Today:** Children, progress, pending reviews, active unlocks, and enforcement health.
- **Review:** Submitted chores and evidence, approve/redo actions.
- **Schedule:** Chores, recurrence, reset time, evidence rules.
- **Access:** Selected app/category policy, always-available review, Apple TV assignments.
- **Activity:** Human-readable decisions, overrides, schedule changes, and failures.
- **Settings:** Guardians, privacy/retention, notifications, router connections, recovery, support.

### Child app

- **Today:** Remaining chores, progress, required evidence, request approval.
- **Status:** What is unavailable, why, approval/override expiry, refresh.
- **History:** Recent personal completion states without comparative scoring.
- **Help:** Ask parent, offline code, authorization/recovery guidance.

## Onboarding requirements

- Begin with a three-part promise: complete chores, parent approves, selected entertainment opens.
- Present phone enforcement and optional TV control as separate setup modules.
- Explain before Apple's authorization prompt why permission is requested and what GetEmDone cannot do.
- Use Apple's opaque selection UI; do not list or transmit selected app identities in custom analytics.
- Include an “Always available” safety review with examples: Phone, Messages, Maps, school, health, authenticators, and GetEmDone.
- Show a final activation preview containing child, device, apps/categories, schedule, approval rule, and recovery method.
- Run a reversible test before activation and restore automatically if abandoned.
- Permit Skip for Now for evidence, notifications, co-guardian, and Apple TV setup.
- Phone-only setup target: no more than seven decision screens and under ten minutes median in usability testing.

## Parent Today screen

- Each child card shows: chore progress, review state, phone state, optional TV state, and next scheduled change.
- Primary action adapts to context: Review, Unlock Temporarily, Resolve Issue, or View Today.
- Pending reviews sort ahead of completed children; errors never hide inside settings.
- Shared Apple TV status appears independently from the child's phone state.
- “Unlock all managed targets” is visible from an overflow/recovery action, requires authentication and confirmation, then returns per-target results.

## Child Today screen

- Show a calm header such as “3 things before entertainment.”
- Each chore clearly displays completion method and any required minimum duration.
- Checkoff must be one tap; photo/audio/timer flows must return directly to Today.
- Progress is persistent and available offline.
- Request Approval remains disabled with an explanation until requirements are met.
- After submission, show whether evidence is uploading, waiting for parent, needs redo, or is approved.
- A rejection shows the parent's reason, preserves accepted work, and emphasizes the next action.

## Evidence UX

- Ask for camera/microphone/photo access at the moment of use, with a plain-language purpose.
- Show captured evidence before upload with Retake and Use controls.
- Reveal retention duration and who can view it near first use and in settings.
- Do not automatically analyze faces, rooms, voices, or behavior in MVP.
- Never display evidence in push-notification previews by default.
- Use thumbnails cautiously; require recent parent authentication before full-size viewing after an inactivity threshold.
- Provide delete and replace actions and a clear upload/offline state.

## Approval UX

- Review presents one child and one chore day at a time.
- Each item displays requirement, submitted evidence, completion time, Approve, and Needs Redo.
- “Approve day” is available only when policy conditions are satisfied or the parent explicitly overrides them.
- On approval, immediately show separate application states:
  - Child phone: Applying / Unlocked / Needs attention
  - Family Room Apple TV: Resuming / Available / Needs attention
- Do not trap the parent on a spinner. Changes continue in the background and results notify once.

## Shield and restricted-state UX

- The shield communicates: “Entertainment is waiting for today's chores,” the number remaining or review status, and an action to open GetEmDone.
- Avoid punitive imagery, countdown anxiety, or public-facing messages.
- When approved but sync is delayed, child Status offers Refresh and Enter Parent Code.
- Do not promise a specific unlock time unless a valid grant already contains it.
- Essential and system surfaces must remain usable according to platform behavior.

## Overrides and recovery

- Quick choices: 30 Minutes, Until…, Today, Skip Chores Today, Lock Again.
- Scope choices must be explicit: Phone entertainment, Family Room Apple TV, or both.
- Confirmation summarizes targets and automatic expiry.
- Parent authentication is required; biometric authentication is preferred with secure fallback.
- Offline unlock code UX displays child, targets, and expiry before generation; entry supports accessibility and avoids ambiguous characters.
- Errors offer an immediate safe action, diagnostic summary, and support path without exposing secrets.
- A visible recovery route must exist on both the parent Today screen and child waiting/status screen.

## Apple TV setup UX

- Only show router models/adapters currently supported for that release and region.
- Explain: “GetEmDone pauses this Apple TV's internet. It cannot tell who is holding the remote.”
- Authorization is hosted or system-provided where possible; never ask users to paste tokens in normal setup.
- Device discovery lists friendly name, device type confidence, connection, and last seen—never auto-select.
- Pause test flow:
  1. Ask the parent to start playback on the intended Apple TV.
  2. Pause for a short bounded interval.
  3. Ask whether playback stopped on the correct TV.
  4. Automatically resume regardless of answer or flow abandonment.
- If the test fails, do not permit assignment. Offer retry, adapter-specific help, or phone-only continuation.
- TV controls never ask the user to change Wi-Fi password, DNS, DHCP, firewall, or router firmware manually.

## Status language

| System state | Parent label | Child label |
|---|---|---|
| Restrictions confirmed | Entertainment paused | Chores first |
| Submission awaiting decision | Review requested | Waiting for parent |
| Grant applying | Unlocking… | Approval received—unlocking… |
| Grant confirmed | Available until [time] | You're all set until [time] |
| Router command pending | Pausing/Resuming TV… | TV update in progress |
| Result unknown | Can't confirm TV status | Ask a parent to check the TV |
| Authorization lost | Setup needs attention | Ask a parent to reconnect |

Avoid “blocked successfully” when state is merely requested, “proof failed,” “bad child,” “earned screen time” as a universal value judgment, or technical router errors without translation.

## Accessibility requirements

- Meet WCAG 2.2 AA where applicable and Apple accessibility guidance.
- Support VoiceOver labels, logical focus order, rotor headings, and accessible media controls.
- Support Dynamic Type through accessibility sizes without hiding primary actions.
- Never encode pending/approved/failed only by color or animation.
- Minimum 44x44-point touch targets; captions/transcripts for audio evidence where user-provided and appropriate.
- Respect Reduce Motion, Increase Contrast, Differentiate Without Color, and system text settings.
- Timers survive navigation and do not demand continuous visual attention.

## UX acceptance tests

- A first-time parent can enroll one child, choose apps, create three chores, and activate without assistance.
- A child can complete three mixed-method chores and request approval without instruction after initial walkthrough.
- A parent can identify and recover from delayed approval in under one minute.
- A parent can unlock only a shared Apple TV without unlocking the child's phone.
- No participant mistakes a pending router command for confirmed enforcement in moderated tests.
- Users can explain which devices will be affected before activation.
- VoiceOver users can complete onboarding, evidence submission, approval, and emergency unlock.

