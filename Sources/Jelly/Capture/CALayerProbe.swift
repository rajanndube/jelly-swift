#if canImport(UIKit)
import UIKit
import QuartzCore

/// CoreAnimation-layer hit-test probe.
///
/// SwiftUI renders most static content (Text, Image, Shape, backgrounds,
/// strokes) into CALayers attached directly to a single UIView rather than
/// allocating a separate UIView per SwiftUI view. On screens with few
/// interactive widgets, the visual hierarchy can have **no deeper UIView**
/// than the SwiftUI hosting view — every visible widget lives as a sublayer
/// of that view's `layer`.
///
/// When the UIView and accessibility probes both bottom out at a giant
/// generic UIView (typical for analytics-SDK-wrapped apps that suppress the
/// SwiftUI accessibility tree), this probe drills into the layer tree and
/// returns the deepest *visible* sublayer at the press point — yielding a
/// tight bounding box around the actual rendered widget (the button, the
/// text glyph run, the icon, the card background, etc.).
@MainActor
enum CALayerProbe {

    struct Result {
        /// Bounding box of the layer, in window coordinates.
        let frameInWindow: CGRect
        /// Runtime class name of the matched layer (e.g. `CALayer`,
        /// `CAShapeLayer`, `_TtCV...`). Used as the role fallback when
        /// no accessibility label / UILabel text is available.
        let layerClass: String
        /// Hint about what the layer is drawing — drives the role name.
        let kind: Kind

        enum Kind { case image, shape, text, drawing }
    }

    /// Walks every sublayer of `root.layer` and returns the smallest
    /// visible layer whose frame contains `pointInWindow`. Returns nil
    /// when the press misses every contentful sublayer.
    static func deepestVisibleLayer(in root: UIView, pointInWindow: CGPoint) -> Result? {
        var best: Result?
        walk(root.layer, pointInWindow: pointInWindow) { candidate in
            if best == nil || candidate.frameInWindow.area < best!.frameInWindow.area {
                best = candidate
            }
        }
        return best
    }

    private static func walk(
        _ layer: CALayer,
        pointInWindow: CGPoint,
        emit: (Result) -> Void
    ) {
        if layer.isHidden || layer.opacity < 0.03 { return }
        // `convert(_:to: nil)` walks the implicit super-layer chain to the
        // root layer of the hierarchy (the UIWindow's layer), so the result
        // is in window coordinates — the same space as `pointInWindow`.
        let frameInWindow = layer.convert(layer.bounds, to: nil)
        if !frameInWindow.contains(pointInWindow) { return }
        // Drop hairline / zero-sized layers to avoid picking 1pt separator
        // strokes over real widgets.
        if frameInWindow.width < 2 || frameInWindow.height < 2 { return }

        if let kind = classify(layer) {
            emit(.init(
                frameInWindow: frameInWindow,
                layerClass: String(describing: type(of: layer)),
                kind: kind
            ))
        }

        if let sublayers = layer.sublayers {
            for sub in sublayers {
                walk(sub, pointInWindow: pointInWindow, emit: emit)
            }
        }
    }

    /// Decide whether a layer is drawing something the user can see. Layers
    /// with no contents, no border, and a transparent background are
    /// transit-only — recurse into them but don't emit.
    private static func classify(_ layer: CALayer) -> Result.Kind? {
        if layer is CATextLayer { return .text }
        if layer is CAShapeLayer { return .shape }
        if layer.contents != nil { return .image }
        if layer.borderWidth > 0.01 { return .drawing }
        if let bg = layer.backgroundColor, bg.alpha > 0.03 { return .drawing }
        return nil
    }
}
#endif
