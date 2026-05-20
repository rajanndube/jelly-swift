#if canImport(UIKit)
import UIKit

/// Mirrors `dev.jelly.capture.Screenshot`. Uses `UIGraphicsImageRenderer`
/// to capture the full window, then iterates the scene's other visible
/// windows in z-order so any sheets, alerts, or keyboards get baked in
/// too. Excludes our own overlay windows.
public enum JellyScreenshot {

    /// Captures the host window's content (and any sibling sheets / alerts
    /// in the same scene) and writes to `cacheDir/jelly/<id>.jpg`. Returns
    /// the file path or nil on failure.
    @MainActor
    public static func captureWindow(
        annotationId: String,
        window: UIWindow,
        excluding markedWindows: [UIWindow] = []
    ) -> String? {
        let bounds = window.bounds
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = window.screen.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)

        // Hide overlay windows BEFORE rendering so they don't bake into the
        // shot. Restore on exit.
        let hideStates = markedWindows.map { ($0, $0.isHidden) }
        for w in markedWindows { w.isHidden = true }
        defer { for (w, prev) in hideStates { w.isHidden = prev } }

        // Pull all visible non-overlay windows from the same scene, sorted
        // by z-order (low → high). This composites the host plus any
        // presented sheets / system alerts onto a single bitmap. For a
        // single-window app this just renders the host window itself.
        let scene = window.windowScene
        let allWindows: [UIWindow] = {
            guard let scene else { return [window] }
            return scene.windows
                .filter { !($0 is JellyOverlayMarking) }
                .filter { !$0.isHidden && $0.alpha > 0.01 }
                .sorted { $0.windowLevel < $1.windowLevel }
        }()

        let image = renderer.image { _ in
            for w in allWindows {
                // Each window may be at a different scene origin (iPad
                // multi-window). Convert its bounds into our renderer's
                // coordinate space.
                let frameInRoot = w.convert(w.bounds, to: window)
                // afterScreenUpdates: true forces any pending layout +
                // visibility changes (e.g. our overlay-hide above) to
                // apply before the snapshot. Without this, a stale
                // version with the FAB still visible can leak into the
                // bake.
                w.drawHierarchy(in: frameInRoot, afterScreenUpdates: true)
            }
        }
        return write(image: image, annotationId: annotationId)
    }

    private static func write(image: UIImage, annotationId: String) -> String? {
        let dir = JellyScreenshot.imageDirectory()
        let url = dir.appendingPathComponent("\(annotationId).jpg")
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }

    /// Resolves a stored `screenshotPath` value to a current absolute
    /// path that `UIImage(contentsOfFile:)` / `Data(contentsOf:)` can
    /// actually read. Handles three cases:
    ///
    ///  1. Path as stored is still valid (fresh install, no container
    ///     UUID rotation) — returned unchanged.
    ///  2. Path's directory has rotated (iOS reassigned the app's data
    ///     container UUID after a re-install from archive / TestFlight,
    ///     while preserving the data inside) — extract the basename
    ///     and look it up under the current `imageDirectory()`.
    ///  3. The file is genuinely gone — return nil so callers render
    ///     gracefully (no image, rest of the annotation intact).
    ///
    /// This is the right thing to call EVERY time you need to read an
    /// annotation's screenshot, anywhere. Absolute paths get baked into
    /// the JSON at capture time but the absolute file system layout
    /// isn't promised to be stable across re-installs.
    public static func resolve(storedPath: String?) -> String? {
        guard let stored = storedPath, !stored.isEmpty else { return nil }
        if FileManager.default.fileExists(atPath: stored) { return stored }
        let filename = (stored as NSString).lastPathComponent
        let resolved = imageDirectory().appendingPathComponent(filename).path
        return FileManager.default.fileExists(atPath: resolved) ? resolved : nil
    }

    /// Persistent directory for annotation screenshots — `Library/Application
    /// Support/jelly/`. Application Support is the right home for
    /// app-managed data that must persist between launches; using
    /// `Library/Caches/` (the previous location) was incorrect because
    /// iOS purges Caches under storage pressure, which manifested as
    /// "annotation text survives but the image is gone after restart".
    /// Created lazily on first write.
    public static func imageDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("jelly", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Best-effort one-time migration: copy any baked images that the
        // previous build wrote to Caches/jelly/ across to the new home,
        // so users upgrading don't lose existing screenshots. The Caches
        // copy is left in place; the system will eventually evict it.
        migrateLegacyCachesIfNeeded(target: dir)
        return dir
    }

    private static var legacyMigrationDone = false
    private static func migrateLegacyCachesIfNeeded(target: URL) {
        guard !legacyMigrationDone else { return }
        legacyMigrationDone = true
        guard let oldBase = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let oldDir = oldBase.appendingPathComponent("jelly", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: oldDir, includingPropertiesForKeys: nil
        ) else { return }
        for src in entries {
            let dst = target.appendingPathComponent(src.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dst.path) {
                try? FileManager.default.copyItem(at: src, to: dst)
            }
        }
    }
}

/// Marker protocol for windows the screenshot pipeline must skip. The two
/// install windows (`JellyOverlayWindow`, `JellyCaptureWindow`) conform.
public protocol JellyOverlayMarking: AnyObject {}
#endif
