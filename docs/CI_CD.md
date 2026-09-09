# CI/CD contract

## Current automation

`iOS CI` runs on every pull request and push to `main`, and can be started manually. It provides three release gates:

- **Backend quality:** reproducible `npm ci`, strict TypeScript checking, Node test coverage with minimum thresholds (80% lines, 80% functions, 70% branches), and a high/critical production-dependency audit.
- **Dependency review:** pull requests are rejected when they introduce a high- or critical-severity dependency vulnerability.
- **Static analysis:** CodeQL scans the TypeScript backend on pushes, pull requests, manual runs, and every Monday. Findings appear in GitHub code scanning.
- **Apple build:** Xcode 26.3 regenerates the project, explicitly builds all three Screen Time extension targets without signing, validates their property lists and required Family Controls/App Group capabilities, then builds the app and runs unit tests on an iOS 26.2 simulator. The `.xcresult` is retained for 14 days.

Versions and destinations are explicit so a hosted-runner default change cannot silently produce a non-submittable build. Extension validation is intentionally separate from the application test build: removing an embedded extension or breaking one of its independent targets must fail CI even if ordinary unit tests still compile.

CI has read-only repository permissions. It receives no Apple signing material, child data, router credentials, or production secrets.

## Delivery design

`TestFlight Delivery` is a protected manual workflow. It currently validates only the release request because these prerequisites are intentionally absent:

- Apple Developer team and signing setup.
- App Store Connect app record and bundle identifier ownership.
- Approved Family Controls entitlements for the app and extensions.
- App Store Connect API key stored as GitHub environment secrets.
- Distribution certificate/profile strategy or Xcode Cloud configuration.

Once those exist, the job will archive, export, validate, upload to TestFlight, retain symbols/results, and record the Git commit and build number. The `testflight` GitHub environment should require manual approval and allow deployment only from `main` or signed release tags.

## Recommended repository policy

- Require `Backend quality gate`, `Dependency review`, and `Build and unit test` before merging to `main` once the first successful pull-request run establishes the check names. Configure `Dependency review` as required only for pull requests because GitHub intentionally skips that job on pushes.
- Require pull requests for feature work; emergency policy changes still need CI.
- Enable secret scanning and dependency alerts.
- Keep deployment secrets only in the protected `testflight` environment.
- Never run forked pull-request code with signing or deployment secrets.
- Use immutable release tags and generate release notes from the tranche commit.

## Future jobs

1. Swift formatting/linting with a pinned tool version.
2. UI and accessibility tests on two simulator form factors.
3. Physical-device Screen Time qualification outside ordinary GitHub-hosted CI.
4. Backend migration, adversarial authorization, and API fuzz tests as those surfaces expand.
5. Swift static analysis after a suitable pinned tool and ruleset are selected.
6. Signed archive and TestFlight upload after Apple prerequisites pass.
7. Scheduled compatibility builds against the current and next Xcode/iOS releases.

## Local parity checks

From the repository root:

```sh
(cd backend && npm ci && npm run typecheck && npm run test:coverage && npm run audit:production)
xcodegen generate
bash scripts/validate-ios-project.sh
```

The extension validation script requires macOS, the selected supported Xcode, and XcodeGen-generated project files. Dependency review is GitHub-specific and runs only on pull requests.
