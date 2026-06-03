# Jelly iOS (Swift / SwiftUI)

Standalone Swift Package. A debug-only QA toolbar: long-press any UI element in an iOS app, capture structured feedback, and hand it to AI coding agents as markdown plus a baked image. Status: v0.1; the SDK is iOS-only and builds + passes its 17 tests via `xcodebuild` against the iOS Simulator (the macOS host slice no-ops via `canImport(UIKit)`, so plain `swift build` / `swift test` do not compile the UIKit-backed code).

The output markdown contract is **byte-identical** to the Jelly Android and web SDKs, so the same downstream agents work across all three clients.

## What this is

A Swift Package that QA / designers add to their iOS app. Long-press any UI element while annotate-mode is on; the library inspects the runtime view + accessibility tree, a popup captures a comment, and output goes to clipboard / share sheet / MCP `/sessions` endpoint as markdown.

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

- `Sources/Jelly/Jelly.swift` — public `install` / `uninstall` / `isInstalled` entrypoint
- `Sources/Jelly/JellyConfig.swift` — config struct
- `Sources/Jelly/JellyOverlayState.swift` — shared `ObservableObject` state across the two overlay windows
- `Sources/Jelly/Install/SceneOverlayController.swift` — per-`UIWindowScene` attachment registry
- `Sources/Jelly/Install/JellyOverlayWindow.swift` — toolbar window at `windowLevel = .alert + 1` (above SwiftUI sheets)
- `Sources/Jelly/Install/JellyCaptureWindow.swift` — capture overlay window at `.statusBar - 1`
- `Sources/Jelly/Install/JellyOverlayContent.swift` — SwiftUI content of the capture window: markers, long-press gesture, popup, review screen, settings sheet
- `Sources/Jelly/Capture/HitTestEngine.swift` — orchestrates the probes and picks the tightest winner
- `Sources/Jelly/Capture/UIViewProbe.swift` — UIKit view-tree walk
- `Sources/Jelly/Capture/AccessibilityProbe.swift` — `UIAccessibility` element walk (the SwiftUI semantic-tree analog)
- `Sources/Jelly/Capture/CALayerProbe.swift` — recursive `CALayer` walk for layer-rasterized SwiftUI content
- `Sources/Jelly/Capture/JellySourceRegistry.swift` — `NSMapTable` weak-keyed source tags + `UIViewController.jellySource(file:line:)`
- `Sources/Jelly/Capture/HostSourceDetector.swift` — captures the `Jelly.install()` site `#fileID` / `#line`
- `Sources/Jelly/Capture/Screenshot.swift` — `UIGraphicsImageRenderer` window capture excluding our own overlay windows
- `Sources/Jelly/Modifiers/JellySource.swift` — `.jellySource(file:line:)` SwiftUI modifier backed by an invisible `UIViewRepresentable` marker
- `Sources/Jelly/Output/OutputGenerator.swift` — produces the export markdown; tested against curated golden fixtures
- `Sources/Jelly/Storage/AnnotationStore.swift` — UserDefaults suite with 7-day TTL
- `Sources/Jelly/Sync/JellyAPI.swift` — URLSession async/await client for the MCP `/sessions` endpoint
- `Sources/Jelly/Models/Annotation.swift` — `Codable` with `CodingKeys` mapping `composableHierarchy ↔ "reactComponents"` and `syncedTo ↔ "_syncedTo"` for wire parity
- `Sources/Jelly/Theme/JellyTheme.swift` — forced-dark zinc palette (#09090B / #18181B / #27272A / #FAFAFA / #A1A1AA / #52525B)
- `jelly sample/` — minimal SwiftUI app for live testing (not part of the SwiftPM package; standalone Xcode project)

## Source location (`Source: Foo.swift:42`)

Three paths populate `Annotation.sourceFile`, in priority order. First non-nil wins:

1. **`.jellySource()` SwiftUI modifier or `vc.jellySource()` UIKit method.** Uses `#fileID` / `#line` defaults at the call site, so values are correct without runtime stack walking. The capture pipeline walks ancestor `UIView`s and picks the closest registered tag.

2. **`UIHostingController` type-name inference.** Populates `composableHierarchy` (the `**Composables:**` field), not `sourceFile`. Type-name only, not `file:line`.

3. **Install-site fallback.** `Jelly.install(file: #fileID, line: #line)` captures the call site once. Used as the last-resort `sourceFile`.

This means **zero per-screen integration code** is required for source attribution in the common case (every annotation gets `Source: MyApp.swift:9`). Devs only reach for `.jellySource()` when they want sub-screen precision.

## Capabilities

Element identification (UIView + UIAccessibility + CALayer), bounds, output markdown, storage, MCP `/sessions` sync, screenshot + bake, settings sheet, review screen, accent colors, motion tokens.

Not in scope: React Native introspection, animation freeze, keyboard shortcuts, design-mode style mutation, multi-select drag, drawing strokes.

Platform notes:
- **Source `file:line` is not recoverable from `Thread.callStackSymbols`.** Swift's runtime carries mangled symbols only. Tier-1 `.jellySource()` is the only path to true sub-screen precision; tier-3 is one fixed install-site pin.
- **Forced-dark theme is `.preferredColorScheme(.dark)` on overlay windows only.** Does not bleed into host content.
- **Two-window FAB-over-sheets.** `UIWindow(windowLevel: .alert + 1)` sits above SwiftUI `.sheet` and `.fullScreenCover` (both presented within the host window).
- **iPad Stage Manager.** `SceneOverlayController` is keyed by `ObjectIdentifier(UIWindowScene)` so each scene gets its own pair of windows. Teardown on `sceneDidDisconnect` is mandatory or windows leak.

## Phasing

- **v0.1** (current) — `Jelly.install` (multi-scene), FAB toolbar, annotate-mode toggle, dual UIView + UIAccessibility hit-test plus CALayer probe, `AnnotationPopup`, `OutputGenerator` with parity-fixture tests, clipboard out, UserDefaults annotation store, MCP `/sessions` sync via URLSession, review UI, settings sheet, accent colors, detail levels, baked screenshots, source attribution (3-tier).
- **v0.2** — Drag-to-edge FAB with spring snap, haptics, motion polish for popup / sheet entrances.
- **v0.3** — Live-hover refinement (long-press hit follows finger to deepest element), nearby-text / sibling extraction.
- **v0.4** — UIKit-only host refinement (deeper UIControl + responder-chain walk for non-SwiftUI apps), VoiceOver-aware capture mode.
- **v0.5+** — Redaction tags (mark sensitive elements as "do not screenshot"), region-only screenshots, design-mode hot-tweak overlays.

## Build

```bash
xcodebuild -scheme Jelly \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    build                                  # builds the SDK
xcodebuild -scheme Jelly \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    test                                   # 17 tests
xcodebuild -project "jelly sample/jelly sample.xcodeproj" \
    -scheme "jelly sample" \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    build                                  # sample app
```

The `OutputGenerator` markdown contract and the `Annotation` schema are the load-bearing parity points across the iOS, Android, and web clients; they are covered by `Tests/JellyTests/OutputGeneratorParityTests.swift` and `AnnotationCodableTests.swift`.
