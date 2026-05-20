#if canImport(UIKit)
import UIKit

/// View-tree hit-test probe. Mirrors the View-fallback half of
/// `dev.jelly.capture.SemanticsCapture.captureInWindow` — walks the
/// visible UIView hierarchy and finds the deepest view containing the
/// press point, skipping invisible / overlay-marked subtrees.
@MainActor
enum UIViewProbe {

    struct Result {
        let view: UIView
        let frameInWindow: CGRect
    }

    /// Returns the deepest interactive UIView at `pointInWindow` using
    /// UIKit's authoritative `hitTest`. SwiftUI gesture host views are
    /// `isUserInteractionEnabled = true`, so this drills into them
    /// reliably. Falls back to a manual deep-walk only if `hitTest`
    /// returns nil or our own overlay window.
    static func deepestVisibleView(
        in root: UIView,
        pointInWindow: CGPoint
    ) -> Result? {
        // First, try the host window's native hitTest — this is what UIKit
        // uses for touch dispatch and is the most reliable way to find the
        // deepest interactive leaf (including SwiftUI's _TtCV... button hosts).
        if let window = root.window {
            // pointInWindow is already in window coords; UIView.hitTest
            // expects the receiver's own coords, which for a UIWindow is
            // identical.
            if let hit = window.hitTest(pointInWindow, with: nil),
               !(hit.window is JellyOverlayMarking),
               hit !== window {
                let frame = hit.convert(hit.bounds, to: nil)
                return Result(view: hit, frameInWindow: frame)
            }
        }

        // Fallback: manual deep walk. Iterates children in reverse z-order
        // (later subviews draw on top) and treats transparent shells as
        // pass-through so the search falls through to the visible widget
        // underneath.
        return manualDeepWalk(in: root, pointInWindow: pointInWindow)
    }

    private static func manualDeepWalk(
        in root: UIView,
        pointInWindow: CGPoint
    ) -> Result? {
        if root.window is JellyOverlayMarking { return nil }
        if !isEffectivelyVisible(root) { return nil }

        let frame = root.convert(root.bounds, to: nil)
        if !frame.contains(pointInWindow) { return nil }

        for child in root.subviews.reversed() {
            if let hit = manualDeepWalk(in: child, pointInWindow: pointInWindow) {
                return hit
            }
        }
        if isTransparentShell(root) { return nil }
        return Result(view: root, frameInWindow: frame)
    }

    private static func isEffectivelyVisible(_ view: UIView) -> Bool {
        if view.isHidden { return false }
        if view.alpha <= 0.01 { return false }
        if view.bounds.width <= 0 || view.bounds.height <= 0 { return false }
        return true
    }

    private static func isTransparentShell(_ view: UIView) -> Bool {
        guard !view.subviews.isEmpty else { return false }
        let bg = view.backgroundColor
        if let bg, !bg.isEffectivelyTransparent { return false }
        if view.layer.backgroundColor != nil,
           let cg = view.layer.backgroundColor,
           cg.alpha > 0.03 {
            return false
        }
        return !hasMeaningfulOwnDrawing(view)
    }

    private static func hasMeaningfulOwnDrawing(_ view: UIView) -> Bool {
        if view is UILabel { return true }
        if view is UIImageView { return true }
        if view is UIControl { return true }
        if view.layer.contents != nil { return true }
        if view.layer.borderWidth > 0 { return true }
        return false
    }
}

private extension UIColor {
    var isEffectivelyTransparent: Bool {
        var alpha: CGFloat = 0
        getRed(nil, green: nil, blue: nil, alpha: &alpha)
        return alpha <= 0.03
    }
}
#endif
