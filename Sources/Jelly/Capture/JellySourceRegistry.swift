#if canImport(UIKit)
import UIKit

/// Mirrors `dev.jelly.capture.JellySourceRegistry`.
///
/// On Android, source attribution travels through the Compose semantics
/// tree as a `SemanticsPropertyKey<SourceInfo>` and the capture pipeline
/// walks the hit node's ancestors looking for the closest tag.
///
/// On iOS we tag the underlying `UIView` ancestor — either a sentinel
/// `JellySourceMarkerView` injected via the `.jellySource()` SwiftUI
/// modifier, or directly via associated objects on a `UIViewController`.
/// At hit time, `HitTestEngine` walks the `superview` / `next` responder
/// chain looking for the closest registered tag.
///
/// `NSMapTable` with weak keys keeps us from retaining views past their
/// natural lifetime — when the host view goes away, so does its tag.
public struct JellySourceInfo: Hashable, Sendable {
    public let file: String
    public let line: Int

    public init(file: String, line: Int) {
        self.file = file
        self.line = line
    }

    public func formatted() -> String { "\(file):\(line)" }
}

@MainActor
public final class JellySourceRegistry {
    public static let shared = JellySourceRegistry()

    private let viewTags = NSMapTable<UIView, NSString>(
        keyOptions: [.weakMemory, .objectPointerPersonality],
        valueOptions: [.copyIn]
    )

    /// Holds a strong reference to the bridging value while the view is
    /// alive — without this, the autoreleased NSString sometimes dies on
    /// the next runloop cycle and the lookup misses.
    private var liveTags: [ObjectIdentifier: JellySourceInfo] = [:]

    private init() {}

    public func tag(_ view: UIView, with source: JellySourceInfo) {
        viewTags.setObject(source.formatted() as NSString, forKey: view)
        liveTags[ObjectIdentifier(view)] = source
    }

    public func untag(_ view: UIView) {
        viewTags.removeObject(forKey: view)
        liveTags.removeValue(forKey: ObjectIdentifier(view))
    }

    /// Look up the source tag for a single view (no ancestor walk).
    public func source(for view: UIView) -> JellySourceInfo? {
        liveTags[ObjectIdentifier(view)]
    }

    /// Walk ancestors looking for the deepest registered tag — that's
    /// usually the actual screen / form root. Mirrors
    /// `SemanticsCapture.nearestSourceInfo`.
    public func nearestSource(forAncestorsOf view: UIView) -> JellySourceInfo? {
        var current: UIView? = view
        while let v = current {
            if let info = source(for: v) { return info }
            current = v.superview
        }
        return nil
    }
}

// MARK: - UIViewController source tagging

private var jellySourceAssociationKey: UInt8 = 0

public extension UIViewController {
    /// Tag this view controller with a `(file, line)` so any annotation
    /// captured inside it inherits the source attribution. Mirrors the
    /// Android `Modifier.jellySource()` ancestor-walk semantics.
    @MainActor
    func jellySource(file: StaticString = #fileID, line: UInt = #line) {
        let info = JellySourceInfo(file: "\(file)", line: Int(line))
        objc_setAssociatedObject(self, &jellySourceAssociationKey, info.formatted(), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        // Persist on the loaded view too so the ancestor walk on UIView
        // also picks it up regardless of whether the search starts from
        // the responder chain or the view tree.
        if isViewLoaded {
            JellySourceRegistry.shared.tag(view, with: info)
        }
    }

    /// Internal accessor for the associated source string (if any).
    @MainActor
    var jellySourceFormatted: String? {
        objc_getAssociatedObject(self, &jellySourceAssociationKey) as? String
    }
}

#endif
