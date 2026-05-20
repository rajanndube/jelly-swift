# Jelly iOS (Swift / SwiftUI port)

Standalone Swift Package. Ports the Jelly QA toolbar from `jelly-android` to native Swift / SwiftUI / UIKit so QA can long-press any UI element in an iOS app, capture structured feedback, and hand it to AI coding agents as markdown plus a baked image. Status: v0.1, `swift build` green; sample app builds via `xcodebuild -project "jelly sample/jelly sample.xcodeproj"`; `swift test` 17 tests pass.

The output markdown contract is **byte-identical** to the Android and web SDK so the same downstream agents work for all three clients.

## What this is

A Swift Package that QA / designers add to their iOS app. Long-press any UI element while annotate-mode is on, the library inspects the runtime view + accessibility tree, a popup captures a comment, output goes to clipboard / share sheet / MCP `/sessions` endpoint as markdown.

## Integration (host app perspective)

```swift
@main
struct MyApp: App {
    init() {
        #if DEBUG
        Jelly.install()
        #endif
    }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

No per-screen wiring. No accessibility-id plumbing. Optional `.jellySource()` modifier on screen roots for sub-screen source attribution.

## Architecture (key files)

- `Sources/Jelly/Jelly.swift` — public install / uninstall / isInstalled, mirrors `dev.jelly.Jelly`
- `Sources/Jelly/JellyConfig.swift` — config struct, mirrors `JellyConfig.kt`
- `Sources/Jelly/JellyOverlayState.swift` — shared `ObservableObject` state across the two overlay windows
- `Sources/Jelly/Install/SceneOverlayController.swift` — per-`UIWindowScene` attachment registry; mirrors `ActivityOverlayController.kt`
- `Sources/Jelly/Install/JellyOverlayWindow.swift` — toolbar window at `windowLevel = .alert + 1` (above SwiftUI sheets)
- `Sources/Jelly/Install/JellyCaptureWindow.swift` — capture overlay window at `.statusBar - 1`
- `Sources/Jelly/Install/JellyOverlayContent.swift` — SwiftUI content of the capture window: markers, long-press gesture, popup, review screen, settings sheet
- `Sources/Jelly/Capture/HitTestEngine.swift` — orchestrates the two probes and picks the tighter winner
- `Sources/Jelly/Capture/UIViewProbe.swift` — UIKit view-tree walk, mirrors the View-fallback half of `SemanticsCapture.captureInWindow`
- `Sources/Jelly/Capture/AccessibilityProbe.swift` — `UIAccessibility` element walk, the SwiftUI semantic-tree analog
- `Sources/Jelly/Capture/JellySourceRegistry.swift` — `NSMapTable` weak-keyed source tags + `UIViewController.jellySource(file:line:)`
- `Sources/Jelly/Capture/HostSourceDetector.swift` — captures the `Jelly.install()` site `#fileID` / `#line`
- `Sources/Jelly/Capture/Screenshot.swift` — `UIGraphicsImageRenderer` window capture excluding our own overlay windows
- `Sources/Jelly/Modifiers/JellySource.swift` — `.jellySource(file:line:)` SwiftUI modifier backed by an invisible `UIViewRepresentable` marker
- `Sources/Jelly/Output/OutputGenerator.swift` — 1:1 byte-parity port of `OutputGenerator.kt`; tested against curated golden fixtures
- `Sources/Jelly/Storage/AnnotationStore.swift` — UserDefaults suite with 7-day TTL, mirrors `AnnotationStore.kt`
- `Sources/Jelly/Sync/JellyAPI.swift` — URLSession async/await client mirroring `sync/JellyApi.kt`
- `Sources/Jelly/Models/Annotation.swift` — `Codable` with `CodingKeys` mapping `composableHierarchy ↔ "reactComponents"` and `syncedTo ↔ "_syncedTo"` for wire parity
- `Sources/Jelly/Theme/JellyTheme.swift` — forced-dark zinc palette (#09090B / #18181B / #27272A / #FAFAFA / #A1A1AA / #52525B)
- `jelly sample/` — minimal SwiftUI app for live testing (not part of the SwiftPM package; standalone Xcode project)

## Source location (`Source: Foo.swift:42`)

Three paths populate `Annotation.sourceFile`, in priority order. First non-nil wins:

1. **`.jellySource()` SwiftUI modifier or `vc.jellySource()` UIKit method.** Uses `#fileID` / `#line` defaults at the call site, so values are correct without runtime stack walking. The capture pipeline walks ancestor `UIView`s and picks the closest registered tag.

2. **`UIHostingController` type-name inference.** Populates `composableHierarchy` (the Android `**Composables:**` field), not `sourceFile`. Type-name only, not `file:line`.

3. **Install-site fallback.** `Jelly.install(file: #fileID, line: #line)` captures the call site once. Used as the last-resort `sourceFile`.

This means **zero per-screen integration code** is required for source attribution in the common case (every annotation gets `Source: MyApp.swift:9`). Devs only reach for `.jellySource()` when they want sub-screen precision.

## What ports vs. what doesn't

Ports cleanly: element identification (UIView + UIAccessibility), bounds, output markdown, storage shape, MCP `/sessions` API, screenshot + bake, settings sheet, review screen, accent colors, motion tokens.

Doesn't port (same as Android): no React Native introspection, no animation freeze, no keyboard shortcuts, no design-mode style mutation, no multi-select drag, no drawing strokes.

iOS-specific divergences:
- **Source `file:line` is not recoverable from `Thread.callStackSymbols`.** Swift's runtime carries mangled symbols only. Tier-1 `.jellySource()` is the only path to true sub-screen precision; tier-3 is one fixed install-site pin (the JVM stack-walk equivalent only works on Android). Document this prominently.
- **Forced-dark theme is `.preferredColorScheme(.dark)` on overlay windows only.** Does not bleed into host content.
- **Two-window FAB-over-sheets** is a clean win. `UIWindow(windowLevel: .alert + 1)` sits above SwiftUI `.sheet` and `.fullScreenCover` (both presented within the host window) without the focus-bumper / `WindowManager.removeViewImmediate` workaround needed on Android.
- **iPad Stage Manager.** `SceneOverlayController` is keyed by `ObjectIdentifier(UIWindowScene)` so each scene gets its own pair of windows. Tear down on `sceneDidDisconnect` is mandatory or windows leak.

## Source of truth

The full design plan is at `~/.claude/plans/crispy-mixing-sketch.md`. Read it for context, decisions log, and phasing.

## Phasing

- **v0.1** (current) — `Jelly.install` (multi-scene), `JellyOverlayWindow`, FAB toolbar, annotate-mode toggle, dual UIView + UIAccessibility hit-test, `AnnotationPopup`, `OutputGenerator` with parity-fixture tests, clipboard out, UserDefaults annotation store, MCP `/sessions` sync via URLSession, `AnnotationsScreen` review UI, `SettingsSheet`, accent colors, detail levels, baked screenshots, source attribution (3-tier).
- **v0.2** — Drag-to-edge FAB with spring snap, haptics (`UIImpactFeedbackGenerator`), motion polish for popup / sheet entrances.
- **v0.3** — Live-hover refinement (longer-pressed hit follows finger to deepest element), nearby-text / sibling extraction parity with Android.
- **v0.4** — UIKit-only host refinement (deeper UIControl + responder-chain walk for non-SwiftUI apps), VoiceOver-aware capture mode.
- **v0.5+** — Redaction tags (mark sensitive elements as "do not screenshot"), region-only screenshots, design-mode hot-tweak overlays.

## Build

```bash
swift build                                # builds the SDK (macOS host, iOS arm64 cross)
xcodebuild -scheme Jelly \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    build                                  # iOS Simulator build
xcodebuild -scheme Jelly \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    test                                   # 17 tests
xcodebuild -project "jelly sample/jelly sample.xcodeproj" \
    -scheme "jelly sample" \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    build                                  # sample app
```

## Android cross-reference

Cross-references in source code (`dev.jelly.*` / `package/src/...`) point at files in the sibling `../jelly-android` repo (and the web `../jelly` repo). Read those alongside this code when porting new features. The markdown contract and `Annotation` schema are the load-bearing parity points and are tested in `Tests/JellyTests/OutputGeneratorParityTests.swift` + `AnnotationCodableTests.swift`.
