# CI/CD contract

## Current automation

`iOS CI` runs on every pull request and push to `main`, and can be started manually. It regenerates the Xcode project, builds the app without signing, runs the unit tests on an iOS Simulator, and retains the `.xcresult` bundle for 14 days.

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

- Require the `Build and unit test` check before merging to `main` once the first successful run establishes the check name.
- Require pull requests for feature work; emergency policy changes still need CI.
- Enable secret scanning and dependency alerts.
- Keep deployment secrets only in the protected `testflight` environment.
- Never run forked pull-request code with signing or deployment secrets.
- Use immutable release tags and generate release notes from the tranche commit.

## Future jobs

1. Swift formatting/linting with a pinned tool version.
2. UI and accessibility tests on two simulator form factors.
3. Physical-device Screen Time qualification outside ordinary GitHub-hosted CI.
4. Backend contract, migration, security, and dependency tests when the service exists.
5. Signed archive and TestFlight upload after Apple prerequisites pass.
6. Scheduled compatibility builds against the current and next Xcode/iOS releases.

