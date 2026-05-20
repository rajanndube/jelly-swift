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

    /// Returns the deepest UIView at `pointInWindow`. Runs two passes and
    /// merges:
    ///
    /// 1. UIKit's `hitTest` for the deepest *interactive* view. SwiftUI
    ///    gesture host views and UIControls are reliably surfaced here.
    /// 2. A manual deep walk for the deepest *visible* view, drilling past
    ///    interactive containers into their drawing leaves (UILabel,
    ///    UIImageView, etc.) so QA can annotate the actual visible widget
    ///    inside a tap row / card / cell — not just the tap target.
    ///
    /// When both pass — typically the case for SwiftUI Buttons, UIKit cells,
    /// custom tap rows — the visual leaf wins if it's a descendant of the
    /// interactive hit AND meaningfully tighter (the same arbitration as
    /// Android's `shouldPreferSlot`).
    static func deepestVisibleView(
        in root: UIView,
        pointInWindow: CGPoint
    ) -> Result? {
        let interactive: Result? = {
            guard let window = root.window else { return nil }
            guard let hit = window.hitTest(pointInWindow, with: nil),
                  !(hit.window is JellyOverlayMarking),
                  hit !== window else { return nil }
            return Result(view: hit, frameInWindow: hit.convert(hit.bounds, to: nil))
        }()
        let visual = manualDeepWalk(in: root, pointInWindow: pointInWindow)

        switch (interactive, visual) {
        case (nil, let v): return v
        case (let i, nil): return i
        case (let i?, let v?):
            // Use the visual leaf when it lives inside the interactive hit
            // (legitimate nested content) AND is at least 10% tighter. The
            // descendant check protects against picking a sibling that happens
            // to share the point under iPad popover edge-cases.
            let isNested = v.view.isDescendant(of: i.view) || v.view === i.view
            if isNested, v.frameInWindow.area < i.frameInWindow.area * 0.9 {
                return v
            }
            return i
        }
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
