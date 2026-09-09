# GetEmDone

GetEmDone is a family routine app that keeps selected entertainment apps and supported living-room devices unavailable until a child's daily responsibilities are approved.

This repository currently contains the first testable iOS product tranche: a local-first SwiftUI prototype, enforcement abstractions, deterministic fixtures, and unit tests. Screen Time distribution entitlements, cloud sync, and production router adapters remain explicit shipping gates.

## Run

```sh
xcodegen generate
xcodebuild -project GetEmDone.xcodeproj -scheme GetEmDone \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

See [`docs/`](docs/) for the product contract, architecture, test plan, and staged release plan.

GitHub Actions runs the unsigned simulator build and unit tests on every pull request and push. TestFlight delivery is separately protected and intentionally remains disabled until Apple signing, App Store Connect, and Family Controls entitlement prerequisites are configured. See [`docs/CI_CD.md`](docs/CI_CD.md).
