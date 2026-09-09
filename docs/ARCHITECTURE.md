# GetEmDone Technical Architecture

Status: proposed architecture for the first production tranche  
Primary platform: iOS/iPadOS  
Last reviewed: 2026-09-08

## 1. Product boundary

GetEmDone is a chore workflow with enforceable, reversible limits on a child's entertainment access. The first production release should do three things well:

1. Apply and remove selected iPhone/iPad app and website shields.
2. Collect chore completion evidence and parent approval.
3. Optionally pause a designated Apple TV through a validated, supported home-network integration.

It does **not** promise to disable cellular service, identify who is holding an Apple TV remote, control individual tvOS profiles, support arbitrary routers, or defeat every VPN/network workaround. Network filtering is defense in depth; iOS app shielding is the primary child-device enforcement mechanism.

## 2. Capability truth table

| Capability | Prototype/simulator | Production path | Risk |
|---|---|---|---|
| Chore schedules, checkoffs, photos, timers | Local mock data | Local database plus backend sync/object storage | Low |
| Parent review and approval | Same-device role switch | Separate authenticated parent and child installations | Medium |
| App/site selection | Fake named catalog if entitlement is absent | `FamilyActivityPicker` and opaque Apple tokens | Entitlement and device testing required |
| Apply app/site shields | In-app simulated lock screen | `ManagedSettingsStore` on the child's device | Family Controls entitlement required |
| Morning lock schedule | App-driven simulation | `DeviceActivityMonitor` extension plus local reconciliation | Extension timing/device testing required |
| Custom shield UI/action | SwiftUI preview | Managed Settings UI and shield action extensions | Extension UX/API constraints |
| Internet category filtering | Policy preview only | Family Controls web-domain shields first; optional Network Extension later | Separate entitlement/deployment validation |
| Apple TV pause | `MockRouterAdapter` state | One certified router adapter at a time | Vendor API/commercial access is unvalidated |
| Offline unlock code | Deterministic development signer | Backend-signed, short-lived token verified on child device | Key custody/replay design required |

No UI may represent a simulated control as active enforcement. Development builds must display a persistent `Simulation` badge and enforcement status must be modeled as `simulated`, `active`, `degraded`, or `unavailable`.

## 3. System context

```text
Parent iOS app                              Child iOS app + extensions
----------------                              --------------------------
create chores  ---- HTTPS / push ---->        local schedule reconciliation
review proof   <--- HTTPS / object URL ---     capture/upload evidence
approve/unlock ---- signed policy ---->        verify, persist, remove shields
      |
      +--------- router command API -------->  Router/cloud controller
                                                   |
                                                   +--> pause Apple TV WAN access
```

The backend is the shared coordination plane, not the only source of enforcement. The child device must be able to reapply a previously downloaded schedule and verify a parent-issued unlock without a live server connection.

## 4. iOS target layout

Recommended targets:

- **GetEmDoneApp** — SwiftUI app, role-aware onboarding, chores, evidence, approval, settings, diagnostics.
- **GetEmDoneCore** — pure Swift package containing domain models, policy evaluation, signed-token verification, persistence interfaces, and API DTOs. No SwiftUI or Apple framework dependencies.
- **GetEmDoneFamilyControls** — adapter around `AuthorizationCenter`, `FamilyActivitySelection`, and `ManagedSettingsStore`.
- **DeviceActivityMonitorExtension** — locally begins scheduled restriction windows and triggers shield reconciliation.
- **ShieldConfigurationExtension** — branded but clear shield content: why access is blocked, next action, and request-access affordance.
- **ShieldActionExtension** — records a request-to-parent action where Apple permits it; it must not grant access itself.
- **NotificationServiceExtension** (optional) — presentation only; never required for enforcement.
- **NetworkFilter extensions** (deferred) — only after entitlement and App Review deployment assumptions are validated.

Apple's Family Controls authorization occurs on the device being managed. Child authorization requires approval by a parent/guardian in the same Family Sharing group. App and web-domain selections are opaque tokens; architecture and analytics must not assume the server can recover application identities. See [Family Controls](https://developer.apple.com/documentation/familycontrols), [Managed Settings](https://developer.apple.com/documentation/managedsettings), and [Device Activity](https://developer.apple.com/documentation/deviceactivity).

### App groups and shared state

The app and Screen Time extensions share the minimum necessary state in an App Group:

```text
SharedPolicySnapshot
  policyVersion
  householdIDHash
  restrictionWindow
  appleSelectionData       // opaque, encrypted/protected locally
  currentGrant
  lastSuccessfulSyncAt
  nextMandatoryReconcileAt
  enforcementMode
```

Use file protection appropriate for data unavailable before first unlock. Store device credentials and verification-key metadata in Keychain. Extensions read a small, atomically replaced snapshot rather than opening the app's full database.

### Shield reconciliation

All state changes flow through one idempotent operation:

```swift
protocol ShieldReconciler {
    func reconcile(now: Date, snapshot: PolicySnapshot) async throws -> EnforcementReport
}
```

The desired state is derived, never toggled blindly:

```text
shouldShield = withinRestrictionWindow
            && requiredChoresRemain
            && noValidGrantCoversCurrentTime
            && parentalControlsAuthorized
```

Reconcile on app launch/foreground, push receipt, Device Activity interval callbacks, policy download, approval-code redemption, authorization changes, and significant clock/day changes. A delayed push therefore affects freshness, not correctness.

## 5. Local-first state and signed unlock fallback

### Canonical policy

The server is authoritative for household membership, chore templates, evidence, parent decisions, and router commands. The child device is authoritative for the immediate application of its locally cached iOS shields.

Each child downloads a signed `PolicyEnvelope`:

```json
{
  "policyVersion": 42,
  "householdID": "hh_...",
  "childDeviceID": "dev_...",
  "effectiveDay": "2026-09-08",
  "timezone": "America/Denver",
  "lockStart": "06:00",
  "safetyRelease": "23:00",
  "requiredChoreIDs": ["chore_1", "chore_2"],
  "issuedAt": "...",
  "expiresAt": "...",
  "keyID": "policy-2026-09"
}
```

The client validates schema, audience/device, signature, expiry, day/timezone, and monotonic `policyVersion`. Policy signatures allow the child to reject tampered cached state; they are not a substitute for Apple parental-control authorization.

### Offline parent unlock

The recovery flow must not depend on APNs or internet availability:

1. Parent selects child, duration, and reason on an already authenticated parent device.
2. The parent app requests a server-signed grant while online and caches a small bounded set of grants, or signs with a hardware-backed parent device key that the child previously enrolled.
3. Parent shows a QR code; numeric entry is a fallback.
4. Child verifies the signature locally and checks household, child device, nonce, `notBefore`, `expiresAt`, maximum duration, and grant type.
5. Child records the nonce in an append-only redemption set and reconciles shields.
6. Redemption syncs to the backend later.

Prefer QR because a secure signed payload is too large for a pleasant six-digit code. A short numeric code generally requires an online exchange and is not truly offline. If a human-entered offline code is required, use a compact encoding with enough entropy and a short lifetime; security and usability must be threat-modeled before production.

Grant constraints:

- Maximum offline duration: configurable, default 2 hours.
- Never valid beyond the policy's safety-release boundary.
- Bound to one household and child device.
- Single-use nonce; tolerate reinstall/key-loss through a parent recovery flow.
- No embedded child name, chore evidence, or sensitive content.
- Verification keys rotate; retain old public keys through maximum token lifetime.

The safety-release time is a product recovery feature, not an invisible fail-open: parents choose it during onboarding and see it in daily status. Always-allowed essential apps remain outside the selected shield set.

## 6. Domain model

Core aggregates:

- `Household`: timezone, members, supported integrations.
- `Member`: parent/guardian or child; authentication identity and permissions.
- `ChildDevice`: enrollment, push token, public key, enforcement capabilities, health.
- `ChoreTemplate`: recurrence, evidence requirement, estimated duration.
- `ChoreOccurrence`: dated instance with completion and approval state.
- `Evidence`: metadata and protected object reference; no public URLs.
- `RestrictionPolicy`: schedule, required occurrences, selected Apple tokens held locally, device targets.
- `AccessGrant`: scoped, signed exception or completed-day unlock.
- `NetworkTarget`: router-scoped device identifier and parent-facing label.
- `EnforcementReport`: desired/actual state, last reconcile, actionable error.

Use a household-local date plus IANA timezone for daily occurrence identity. Define daylight-saving, travel, and skipped-day behavior in tests; do not derive the chore day solely from UTC.

## 7. Backend interfaces

An HTTP/JSON API is adequate initially. Commands require idempotency keys; mutable resources use versions/ETags.

```text
POST   /v1/device-enrollments
GET    /v1/households/{id}/today
PUT    /v1/chore-occurrences/{id}/completion
POST   /v1/chore-occurrences/{id}/evidence-upload
POST   /v1/chore-occurrences/{id}/decision
GET    /v1/devices/{id}/policy
POST   /v1/devices/{id}/enforcement-reports
POST   /v1/devices/{id}/access-grants
POST   /v1/access-grants/{id}/redemptions
GET    /v1/router-integrations/{id}/targets
POST   /v1/network-targets/{id}/pause
POST   /v1/network-targets/{id}/resume
POST   /v1/network-targets/{id}/test
```

Backend services:

- **Identity/household service** — Sign in with Apple or another approved login, invitation and role enforcement.
- **Chore service** — recurrence materialization and approval state machine.
- **Policy service** — calculates desired grants/restrictions and signs envelopes.
- **Evidence service** — short-lived uploads, malware/content checks as appropriate, retention/deletion.
- **Notification service** — APNs delivery; messages contain resource IDs/version only, not evidence details.
- **Integration service** — encrypted vendor credentials and router adapter execution.
- **Audit service** — parent decisions, grants, policy changes, and integration commands.

### State changes and delivery

Use an outbox pattern so approval and its downstream effects cannot diverge:

```text
approve occurrence transaction
  -> update occurrence(s)
  -> derive access grant
  -> append policy-changed event
  -> append router-desired-state event
```

Workers deliver APNs and router commands with retries. A router command is convergent desired-state reconciliation, not a one-shot toggle. The UI shows `Unlock approved; Apple TV pending` if the child phone and router have different health.

## 8. Router adapter boundary

Router support is an optional capability. Keep vendor logic server-side unless a vendor requires LAN-local discovery/control.

```swift
protocol RouterAdapter {
    var capabilities: RouterCapabilities { get }
    func authorize(_ input: AuthorizationInput) async throws -> RouterAccount
    func listTargets(account: RouterAccount) async throws -> [NetworkTarget]
    func status(target: NetworkTarget) async throws -> NetworkTargetStatus
    func setInternetAccess(
        target: NetworkTarget,
        desired: InternetAccess,
        idempotencyKey: String
    ) async throws -> RouterCommandResult
}
```

Required capability flags include whole-device pause, reliable resume, remote/cloud command, target identifiers stable across DHCP leases, command-status polling, connection termination, and rate limits. Adapters normalize vendor states into `open`, `paused`, `transitioning`, `offline`, `unknown`, or `unsupported`.

Production admission criteria for an adapter:

- Public or contractually authorized API; no reverse-engineered private endpoints.
- OAuth/token revocation and least-privilege credential handling.
- Stable target identity across IP changes and router restarts.
- Tested pause and resume latency, including an already-playing stream.
- Idempotent recovery after backend retry/restart.
- Parent work devices cannot be selected implicitly.
- Clear vendor-specific recovery instructions.
- Commercial terms allow a third-party parental-control integration.

See [APPLE_TV_INTEGRATION.md](APPLE_TV_INTEGRATION.md).

## 9. Internet filtering strategy

Stage filtering to reduce entitlement and support risk:

1. **Production v1:** Apple app/category/web-domain shields selected through Family Controls. This is not a general packet filter.
2. **Validated pilot:** a managed list of distraction web domains, still represented by Apple's privacy-preserving tokens where applicable.
3. **Deferred:** a Network Extension content filter for broader socket/browser flow decisions, only after confirming entitlement availability, consumer deployment rules, privacy posture, coexistence with VPNs/Private Relay, and App Review acceptance. Apple's content-filter provider architecture intentionally prevents the data provider from exporting observed network content. See [Content filter providers](https://developer.apple.com/documentation/networkextension/content-filter-providers) and [TN3134](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment).

Do not implement a packet-tunnel VPN merely to intercept DNS. Do not claim full URL visibility for encrypted traffic. Collect aggregate enforcement health rather than browsing history.

## 10. Security and child privacy

- Separate parent and child authorization scopes server-side; never trust a client-supplied role.
- Bind devices using per-installation hardware-backed keys where feasible.
- Encrypt vendor credentials and evidence at rest; short-lived signed object URLs only.
- Apply evidence retention defaults and parent-visible deletion controls.
- Never put Family Controls tokens, child names, evidence URLs, or chore text in analytics.
- Audit every unlock, policy edit, target reassignment, and router pause/resume.
- Require recent parent authentication for integration changes and long overrides.
- Rate-limit evidence, pairing, unlock, and router-command endpoints.
- Complete COPPA/child-privacy and App Store Kids/privacy review before launch; this document is not legal advice.

## 11. Observability and support

Expose a parent-readable health card per target:

```text
Liam's iPhone: Restrictions active · checked 2 min ago
Family Room Apple TV: Paused · router confirmed 18 sec ago
Internet filter: App/site shields active
```

Record correlation IDs across approval, policy generation, APNs delivery, child reconciliation, and router command. Metrics should cover reconciliation success, time-to-unlock, router latency/error by adapter version, stale devices, unexpected safety releases, and override use—without collecting browsing activity.

## 12. Delivery gates

### Gate A — simulated vertical slice

- Local chores, evidence placeholders, parent approval, and simulated shield/router status.
- Automated tests for recurrence, policy derivation, grants, timezones, and state recovery.
- Every enforcement UI clearly says simulation.

### Gate B — device enforcement spike

- Development entitlement and on-device Family Controls authorization.
- Picker tokens persist through app/extension boundary.
- Device Activity schedule reapplies shields after app termination and reboot scenarios.
- Approval removes shields; offline signed QR grant works.

### Gate C — connected beta

- Separate parent/child devices, backend sync, APNs, real evidence upload.
- One router adapter passes admission tests; Apple TV test-pause onboarding.
- Support diagnostics and emergency recovery validated with real families.

### Gate D — ship readiness

- Production Family Controls and any Network Extension entitlements approved.
- App Review narrative and demo account/device path documented.
- Privacy/legal, threat model, accessibility, restore/reinstall, and failure-mode testing complete.
- Marketing claims match the capability truth table.

## 13. Open validation risks

1. Production approval for Family Controls entitlement for the app and all required Screen Time extensions.
2. Exact OS/device behavior of schedules, shielding, and shield actions across supported iOS versions.
3. Whether a consumer Network Extension content-filter entitlement/deployment model is available and acceptable for this product.
4. Router vendors with supported third-party APIs that can reliably pause and resume one Apple TV.
5. Whether vendor pause ends established streams or only prevents new connections.
6. Apple TV identity stability when Private Wi-Fi Address/network settings change.
7. APNs/background timing; the offline grant and local reconciliation are required mitigations, not optional polish.

