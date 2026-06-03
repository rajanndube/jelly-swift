# Contributing to Jelly for iOS

Thanks for your interest in improving Jelly. This is a small, focused SDK — contributions that keep it that way are very welcome.

## Ground rules

- **`main` is protected.** Open a pull request; direct pushes are rejected. Keep PRs scoped to one change.
- **Preserve the markdown contract.** `OutputGenerator` produces output that is byte-identical to the Android and web SDKs. Any change to its output must keep the golden-fixture parity tests green — that contract is load-bearing for downstream agents.
- **Debug-only.** The SDK is meant to be linked into debug builds only. Don't add anything that assumes it ships in release.

## Getting set up

```bash
git clone https://github.com/rajanndube/jelly-swift.git
cd jelly-swift
swift build        # builds the SDK
swift test         # runs the parity + storage tests
```

For iOS Simulator builds and the sample app:

```bash
xcodebuild -scheme Jelly \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

xcodebuild -project "jelly sample/jelly sample.xcodeproj" \
    -scheme "jelly sample" \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Before you open a PR

1. `swift test` passes (all parity tests green).
2. New behavior has a test where practical — especially anything touching `OutputGenerator` or the hit-test probes.
3. Code matches the surrounding style (naming, comment density, idiom).
4. Update [`CHANGELOG.md`](CHANGELOG.md) under an "Unreleased" heading if your change is user-facing.

## Architecture

See [`CLAUDE.md`](CLAUDE.md) for the file-by-file map of the codebase and the key parity points.

## Reporting bugs

Open an issue with: device / iOS version, whether the host screen is SwiftUI or UIKit, and — if an element isn't selectable — the output of `HitTestEngine.debugLoggingEnabled = true` around the long-press.
