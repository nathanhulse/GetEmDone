# GetEmDone engineering handoff

Read `docs/PRD.md`, `docs/UX_REQUIREMENTS.md`, `docs/ARCHITECTURE.md`, and `docs/RELEASE_TRANCHES.md` before changing scope.

## Current state

- Tranche 0 SwiftUI prototype builds and its domain-state tests pass.
- `DemoEnforcementService` is intentionally simulated. Never label it as real protection.
- No Family Controls entitlement, backend, production content filter, or router vendor authorization is configured yet.
- The parent experience must never block unassigned parent devices or the whole household by default.

## Build and test

```sh
xcodegen generate
xcodebuild -project GetEmDone.xcodeproj -scheme GetEmDone \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .DerivedData test CODE_SIGNING_ALLOWED=NO
```

## Implementation order

1. Complete Tranche 1 local chore CRUD, schedules, persistence, evidence capture, and UI tests.
2. Add real Family Controls targets only after distribution entitlement work begins; keep a demo adapter for Simulator.
3. Add backend sync, push reconciliation, audit events, and signed offline recovery.
4. Validate one router vendor commercially and technically before implementing a production Apple TV adapter.
5. Ship only after the gates in `docs/SHIP_CHECKLIST.md` pass on physical child and parent devices.

Use small SwiftUI views, explicit dependency injection, idempotent policy reconciliation, and truthful per-device status (`paused`, `available`, `pending`, `unreachable`, `unsupported`). Fail safely without disabling essential communication.

