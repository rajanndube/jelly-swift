# Changelog

All notable changes to the Jelly iOS SDK are documented here. This project adheres to [Semantic Versioning](https://semver.org).

## [0.1.2] — 2026-05-20

Fixes "only the parent container is selectable" for apps that rasterize SwiftUI content into CALayers (analytics-SDK-wrapped apps with suppressed accessibility, banking / fintech apps), and removes content-overlap from the annotation mark.

### Added
- **`CALayerProbe`** — a third hit-test probe that walks `view.layer.sublayers` recursively and returns the tightest visible contentful layer (image / shape / text / drawing) at the press point. Kicks in when both `UIViewProbe` and `AccessibilityProbe` bottom out at a giant generic container — the common case when SwiftUI rasterizes static content into CALayers, or when an analytics SDK (Smartlook, Plotline, Heap) suppresses the accessibility tree.
- **Opt-in diagnostics** — `HitTestEngine.debugLoggingEnabled` (default `false`). When enabled, every `capture()` dumps both probe results, the CALayer hit, the host window's view tree at the press point, and the full accessibility candidate set. Useful when onboarding the SDK into a new app and an element isn't selectable.

### Changed
- **`HitTestEngine` arbitration** now resolves in priority order: (1) accessibility hit with a label / identifier / non-trivial trait, (2) a specific `UIView` (`UILabel`, `UIControl`, `UIImageView`, `UITextView`, cells), (3) a CALayer at least 40% tighter than the deepest UIView, (4) the generic UIView as a last-resort anchor.
- The accent mark now renders as a rounded 2.5pt stroke **outset by half its width**, so the stroke sits entirely outside the captured bounds and never paints over the element — keeping QA color reporting faithful. Applied to both `AnnotatedScreenshot.bake` and the `AnnotationPopup` preview.

### Compatibility
No API changes. Drop-in replacement for 0.1.0 / 0.1.1.

## [0.1.1] — 2026-05-20

Fixes hit-test precision when long-pressing nested elements (labels, icons, text) inside SwiftUI Buttons, UIKit cells, custom tap rows, and cards.

### Changed
- **`UIViewProbe`** now always runs both UIKit's `hitTest` and a manual deep walk, then picks the visual leaf when it's a descendant of the interactive hit and at least 10% tighter. Previously it stopped at the deepest *interactive* view, which selected the parent container for most non-input widgets.
- **`AccessibilityProbe`** now falls back to the UIView subtree when a view publishes `accessibilityElements` as an *empty* array (not just `nil`) — fixing screens that use `.accessibilityElement(children: .combine)` near the root.

### Compatibility
No API changes. Drop-in replacement for 0.1.0.

## [0.1.0] — 2026-05-20

First public release of the Jelly iOS SDK — a debug-only QA-annotation toolbar for SwiftUI / UIKit apps.

### Added
- Single-line `Jelly.install()`, multi-scene aware (iPad Stage Manager, external displays).
- Two-window architecture — FAB at `windowLevel = .alert + 1` sits above SwiftUI sheets and `fullScreenCover` without workarounds.
- Dual hit-testing — parallel `UIView` tree walk + `UIAccessibility` element walk, picks the tighter winner so SwiftUI screens stay precise.
- 3-tier source attribution — `.jellySource()` modifier → `UIHostingController` type name → install-site `#fileID`/`#line` fallback. Zero per-screen wiring required.
- `OutputGenerator` byte-parity port — same markdown contract as the Android and web SDKs, golden-fixture tested.
- Annotation review screen, settings sheet, baked share images, 7-day TTL `UserDefaults` storage, MCP `/sessions` sync via `URLSession`.
- Forced-dark zinc theme on overlay windows only — does not bleed into host content.

### Requirements
- iOS 16+ (Mac Catalyst 16+ / visionOS 1+).
- SwiftUI or UIKit host app.
- Debug-only by design — gate `import Jelly` and `Jelly.install()` behind `#if DEBUG`.

[0.1.2]: https://github.com/rajanndube/jelly-swift/releases/tag/v0.1.2
[0.1.1]: https://github.com/rajanndube/jelly-swift/releases/tag/v0.1.1
[0.1.0]: https://github.com/rajanndube/jelly-swift/releases/tag/v0.1.0
