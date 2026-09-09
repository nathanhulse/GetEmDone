# Screen Time Implementation Contract

Status: implementation-ready design; production capability remains entitlement-gated  
Deployment target: iOS/iPadOS 17.0+  
Last reviewed: 2026-09-09

## 1. Scope and safety boundary

This tranche replaces `DemoEnforcementService` for a managed child device with Apple's supported Screen Time stack:

- `FamilyControls` for guardian authorization and privacy-preserving app/category/web-domain selection.
- `ManagedSettings` for applying and removing shields.
- `DeviceActivity` for locally scheduled lock-window callbacks.
- A shield configuration extension for the blocked presentation.
- A shield action extension for a request/return action. It never grants access.

The implementation does not disable Wi-Fi or cellular, inspect selected app identities, infer browsing history, or manage Apple TV. It must never apply a broad fallback such as “all applications” when shared state is absent, corrupt, or incompatible. Parent devices are not enrolled as managed child devices.

Simulator builds remain fully usable for domain, persistence, UI, screenshot, and CI testing, but must identify enforcement as simulated. Simulator results are not evidence that Screen Time enforcement works.

## 2. Exact Xcode target map

Keep the existing application and unit-test targets and add three app extensions. Use these names and identifiers consistently in XcodeGen, App Store Connect, provisioning, logs, and documentation.

| Xcode target | Product type | Bundle identifier | Frameworks | Purpose |
| --- | --- | --- | --- | --- |
| `GetEmDone` | iOS application | `com.getemdone.app` | FamilyControls, ManagedSettings, DeviceActivity | Enrollment, protected picker, policy reconciliation, diagnostics |
| `GetEmDoneDeviceActivityMonitor` | Device Activity Monitor Extension | `com.getemdone.app.device-activity-monitor` | DeviceActivity, ManagedSettings | Start/end and threshold callbacks; reconcile cached desired state |
| `GetEmDoneShieldConfiguration` | Shield Configuration Extension | `com.getemdone.app.shield-configuration` | ManagedSettings, ManagedSettingsUI | Return branded shield copy and actions from cached, non-sensitive state |
| `GetEmDoneShieldAction` | Shield Action Extension | `com.getemdone.app.shield-action` | ManagedSettings | Record/request parent help or return to the shield; never unlock |
| `GetEmDoneTests` | Unit test bundle | `com.getemdone.tests` | XCTest | Pure policy, persistence, codec, and simulator-adapter tests |

Create a local Swift package or framework target named `GetEmDoneCore` when the Screen Time work begins. It must contain Foundation-only models, schedule/policy evaluation, shared snapshot codecs, and protocols. The app and all three extensions link it. `GetEmDoneCore` must not import SwiftUI, FamilyControls, ManagedSettings, or DeviceActivity.

Use dedicated source roots so an extension cannot accidentally compile the application entry point:

```text
GetEmDone/
GetEmDoneCore/
Extensions/DeviceActivityMonitor/
Extensions/ShieldConfiguration/
Extensions/ShieldAction/
GetEmDoneTests/
```

All four executable targets use the same deployment target. Each extension's `APPLICATION_EXTENSION_API_ONLY` setting is `YES`. The application embeds all three extension products. Unit tests depend on the app and/or `GetEmDoneCore`; CI continues to build every target even on Simulator.

## 3. Capabilities, entitlements, and identifiers

Reserve this App Group before generating distribution profiles:

```text
group.com.getemdone.shared
```

Use explicit entitlements files rather than Xcode's generated entitlements:

```text
Configuration/Entitlements/GetEmDone.entitlements
Configuration/Entitlements/DeviceActivityMonitor.entitlements
Configuration/Entitlements/ShieldConfiguration.entitlements
Configuration/Entitlements/ShieldAction.entitlements
```

The application entitlements are:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.family-controls</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.getemdone.shared</string>
    </array>
</dict>
</plist>
```

Each of the three Screen Time extension entitlements files contains the same two keys and App Group value. Apple requires Family Controls capability approval for distribution, and the capability must be enabled for the containing app and each Screen Time API extension App ID. Development signing may expose capability behavior that does not imply distribution approval.

Do not add Network Extension, DNS Proxy, Personal VPN, MDM, associated-domains, or keychain-sharing entitlements in this tranche. Push Notifications and Sign in with Apple belong to the later backend/account tranche and should be added only with their implementation.

For each App ID in Certificates, Identifiers & Profiles:

1. Register the explicit bundle identifier.
2. Enable Family Controls where Apple makes it available for that target.
3. Enable App Groups and attach `group.com.getemdone.shared`.
4. Regenerate development and distribution provisioning profiles after entitlement approval or capability changes.
5. Inspect the signed product with `codesign -d --entitlements :- <path>` before physical-device and archive testing.

Family Controls distribution approval is a release gate, not a build-time feature flag. App Store Connect should contain one app record for `com.getemdone.app`; extensions are embedded identifiers, not separate store listings.

## 4. Extension Info.plist contracts

Use the extension templates created by Xcode for the installed SDK rather than copying stale plist values from a blog. Verify the generated `NSExtensionPointIdentifier` values against the selected Xcode version. The intended extension principal classes and points are:

| Target | Principal type | Extension point intent |
| --- | --- | --- |
| Device Activity Monitor | subclass of `DeviceActivityMonitor` | Device Activity monitor extension |
| Shield Configuration | subclass of `ShieldConfigurationDataSource` | Managed Settings shield configuration service |
| Shield Action | subclass of `ShieldActionDelegate` | Managed Settings shield action service |

Do not put secrets, household names, child names, evidence, selected-token descriptions, or network configuration into an extension plist. Extension display names should be recognizable in diagnostics but need not appear as consumer-facing apps.

## 5. Shared container contract

The App Group contains only extension-safe, per-device data:

```text
Library/Application Support/ScreenTime/policy-v1.json
Library/Application Support/ScreenTime/shield-copy-v1.json
Library/Application Support/ScreenTime/extension-events-v1.jsonl
```

`policy-v1.json` is an atomically replaced envelope containing:

- schema version and monotonically increasing policy version;
- a non-identifying local device enrollment ID;
- household-local day and IANA timezone;
- restriction interval definitions and safety-release boundary;
- serialized `FamilyActivitySelection` data (opaque Apple tokens);
- current, bounded access grant and its expiration;
- desired mode (`locked`, `unlocked`, or `disabled`);
- last successful app reconciliation time.

Use `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`, encode to a sibling temporary file, apply complete file protection compatible with required post-first-unlock behavior, then atomically replace the prior snapshot. Never use a shared `UserDefaults` boolean as the enforcement source of truth. A schema or decoding failure yields `indeterminate/no-policy`, reports a diagnostic event, and does not broaden the shield set.

The app owns writes to policy and shield-copy snapshots. Extensions may append bounded diagnostic events through a concurrency-safe store. The monitor extension may apply the already-authorized cached desired policy; it must not mutate chore approval or create grants. Store authentication material and backend secrets outside the App Group in the app's Keychain.

Treat selection tokens as opaque and device-local. Do not log, upload, stringify for analytics, or attempt to resolve them into application identities. Do not copy a selection between children or devices.

## 6. Runtime architecture and simulator boundary

Place the capability boundary behind protocols in `GetEmDoneCore`:

```swift
public protocol ScreenTimeAuthorizing: Sendable {
    func status() async -> ScreenTimeAuthorizationState
    func requestChildAuthorization() async throws
}

public protocol ActivitySelectionStoring: Sendable {
    func save(_ data: Data) throws
    func load() throws -> Data?
}

public protocol ShieldApplying: Sendable {
    func reconcile(_ policy: LocalScreenTimePolicy, now: Date) async -> EnforcementReport
}

public protocol ActivityScheduling: Sendable {
    func replaceSchedules(with policy: LocalScreenTimePolicy) throws
    func removeAllSchedules() throws
}
```

Implement two compositions:

- `SystemScreenTimeController`: imports Apple frameworks, requests authorization, encodes/decodes `FamilyActivitySelection`, configures named `ManagedSettingsStore` instances, and registers Device Activity schedules.
- `SimulatedScreenTimeController`: deterministic in-memory/disk-backed test double that emits `simulated` reports and never claims system protection.

Select the composition once at the application boundary:

```swift
enum ScreenTimeComposition {
    static func make(environment: AppEnvironment) -> ScreenTimeControlling {
#if targetEnvironment(simulator)
        SimulatedScreenTimeController(clock: environment.clock)
#else
        SystemScreenTimeController(sharedContainer: environment.sharedContainer)
#endif
    }
}
```

Use `#if canImport(FamilyControls)` only to keep reusable core code portable; use `#if targetEnvironment(simulator)` for the behavioral boundary. Do not scatter conditional compilation through views or the domain store. UI consumes `EnforcementReport` with an explicit capability value: `simulated`, `available`, `unauthorized`, `revoked`, `unavailable`, or `failed`.

Debug builds on physical devices use the real controller by default. Provide a launch argument such as `-screenTimeMode simulated` only for automated UI fixtures; make the mode visibly persistent in the UI and unavailable in release builds.

Extension targets compile for Simulator in CI, but their callbacks are not acceptance evidence. Extension code reads the same snapshot and invokes a small synchronous/bounded reconciler. It must avoid network calls, database migrations, image work, unbounded logging, or dependencies on the containing app being alive.

## 7. Policy and store rules

Use stable, namespaced store and activity names. Define them once in `GetEmDoneCore`, for example:

```text
ManagedSettingsStore.Name: com.getemdone.chore-lock
DeviceActivityName:        com.getemdone.daily-chore-window
```

The desired shield state is derived, not toggled:

```text
shield = authorization is approved
      AND local policy is valid for this device/day
      AND now is within a restriction window
      AND required chores remain
      AND no unexpired parent grant covers now
```

When locked, set only the application/category/web-domain tokens explicitly selected by the guardian. When unlocked, clear GetEmDone's named store only. Never call a broad reset that could interfere with another product's managed settings. Repeated reconciliation with the same policy version must be idempotent.

Reconcile from the app on launch, foreground, selection change, policy change, grant receipt/redemption, authorization status change, significant time change, and day/timezone transition. The monitor extension reconciles at configured interval start/end callbacks. The app remains responsible for diagnosing schedule-registration errors and showing actual versus desired state.

The shield action extension may defer/close or create a local “request access” marker that the containing app sends later. It cannot authenticate a parent or remove shields. The shield configuration must use generic copy such as “Finish today's responsibilities to unlock this app”; it cannot name the blocked app because tokens are privacy-preserving.

## 8. Entitlement and delivery gates

| Gate | Evidence required | Blocks |
| --- | --- | --- |
| Paid Apple Developer membership | Active team and device registration | Signed physical-device work |
| Development App IDs/profiles | Four explicit App IDs plus shared App Group; installed entitlements inspected | Device spike |
| Family Controls distribution request | Submitted product explanation, guardian/child flow, privacy model, recovery behavior | TestFlight/App Store archive |
| Distribution entitlement approval | Approval covers containing app and required extensions; regenerated profiles sign successfully | External TestFlight and release |
| Family Sharing test accounts | Guardian and child Apple Accounts configured; consent reproducible | Child authorization claims |
| App Review narrative | Reviewer steps, test account/context, why controls exist, how to recover/revoke | App Store submission |
| Physical-device matrix passes | Results attached to release issue; no S0/S1 defect | Any external enforcement beta |

If distribution approval is denied or incomplete, ship neither simulated nor partially functional enforcement as production protection. Keep the feature behind a remote/local availability gate and continue the chore workflow without claiming device restriction.

## 9. Physical-device test matrix

Run Screen Time acceptance tests on real hardware with production-like signing. At minimum maintain these roles/devices:

| ID | Guardian device | Managed device | OS coverage | Account relationship |
| --- | --- | --- | --- | --- |
| P1 | Current-generation iPhone | Current-generation iPhone | Current iOS | Adult organizer + child Family Sharing member |
| P2 | Supported older iPhone | Supported older iPhone | Previous supported iOS | Adult guardian + child member |
| P3 | Current iPhone | Current iPad | Current iOS/iPadOS | Adult guardian + child member |
| P4 | Current iPhone | Current iPhone | Latest OS beta during beta season | Dedicated synthetic family |
| N1 | Current iPhone | Current iPhone | Current iOS | Adult/non-child account negative control |

For each supported release pair, execute and record:

| Test | Required observation |
| --- | --- |
| Fresh child authorization | Guardian consent completes; app reads approved state; cancellation is recoverable |
| Selection privacy | Apps/categories/domains can be selected; app/backend logs contain no resolved identity |
| Narrow shield | Selected targets show GetEmDone shield; unselected and essential targets remain available |
| Parent approval | Valid approval clears only GetEmDone's store within the stated SLO |
| Local morning schedule | Shield begins while the containing app is terminated and without a push |
| Interval end/safety release | Policy follows documented end behavior without a server wake-up |
| Device reboot | Cached valid policy converges after reboot/unlock; no broad fallback occurs |
| App force-quit | Schedule callback remains effective; reopening reports actual state accurately |
| Offline | Cached schedule applies; supported offline grant clears it; reconnect is idempotent |
| Delayed/duplicate approval | Refresh eventually converges; repeats do not relock or extend a grant |
| Authorization revoked | Protection status changes to revoked; app explains recovery and does not claim active |
| Family membership changed | Authorization/policy outcome is explicit; removed child cannot receive a new valid policy |
| Selection edited while locked | Old selection is cleared from GetEmDone store and new selection is applied without residue |
| Date/timezone/DST change | Correct household day is selected; no indefinite unlock or lock occurs |
| App/extension update | Existing compatible snapshot migrates or safely becomes indeterminate; no crash/broad block |
| Uninstall/reinstall | Documented system behavior observed; reenrollment and stale shared state handled safely |
| Low power/background pressure | Extension stays within system limits and desired state eventually reconciles |
| Multiple managed devices | Each device retains its own selection and grant; no cross-device token copying |
| Parent negative control | Guardian device remains wholly unaffected through every test |

Record device model, OS build, Xcode build, app build, Family Sharing roles, authorization before/after, desired/actual report, callback timestamps, and screenshots or screen recordings. Simulator CI remains mandatory but cannot waive a failed or missing physical-device result.

## 10. Automated test requirements

CI must build the app and all extension targets for Simulator and run:

- policy truth-table tests for authorized, unauthorized, expired, outside-window, completed, and indeterminate inputs;
- atomic snapshot round-trip, corrupt snapshot, unknown schema, monotonic version, and concurrent read/replace tests;
- simulator controller tests proving every report is labeled `simulated`;
- reconciler idempotency and “clear only our named store” adapter-contract tests;
- schedule calculation tests for midnight, DST, timezone travel, missed callbacks, and overlapping grants;
- shield-copy tests for generic language, accessibility, and absence of child/app/evidence data;
- extension entry-point smoke builds and fixture-based callback tests;
- release-build tests proving a simulation launch argument cannot activate simulated protection.

Apple framework calls should sit behind thin adapters. Unit tests assert commands emitted to those adapters; physical-device tests assert the operating system's actual outcome.

## 11. Implementation order

1. Obtain Team ID, register four App IDs and the App Group, and submit the Family Controls distribution request immediately.
2. Extract `GetEmDoneCore`, introduce explicit capability/report states, and retain `DemoEnforcementService` only as the named simulator implementation.
3. Add the three extension targets with Apple templates and shared entitlements; make CI compile all targets.
4. Implement atomic App Group snapshot storage and test malformed/migrated/concurrent state.
5. Implement authorization and `FamilyActivityPicker` on a managed physical device.
6. Implement named-store shield reconciliation and prove narrow lock/unlock manually.
7. Register one daily Device Activity schedule and prove app-terminated/reboot behavior.
8. Add shield configuration/action behavior and truthful diagnostics.
9. Complete the physical-device matrix, entitlement inspection, privacy review, and recovery drill before enabling an external TestFlight flag.

## 12. Go/no-go definition

The Screen Time tranche is complete only when the real signed build on managed physical devices can authorize, select, lock, approve/unlock, reset locally, recover after termination/reboot, and surface revocation accurately. All simulator tests must pass, but a green simulator pipeline alone is a no-go. Distribution remains a no-go until Apple grants the required Family Controls entitlement for the production app and extension identifiers and the archive's signed entitlements are verified.
