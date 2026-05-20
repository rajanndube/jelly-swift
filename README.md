# Jelly for iOS

A debug-only QA-annotation toolbar for SwiftUI / UIKit apps. Long-press any element on screen, drop a comment, and share to Slack, the clipboard, or your MCP server as structured markdown plus a baked image.

This is the iOS port of [`jelly-android`](https://github.com/rajan-dube/jelly-android). The output markdown contract and `/sessions` API are byte-identical, so the same downstream agents work for all clients.

```
┌─────────────────────────────┐
│                             │
│     [Host app content]      │     Long-press → live stroke rectangle
│                             │     Release → comment popup
│                             │     Share → markdown + image
│                       (FAB) │
└─────────────────────────────┘
```

- **Zero per-screen wiring.** Install once at the App level, and every scene gets the toolbar automatically.
- **SwiftUI and UIKit hit-testing.** Works on screens that mix SwiftUI views with UIKit view controllers. Reads the UIView hierarchy plus the UIAccessibility tree.
- **Debug-only.** Gated to debug builds via `#if DEBUG`. Never ships in release.
- **Source attribution.** Automatic via the install-site `#fileID` capture, with per-screen overrides via `.jellySource()`.
- **Self-contained shareable image.** Element bounds, label, source line, and comment all baked into the screenshot.

---

## Integration in three steps

### Prerequisites

- iOS 16+ (Mac Catalyst 16+ / visionOS 1+ / macOS 13+ where the SDK no-ops without UIKit).
- A SwiftUI `App` or a UIKit `AppDelegate`.

### Step 1: Add the package

In Xcode: **File → Add Package Dependencies… → Add Local…** and pick the `jelly-swift` folder. Add the `Jelly` library product to your app target.

For SwiftPM-driven projects, in your `Package.swift`:

```swift
dependencies: [
    .package(path: "../jelly-swift")
],
targets: [
    .executableTarget(
        name: "MyApp",
        dependencies: [
            .product(name: "Jelly", package: "jelly-swift", condition: .when(configuration: .debug))
        ]
    )
]
```

The `condition: .when(configuration: .debug)` is the iOS analog of Android's `debugImplementation`: the SDK is only linked into debug builds.

### Step 2: Call `Jelly.install()` at app launch

**SwiftUI:**

```swift
import SwiftUI
#if DEBUG
import Jelly
#endif

@main
struct MyApp: App {
    init() {
        #if DEBUG
        Jelly.install()
        #endif
    }
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

**UIKit:**

```swift
import UIKit
#if DEBUG
import Jelly
#endif

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        #if DEBUG
        Jelly.install()
        #endif
        return true
    }
}
```

### Step 3: Build and run

The toolbar appears as a draggable FAB in the bottom-right of every scene. No per-view wiring required.

---

## Smoke test

1. Launch the debug build. A small dark pill with a location-pin icon should appear at the bottom-right.
2. Tap the pin. The toolbar expands with review, settings, and close actions.
3. Tap the pin again to enable annotate-mode (the pin turns the accent color).
4. Long-press any UI element. A live stroke rectangle should follow your finger, snapping to the deepest accessibility element under it.
5. Release. The screenshot captures, and a popup appears with the captured region preview.
6. Type a comment, choose intent and severity, then tap Add. A numbered marker appears at the captured spot.
7. Open the toolbar's review screen to see all annotations with thumbnails. Share to send the image and markdown to Slack or wherever else.

If the FAB does not appear, confirm `Jelly` is on the link line: in Xcode, target → Build Phases → Link Binary With Libraries.

---

## Configuration

`JellyConfig` accepts:

```swift
JellyConfig(
    detailLevel: .standard,                                   // compact / standard / detailed / forensic
    accentColor: .indigo,                                     // 7 colors available
    endpoint: URL(string: "https://your-mcp.example.com"),    // optional MCP /sessions sync
    sessionId: nil,                                           // resume a known session
    webhookURL: nil,                                          // optional outbound webhook
    copyToClipboard: true,
    captureScreenshots: true,
    screenKey: nil                                            // override the per-VC storage key
)
```

Most settings are also exposed as a runtime UI in the toolbar's settings sheet. What you pass in `JellyConfig` is just the default before the user changes it.

---

## Source attribution

Every annotation includes a `Source: SomeFile.swift:42` line. Three resolvers run in priority order:

1. **`.jellySource()` modifier on a screen root.** Manual and most precise. SwiftUI captures `#fileID` and `#line` at the call site, so values are correct without any runtime stack walking.
   ```swift
   struct LoginScreen: View {
       var body: some View {
           VStack { ... }.jellySource()
       }
   }
   ```
   The capture pipeline walks ancestor `UIView`s and picks the closest tag, so tagging the screen root is enough.

2. **`UIHostingController` type name.** When the user long-presses a SwiftUI view, the capture pipeline reads the nearest `UIHostingController<Root>` and stores `String(reflecting: Root.self)` in the `**Composables:**` field, mirroring what the Android version pulls from Compose's slot tree.

3. **Install-site fallback.** `Jelly.install(file:line:)` defaults capture the call-site so every annotation gets a meaningful `Source: MyApp.swift:9` automatically.

You do not need to do anything for source attribution to work. Reach for `.jellySource()` only when you want sub-screen precision.

> Note: unlike on the JVM, Swift's runtime does not surface `file:line` from the call stack, only mangled symbols. Tier-1 `.jellySource()` is the only path to true sub-screen precision; the install-site fallback is a single fixed pin. This is the only material parity difference from the Android SDK.

---

## How element identification works

The SDK runs **two parallel hit-tests** on long-press and picks whichever is more specific:

1. **`UIView` hit-test.** Walks the foreground window's view hierarchy and finds the deepest visible view containing the press point. Carries the strongest hit on UIKit-rendered content.
2. **`UIAccessibility` element walk.** Recurses through `accessibilityElements` from the host view and picks the smallest-area frame containing the point. Carries the strongest hit on SwiftUI-rendered content (where SwiftUI's render tree is not public, but its accessibility output is).

When the accessibility hit is meaningfully tighter, it wins. This is what makes the toolbar precise on SwiftUI screens, where the deepest UIView is usually a generic `_UIHostingView`.

Hidden views (`isHidden`, `alpha < 0.01`, zero-sized layouts, transparent shell container views with no opaque content of their own) are filtered out, so a backend-flag-driven hidden overlay cannot steal hits from the visible widget underneath.

---

## Output format

Annotations are exported as markdown with structured fields:

```markdown
### 1. Button "Submit"
**Location:** LoginScreen > Form > Button
**Source:** ContentView.swift:42
**Composables:** MyApp.LoginScreen
**Feedback:** This should be primary, not secondary
```

The export also includes a screenshot with the element bounds drawn in the accent color and a caption strip baking the metadata into the image, so receivers that drop attachments (Slack, WhatsApp) still see the context.

The format is byte-identical to the Android version and the web version's `generateOutput()`, so the same downstream agents work for all clients.

---

## Known limitations

- **No `file:line` runtime resolution.** Swift's `Thread.callStackSymbols` carries only mangled symbols, not source coordinates. Tier-1 `.jellySource()` is the path to sub-screen precision; tier-3 is one fixed pin at the install site. This is the only material divergence from the Android SDK behavior.
- **SwiftUI render tree is private.** All hit-testing rides UIKit and `UIAccessibility`. Apps that aggressively merge accessibility (`.accessibilityElement(children: .combine)`) will produce coarser captures. Leave default `.contain` behavior on screen roots for best granularity.
- **Multi-window scenes (iPad Stage Manager, external display).** Each `UIWindowScene` gets its own pair of overlay windows; capture in window A does not affect window B. Memory will leak if the per-scene attachment dict is not cleared on `sceneDidDisconnect` (handled in `SceneOverlayController`).
- **No way to capture system / Apple-managed views** (status bar, control center, share sheet inner chrome). Long-press inside those areas falls back to "outermost containing window" or finds nothing.

---

## SDK development

For active SDK development against an unpublished branch (when you are modifying `jelly-swift/Sources/...` and do not want to publish per change), use a local Swift Package reference instead of a remote URL.

The included [`jelly sample/`](jelly%20sample/) Xcode project already does this; it points at the parent jelly-swift folder via an `XCLocalSwiftPackageReference` with `relativePath = ".."`. Edits to the SDK source pick up on the next build with no publish step.

For a host project, in Xcode: File → Add Package Dependencies → Add Local… → pick the `jelly-swift` folder.

---

## Status

`v0.1`: Single-line `Jelly.install()`, FAB toolbar, annotate-mode, two-window architecture (`UIWindow` at `.alert + 1` for the FAB plus a separate capture window), SwiftUI accessibility + UIView dual hit-test, settings sheet, review screen, `OutputGenerator` byte-parity tests, MCP `/sessions` sync via URLSession, baked share images.

See [`CLAUDE.md`](CLAUDE.md) for repo-internal architecture notes and the design plan at `~/.claude/plans/crispy-mixing-sketch.md`.
