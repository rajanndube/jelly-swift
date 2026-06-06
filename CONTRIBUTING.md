# Contributing to Jelly for iOS

Thanks for your interest in improving Jelly. This is a small, focused SDK — contributions that keep it that way are very welcome.

## Ground rules

- **`main` is protected.** Open a pull request; direct pushes are rejected. Keep PRs scoped to one change.
- **Preserve the markdown contract.** `OutputGenerator` produces output that is byte-identical to the Android and web SDKs. Any change to its output must keep the golden-fixture parity tests green — that contract is load-bearing for downstream agents.
- **Debug-only.** The SDK is meant to be linked into debug builds only. Don't add anything that assumes it ships in release.

## Getting set up

Jelly is iOS-only, so build and test against the iOS Simulator with `xcodebuild` (the macOS host slice no-ops via `canImport(UIKit)`, so plain `swift build` / `swift test` won't compile the UIKit-backed code):

```bash
git clone https://github.com/rajanndube/jelly-swift.git
cd jelly-swift

# Build + run the parity / storage tests (17 tests)
xcodebuild -scheme Jelly \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Build the sample app
xcodebuild -project "jelly sample/jelly sample.xcodeproj" \
    -scheme "jelly sample" \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Licensing & sign-off (DCO)

This project is **source-available under the [PolyForm Shield 1.0.0](LICENSE)
licence** — free to use, modify, and distribute, but not to build a competing
product. By contributing, you agree your contribution is licensed under those
same terms.

Contributions are accepted under the [Developer Certificate of Origin](https://developercertificate.org/)
(DCO) — a lightweight, sign-off-based alternative to a CLA. It's a statement
that you wrote the patch (or otherwise have the right to submit it). To sign off,
add a `Signed-off-by` trailer to each commit:

```bash
git commit -s -m "your message"
```

This appends `Signed-off-by: Your Name <you@example.com>` using your
`git config user.name` / `user.email`. PRs whose commits aren't signed off will
be asked to amend (`git rebase --signoff main` fixes a whole branch). CI enforces
this per commit.

## Before you open a PR

1. `xcodebuild ... test` passes (all parity tests green).
2. New behavior has a test where practical — especially anything touching `OutputGenerator` or the hit-test probes.
3. Code matches the surrounding style (naming, comment density, idiom).
4. Update [`CHANGELOG.md`](CHANGELOG.md) under an "Unreleased" heading if your change is user-facing.
5. Sign off your commits (`git commit -s`, see above).

## Architecture

See [`CLAUDE.md`](CLAUDE.md) for the file-by-file map of the codebase and the key parity points.

## Reporting bugs

Open an issue with: device / iOS version, whether the host screen is SwiftUI or UIKit, and — if an element isn't selectable — the output of `HitTestEngine.debugLoggingEnabled = true` around the long-press.
