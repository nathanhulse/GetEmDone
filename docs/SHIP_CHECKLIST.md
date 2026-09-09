# GetEmDone Ship Checklist

This checklist is a release gate, not a roadmap. Every item must have an owner and evidence link in the release record. Any unchecked blocking item stops shipment.

## Scope and claims

- [ ] Release scope and supported OS/device/router matrix are frozen.
- [ ] Marketing says “selected apps and websites” and “designated Apple TVs on compatible networks,” not full device shutdown, universal router support, or bypass-proof control.
- [ ] Unsupported features are hidden or clearly labeled; no speculative router integration is enabled.
- [ ] Parent, child, safety-filter, chore-filter, and Apple TV override behavior matches the approved requirements.

## Apple entitlement and review gates

- [ ] Family Controls entitlement is approved for the distribution team and each required target/extension.
- [ ] Distribution provisioning profiles contain the correct entitlements; a clean archived build is inspected rather than relying on Debug behavior.
- [ ] Family Sharing authorization and child-account flows pass on physical devices using TestFlight.
- [ ] Screen Time extension targets, App Groups, keychain access groups, push/environment entitlements, and associated domains are validated in the signed archive.
- [ ] Network Extension/content-filter entitlement is approved before that functionality is offered; otherwise the feature is disabled and absent from claims.
- [ ] App Review notes include setup credentials/instructions, why parental-control capabilities are used, demo paths, and recovery/override behavior.
- [ ] No private APIs, VPN misuse, or unsupported tvOS-control claims remain.
- [ ] Entitlement denial/deferment plan is approved: ship the entitlement-independent scope or hold; never substitute an undisclosed workaround.

## Functional release gates

- [ ] Chore recurrence and local daily reset pass time-zone, DST, offline, restart, and upgrade tests.
- [ ] App/category/site selection affects only the intended child/device.
- [ ] Essential and parent-configured always-allowed access remains available.
- [ ] Submission, approval, rejection, waiver, partial unlock, and expiry are correct and idempotent.
- [ ] Online approval meets unlock SLO; delayed push recovers on foreground refresh.
- [ ] Signed offline/recovery unlock is household/device-bound, expiring, replay-resistant, and tested.
- [ ] Temporary TV/phone overrides expire correctly and can be ended early.
- [ ] Safety filtering remains independent from chore-time filtering.
- [ ] Fresh install, upgrade, logout, account removal, authorization revocation, reinstall, and restored-device paths pass.

## Parent-impact safety gates

- [ ] Parent and unassigned devices cannot inherit a child's policy.
- [ ] Policy preview lists every affected child, device, app/category, site category, and Apple TV before activation.
- [ ] “Unlock for today,” timed parent override, “Skip today,” and emergency recovery are prominent and tested.
- [ ] “Parent workday” test passes: work laptop/VPN/video calls, parent phone, printer, smart home, and parent streaming are unaffected.
- [ ] Missing/corrupt/ambiguous policy state uses the approved narrow fallback and never broad blocking.
- [ ] Backend, push, filter provider, and router outages have tested user messages and recovery steps.
- [ ] Support can remotely disable each risky integration or policy layer without releasing an app update.

## Privacy and security gates

- [ ] Security threat model and privacy data-flow diagram are current and reviewed.
- [ ] Child/privacy legal review, parental consent flow, terms, privacy policy, and age/region handling are approved.
- [ ] App Store privacy labels match actual collection, retention, sharing, diagnostics, and third-party SDK behavior.
- [ ] Evidence is encrypted in transit/at rest, metadata handling is verified, retention is short/configurable, and deletion is tested end to end.
- [ ] Evidence is excluded from advertising, profiling, and model training.
- [ ] Cross-household authorization/IDOR suite and role tests pass.
- [ ] Router credentials, push tokens, signing keys, recovery codes, and evidence URLs are absent from logs and analytics.
- [ ] Secret scan, dependency scan, static analysis, upload validation, and transport-security tests pass.
- [ ] Backend typecheck, coverage thresholds, production dependency audit, and pull-request dependency review pass.
- [ ] Every Screen Time extension builds independently and its extension point, Family Controls entitlement, and shared App Group are validated by CI.
- [ ] Independent penetration test is complete for broad public launch; critical/high findings are closed or formally accepted with mitigation.
- [ ] Incident response, breach escalation, child-safety escalation, deletion request, and account recovery runbooks have been rehearsed.

## Supported-router certification

Complete separately for every model, hardware revision, firmware range, integration/API version, and region:

- [ ] Vendor permission/API terms permit the integration and intended commercial use.
- [ ] Authentication, token refresh, revocation, unlink, least privilege, and rate limits pass.
- [ ] Apple TV discovery and stable identity pass on Wi-Fi and Ethernet, including sleep/wake and rename.
- [ ] User-confirmed reversible pause test prevents selecting the wrong device.
- [ ] Pause/unpause is idempotent; actual enforcement/restoration latency meets the published SLO.
- [ ] Router/WAN/app/backend outage, router reboot, firmware upgrade, API error, and stale-token cases pass.
- [ ] Integration never modifies household-wide DNS, DHCP, Wi-Fi credentials, or unrelated devices without an explicit separately reviewed feature.
- [ ] Known limitations, active-stream behavior, local/AirPlay behavior, and router-native recovery steps are documented in-app.
- [ ] Certification record is signed and dated; firmware/API change monitoring and re-certification owner are assigned.
- [ ] Remote kill switch is tested for this exact integration.

If any certification item fails, remove that router/firmware from the compatibility list; phone features may still ship independently.

## Quality and operations

- [ ] Unit, API/integration, UI/accessibility, extension, filtering, physical-device, and router suites pass per `TEST_PLAN.md`.
- [ ] No open S0/S1 defects; S2 exceptions have owner, mitigation, deadline, and explicit release approval.
- [ ] Crash-free, approval-latency, router-unpause, API, and false-block metrics meet the tranche gates.
- [ ] Analytics and audit events are validated without sensitive payloads; dashboards and alerts are live.
- [ ] Feature flags default safely; staged rollout, rollback, and kill-switch drills pass in production-like infrastructure.
- [ ] Database migrations are backward compatible and rollback/restoration is rehearsed.
- [ ] On-call rotation, status page, customer support scripts, escalation path, and router-specific recovery guides are ready.
- [ ] Support can distinguish app, Apple service, network/filter, router, and user-configuration failures.
- [ ] Release archive, symbols, version/build numbers, licenses/attributions, and reproducible CI evidence are retained.

## TestFlight promotion gates

- [ ] Internal dogfood exit report approved.
- [ ] Staff family pilot consent, privacy controls, support coverage, and exit report approved.
- [ ] Closed iOS beta meets setup, unlock, crash, false-block, support-load, and retention thresholds.
- [ ] Each router certification beta meets its per-model thresholds with no unintended-device incidents.
- [ ] Expanded beta begins only after production entitlements, privacy/security review, recovery drills, and zero unresolved S0/S1 defects.
- [ ] Beta feedback and diagnostics can be deleted with the household account.

## App Store submission

- [ ] Product page, screenshots, privacy nutrition labels, support URL, privacy URL, and compatibility language are accurate.
- [ ] Review account/instructions exercise parent and child flows without exposing real child data.
- [ ] Review notes explain Family Controls and any approved network-filter use, background behavior, photo evidence, and router integration.
- [ ] Subscription/purchase, restore, cancellation, family access, and account deletion meet platform rules where applicable.
- [ ] Production push, backend, evidence lifecycle, signed recovery, feature flags, and router kill switches pass a final smoke test.

## Go/no-go sign-off

- [ ] Product: scope, UX, limitations, and support burden accepted.
- [ ] Engineering: build, migrations, observability, rollback, and SLOs accepted.
- [ ] Security/privacy/legal: child data, consent, retention, vendors, and incident readiness accepted.
- [ ] QA: test evidence and defect disposition accepted.
- [ ] Support/operations: staffing, runbooks, status communication, and recovery accepted.
- [ ] Release owner records **GO**, rollout percentage, monitoring window, abort thresholds, and next checkpoint.

## Immediate stop/rollback triggers

Stop rollout, disable the affected feature, and begin incident handling for any of the following:

- Cross-household access or child evidence exposure.
- Essential communication blocked or a parent/unassigned device restricted.
- Parent approval/recovery cannot restore access within the incident threshold.
- Router command affects the wrong device or causes broader household network disruption.
- Systematic extension crash, policy corruption, or unlock failure.
- Material discrepancy between disclosed and actual child-data collection/use.

Record the incident, customer impact, containment, recovery, evidence preservation, communication decision, and re-release criteria before resuming rollout.
