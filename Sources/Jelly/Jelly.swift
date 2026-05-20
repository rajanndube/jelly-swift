#if canImport(UIKit)
import UIKit

/// Public install/uninstall entry point. Mirrors `dev.jelly.Jelly` (jelly-android)
/// except this is a Swift `enum` namespace rather than a Kotlin `object`.
///
/// Call once from `App.init` (SwiftUI) or
/// `application(_:didFinishLaunchingWithOptions:)` (UIKit), gated by `#if DEBUG`:
///
/// ```swift
/// @main
/// struct MyApp: App {
///     init() {
///         #if DEBUG
///         Jelly.install()
///         #endif
///     }
///     var body: some Scene { WindowGroup { ContentView() } }
/// }
/// ```
///
/// From that point, every `UIWindowScene` in the app gets the toolbar
/// overlay automatically — no per-screen wrapping, no per-control plumbing.
/// `file` and `line` default to the install call site (`#fileID` / `#line`)
/// so every annotation gets a meaningful `Source: MyApp.swift:9`
/// automatically. Use `.jellySource()` on a screen root when you want
/// sub-screen precision.
@MainActor
public enum Jelly {

    private static var controller: SceneOverlayController?

    /// Installs the overlay across every active `UIWindowScene`. Idempotent
    /// — calling twice is safe; the second call is ignored.
    public static func install(
        config: JellyConfig = JellyConfig(),
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        if controller != nil { return }
        HostSourceDetector.shared.setInstallSite(file: file, line: line)
        // One-time migration: previous SDK builds saved screenshots
        // under `Library/Caches/jelly/...` (purgeable). The bytes are
        // copied to `Library/Application Support/jelly/...` by
        // `JellyScreenshot.imageDirectory()`, but each annotation's
        // `screenshotPath` field still references the old Caches path
        // and has to be rewritten in place.
        AnnotationStore().migrateLegacyScreenshotPaths()
        controller = SceneOverlayController(config: config)
    }

    /// Removes the overlay from every scene and stops listening for future
    /// scene activations. Safe to call even if `install` was never called.
    public static func uninstall() {
        controller?.detachAll()
        controller = nil
        HostSourceDetector.shared.reset()
    }

    /// True between `install` and `uninstall` — useful for QA toggles.
    public static var isInstalled: Bool { controller != nil }
}
#endif
