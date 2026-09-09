# Apple TV Whole-Device Pause Integration

Status: design and vendor-validation plan  
Last reviewed: 2026-09-08

## Product promise

With a supported home network, a parent can designate an Apple TV and have GetEmDone pause that device's internet access while a child's chores remain incomplete. Parent approval or an explicit override resumes access.

This is a router/network feature. It is **not** a tvOS app-control feature and does not know which Apple TV profile or person is using the television.

## What “pause Apple TV” means

The supported router is asked to deny WAN access for the selected network client. The command should affect all streaming applications without maintaining lists of Netflix, YouTube, or CDN domains.

Expected behavior while paused:

- New internet streams fail to start.
- App catalogs and other WAN features may fail.
- LAN behavior such as AirPlay or local media may remain available, depending on router implementation.
- An already-buffered segment may continue briefly.
- If the router cannot terminate established flows, an already-playing stream may continue. The UI and compatibility record must disclose this.

GetEmDone does not block the Apple TV from powering on, alter tvOS restrictions, or selectively allow a parent based on the remote/profile.

## Why whole-device pause is the default

Whole-device pause is easier to explain and validate than DNS/service filtering. DNS-only blocking can be bypassed by cached resolutions, alternate resolvers, service infrastructure changes, and established connections. Service-specific filtering may be explored later as an advanced mode; it must not dilute the reliability claim of whole-device pause.

## Consumer setup

1. Parent opens **Add a TV**.
2. App displays only router brands/integrations actually supported.
3. Parent authorizes the network account using the vendor-supported flow.
4. GetEmDone lists candidate network clients with name, device type where available, connection state, and last seen—not raw networking jargon by default.
5. Parent selects a candidate and starts a 30-second test pause.
6. Parent confirms the intended Apple TV lost streaming access.
7. GetEmDone resumes access automatically even if confirmation never arrives.
8. Parent assigns a friendly room label and which child's completed routine governs it.

Never auto-assign a device solely because its hostname contains `Apple TV`. The verification test prevents a work or shared device from being accidentally governed.

Required parent controls:

- Resume now
- Unlock for 30 minutes / 1 hour / until bedtime
- Re-pause now
- Exclude TV today
- Remove TV from GetEmDone
- Test connection

Router failure must never change the parent or child phone's policy. Conversely, TV pause failure must not show the overall routine as still locked after the phone has unlocked.

## Normal state flow

```text
Chore day starts
  -> Policy service wants target PAUSED
  -> Integration worker calls adapter
  -> Adapter confirms or returns pending/error
  -> Parent UI shows independently confirmed TV status

Final required chore approved
  -> Access grant committed
  -> Policy change + router desired-state events written atomically
  -> Child device removes iOS shields
  -> Integration worker wants target OPEN
  -> Adapter confirms resume
```

Network desired state is derived from policy and overrides:

```text
desiredTVAccess = OPEN if parentOverride.isActive
               = OPEN if allRequiredChoresAreApproved
               = OPEN if outsideConfiguredRestrictionWindow
               = PAUSED otherwise
```

The worker continually converges observed state toward desired state. Commands are idempotent. Never model `pause` and `resume` as untracked fire-and-forget actions.

## Adapter contract

Each vendor adapter must expose:

```text
authorize / revoke
listNetworkTargets
readTargetStatus
setTargetInternetAccess(open | paused, idempotencyKey)
readCommandStatus (if asynchronous)
```

Normalized target fields:

```json
{
  "integrationID": "int_...",
  "vendorTargetID": "encrypted-or-tokenized",
  "displayName": "Family Room Apple TV",
  "vendorDeviceType": "media_player",
  "macAddressAvailable": false,
  "connection": "online",
  "lastSeenAt": "...",
  "identityConfidence": "user_verified"
}
```

Do not use an IP address as the durable identifier. Prefer the vendor's stable client ID; a MAC address is sensitive and can change, and must be encrypted/tokenized if retained.

## Adapter certification tests

No adapter is advertised until it passes on supported firmware versions:

1. Discover target, rename it in the router app, and rediscover without duplication.
2. Pause from an open state and verify new streams fail within the published latency.
3. Pause during active playback and document whether playback terminates.
4. Resume and verify streaming recovers without rebooting the Apple TV.
5. Repeat pause/resume commands and reordered retries safely.
6. Change DHCP lease/IP and verify identity remains stable.
7. Restart router and backend worker; desired state reconverges.
8. Revoke vendor authorization; status becomes actionable, not falsely `open` or `paused`.
9. Simulate vendor outage/rate limit/timeouts.
10. Verify test pause always auto-resumes by deadline.
11. Verify parent override wins over chore-driven pause.
12. Verify removal from GetEmDone resumes the target before unlinking, or gives an explicit recovery warning if resume cannot be confirmed.

Publish an adapter compatibility record containing router models, minimum firmware, typical pause/resume latency, active-stream behavior, known limitations, and last certification date.

## Failure and recovery UX

Normalized states and copy:

| State | Parent presentation | Action |
|---|---|---|
| `paused` | Apple TV paused | Resume/override |
| `open` | Apple TV available | Pause/test |
| `transitioning` | Applying TV access… | Retry automatically |
| `offline` | Apple TV appears offline | No destructive retry loop |
| `unknown` | Can't confirm TV access | Test connection / open router app |
| `unsupported` | Router no longer supports this control | Remove integration / support |

If resume is requested but cannot be confirmed, escalate visibly and provide vendor-specific steps to resume the device in the router's own app. A persistent “open” display based only on our intended state is unacceptable.

## Shared-TV semantics

Because a router sees one Apple TV client, the policy cannot distinguish child viewing from parent viewing. Product rules:

- Apple TV targets are opt-in and may be assigned to one routine or a household aggregate.
- A parent override opens the shared TV without completing or approving chores.
- Overrides are quick, visible, time-bounded by default, and auditable.
- No child-facing copy should imply the system identified who attempted to watch.

## Security and privacy

- Use vendor OAuth when available; do not collect the router administrator password.
- Encrypt refresh tokens with a managed key and isolate vendor adapters from general evidence data.
- Request the minimum vendor scopes for client discovery and pause/resume.
- Record commands and results, not household traffic or watched services.
- Vendor webhooks and callbacks require signature/state verification.
- Recent parent authentication is required to connect, reassign, or remove a router.
- Integration deletion revokes vendor tokens and deletes target identifiers on the retention schedule.

## Simulated versus production behavior

### Simulation

`MockRouterAdapter` can list fixtures, delay transitions, and inject errors. It proves UX and backend convergence only. It must show a persistent simulation label and cannot support claims about Apple TV enforcement.

### Production

Production requires a vendor-supported API, commercial permission, actual router and Apple TV hardware tests, observability, and a recovery runbook. A router's first-party app having a pause button does **not** establish that an authorized third-party API exists.

No vendor should be named as supported until these points are verified directly with current documentation or a vendor agreement. Candidate research may include ecosystems that expose client policy controls, but reverse-engineered endpoints are out of scope.

## API-validation questions for every vendor

1. Is third-party client-device pause/resume publicly supported?
2. Is the integration local, cloud-based, or both?
3. What OAuth/scopes, review, partnership, or certification are required?
4. Are client identifiers stable across DHCP, router restart, mesh roaming, and Apple private-address changes?
5. Does pause block WAN only or LAN too?
6. Are established connections terminated?
7. What are command latency, eventual-consistency behavior, rate limits, and status endpoints?
8. Can a command auto-expire to guarantee recovery after a test pause?
9. What models/firmware are covered?
10. May GetEmDone store labels and tokenized client identifiers under the vendor terms?
11. What happens when the customer disables parental controls in the router's own app?
12. Is production access commercially sustainable?

## Go/no-go criteria for the first integration

Proceed only if one vendor offers an authorized interface that can:

- discover and stably identify the parent-verified Apple TV;
- pause and reliably resume its WAN access;
- report enough state to avoid misleading the parent;
- recover through retries without duplicate or inverted state;
- meet a consumer-acceptable setup flow; and
- support the intended commercial use.

If no candidate passes, ship iOS app/site enforcement without Apple TV control. Do not replace the feature with manual DNS configuration or an unsupported private router API merely to preserve scope.

