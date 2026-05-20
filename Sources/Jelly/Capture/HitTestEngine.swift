#if canImport(UIKit)
import UIKit

/// Iterates two parallel hit-test strategies (accessibility-tree probe for
/// SwiftUI, UIView-tree probe for UIKit) and merges them into a single
/// `CapturedElement`. Mirrors the orchestration logic of
/// `dev.jelly.capture.SemanticsCapture` — pick the more specific hit, fall
/// back to the broader one when needed, then run the three-tier source
/// attribution chain (closest `.jellySource()`  → host VC type name → install
/// site).
@MainActor
public enum HitTestEngine {

    /// When true, every `capture()` call dumps both probe results, the full
    /// CALayer / accessibility candidate set, and the host-window inspection
    /// to stdout. Off by default. Flip on from a host app when diagnosing
    /// why a press is selecting the parent instead of the visible widget
    /// underneath (e.g. apps whose SwiftUI accessibility tree is suppressed
    /// by an analytics SDK):
    ///
    ///     #if DEBUG
    ///     Jelly.install()
    ///     HitTestEngine.debugLoggingEnabled = true
    ///     #endif
    public static var debugLoggingEnabled: Bool = false

    /// Last logged probe signature; used to dedupe identical live-hover spam.
    private static var lastLoggedSignature: String = ""

    /// Hit-test a window at `pointInWindow`. Returns nil only when the point
    /// is outside any visible content.
    public static func capture(
        in window: UIWindow,
        pointInWindow: CGPoint,
        skippingWindows skipped: [UIWindow] = []
    ) -> CapturedElement? {
        guard !skipped.contains(where: { $0 === window }) else { return nil }
        guard let root = window.rootViewController?.view ?? window.subviews.last else {
            return nil
        }

        let viewProbe = UIViewProbe.deepestVisibleView(in: root, pointInWindow: pointInWindow)
        let axProbe = AccessibilityProbe.bestMatch(in: root, pointInWindow: pointInWindow)
        let layerProbe = CALayerProbe.deepestVisibleLayer(in: root, pointInWindow: pointInWindow)

        if debugLoggingEnabled {
            let signature = "\(viewProbe.map { "\(type(of: $0.view))\($0.frameInWindow)" } ?? "nil")|\(axProbe.map { "\($0.label ?? "?")\($0.frameInWindow)" } ?? "nil")|\(layerProbe.map { "\($0.layerClass)\($0.frameInWindow)" } ?? "nil")"
            if signature != lastLoggedSignature {
                lastLoggedSignature = signature
                logProbes(pointInWindow: pointInWindow, root: root, viewProbe: viewProbe, axProbe: axProbe, layerProbe: layerProbe)
            }
        }

        // Arbitration order:
        // 1. AX with a real semantic label always wins — it carries the most
        //    information for the output markdown.
        // 2. A specific UIView (UILabel, UIControl, UIImageView, cell) wins
        //    over generic containers and over layer geometry.
        // 3. CALayer probe wins when the UIView probe bottoms out at a giant
        //    generic UIView (the layer-only SwiftUI rendering case). The
        //    layer's frame is the actual visible widget bounds even though
        //    we lose semantic labels.
        // 4. Otherwise the generic UIView fills in as a last-resort anchor.
        if let ax = axProbe, hasSemanticInfo(ax) {
            return buildFromAccessibility(ax: ax, viewProbe: viewProbe, root: root)
        }
        if let v = viewProbe, isSpecificView(v.view) {
            return buildFromView(view: v.view, frame: v.frameInWindow, ax: axProbe)
        }
        if let layer = layerProbe, shouldPreferLayer(layer: layer, view: viewProbe) {
            return buildFromLayer(layer: layer, anchor: viewProbe?.view ?? root)
        }
        if let v = viewProbe {
            return buildFromView(view: v.view, frame: v.frameInWindow, ax: axProbe)
        }
        if let ax = axProbe {
            return buildFromAccessibility(ax: ax, viewProbe: nil, root: root)
        }
        if let layer = layerProbe {
            return buildFromLayer(layer: layer, anchor: root)
        }
        return nil
    }

    /// AX hit carries enough info to make a usable annotation entry (label,
    /// identifier, or non-trivial trait).
    private static func hasSemanticInfo(_ ax: AccessibilityProbe.Result) -> Bool {
        if ax.label?.isEmpty == false { return true }
        if ax.identifier?.isEmpty == false { return true }
        if ax.traits != .none { return true }
        return false
    }

    /// UIView is a known semantic widget class — labels, controls, images,
    /// cells — as opposed to a generic SwiftUI container or `_UIHostingView`.
    private static func isSpecificView(_ view: UIView) -> Bool {
        if view is UILabel { return true }
        if view is UIControl { return true }
        if view is UIImageView { return true }
        if view is UITextView { return true }
        if view is UITableViewCell { return true }
        if view is UICollectionViewCell { return true }
        return false
    }

    /// Pick the layer over the view probe when the layer is meaningfully
    /// tighter — at least 40% smaller in area. Otherwise the layer is most
    /// likely just a background/stroke layer of the same widget the view
    /// probe found, and the view tells us more.
    private static func shouldPreferLayer(layer: CALayerProbe.Result, view: UIViewProbe.Result?) -> Bool {
        guard let view = view else { return true }
        let viewArea = view.frameInWindow.area
        let layerArea = layer.frameInWindow.area
        if viewArea < 1 { return true }
        return layerArea < viewArea * 0.6
    }

    // MARK: Layer-probe → CapturedElement

    private static func buildFromLayer(
        layer: CALayerProbe.Result,
        anchor: UIView
    ) -> CapturedElement {
        let role: String = {
            switch layer.kind {
            case .text:    return "Text"
            case .image:   return "Image"
            case .shape:   return "Shape"
            case .drawing: return "Element"
            }
        }()
        let w = Int(layer.frameInWindow.width)
        let h = Int(layer.frameInWindow.height)
        let displayName = "\(role) (\(w)×\(h))"
        return CapturedElement(
            displayName: displayName,
            elementPath: buildPath(view: anchor),
            role: role,
            contentDescription: nil,
            text: nil,
            testTag: nil,
            stateDescription: nil,
            bounds: layer.frameInWindow,
            nearbyElements: nil,
            nearbyText: collectNearbyText(view: anchor),
            composableName: hostingControllerName(for: anchor),
            sourceFile: resolveSourceFile(for: anchor)
        )
    }

    // MARK: View-probe → CapturedElement

    private static func buildFromView(
        view: UIView,
        frame: CGRect,
        ax: AccessibilityProbe.Result?
    ) -> CapturedElement {
        let role = roleName(for: view, traits: ax?.traits)
        let label = ax?.label
            ?? (view as? UILabel)?.text
            ?? (view as? UIButton)?.titleLabel?.text
            ?? firstDescendantLabel(view)
        let identifier = ax?.identifier ?? view.accessibilityIdentifier?.nilIfEmpty()
        let displayName = displayName(role: role, label: label, identifier: identifier)
        let path = buildPath(view: view)

        return CapturedElement(
            displayName: displayName,
            elementPath: path,
            role: role,
            contentDescription: ax?.label,
            text: label,
            testTag: identifier,
            stateDescription: ax?.value,
            bounds: frame,
            nearbyElements: collectNearby(view: view),
            nearbyText: collectNearbyText(view: view),
            composableName: hostingControllerName(for: view),
            sourceFile: resolveSourceFile(for: view)
        )
    }

    // MARK: Accessibility-probe → CapturedElement

    private static func buildFromAccessibility(
        ax: AccessibilityProbe.Result,
        viewProbe: UIViewProbe.Result?,
        root: UIView
    ) -> CapturedElement {
        let role = roleName(for: nil, traits: ax.traits)
        let label = ax.label ?? viewProbe.flatMap { ($0.view as? UILabel)?.text }
        let identifier = ax.identifier
        let displayName = displayName(role: role, label: label, identifier: identifier)
        let anchorView = viewProbe?.view ?? root
        let path = buildPath(view: anchorView)

        return CapturedElement(
            displayName: displayName,
            elementPath: path,
            role: role,
            contentDescription: ax.label,
            text: label,
            testTag: identifier,
            stateDescription: ax.value,
            bounds: ax.frameInWindow,
            nearbyElements: collectNearby(view: anchorView),
            nearbyText: collectNearbyText(view: anchorView),
            composableName: hostingControllerName(for: anchorView),
            sourceFile: resolveSourceFile(for: anchorView)
        )
    }

    // MARK: Source attribution (3-tier)

    private static func resolveSourceFile(for view: UIView) -> String? {
        if let info = JellySourceRegistry.shared.nearestSource(forAncestorsOf: view) {
            return info.formatted()
        }
        // Walk responder chain for any UIViewController with a tag.
        var responder: UIResponder? = view
        while let r = responder {
            if let vc = r as? UIViewController, let tag = vc.jellySourceFormatted {
                return tag
            }
            responder = r.next
        }
        return HostSourceDetector.shared.installSite?.formatted()
    }

    /// Tier-2: SwiftUI view-type name from the nearest `UIHostingController`.
    private static func hostingControllerName(for view: UIView) -> String? {
        var responder: UIResponder? = view
        while let r = responder {
            if let vc = r as? UIViewController {
                let typeName = String(reflecting: type(of: vc))
                // Trim the boilerplate `_TtGC...UIHostingController...` prefix:
                // SwiftUI generates `UIHostingController<Root>` so the user-readable
                // type is the generic argument. Use mirror introspection.
                if typeName.contains("UIHostingController") {
                    let mirror = Mirror(reflecting: vc)
                    if let rootView = mirror.children.first(where: { $0.label == "rootView" })?.value {
                        return String(reflecting: type(of: rootView))
                    }
                }
                if !typeName.contains("Jelly") {
                    return typeName
                }
            }
            responder = r.next
        }
        return nil
    }

    // MARK: Display name + path

    private static func displayName(role: String, label: String?, identifier: String?) -> String {
        if let label, !label.isEmpty {
            return "\(role) \"\(label.prefix(40))\""
        }
        if let identifier, !identifier.isEmpty {
            return "\(role) #\(identifier)"
        }
        return role
    }

    private static func buildPath(view: UIView) -> String {
        var segments: [String] = []
        var current: UIView? = view
        while let v = current {
            segments.append(segmentName(for: v))
            current = v.superview
        }
        let ordered = Array(segments.reversed())
        var collapsed: [String] = []
        var skipping = false
        let generic: Set<String> = [
            "UIView", "UIWindow", "UITransitionView", "UIDropShadowView",
            "_UIHostingView", "_UILayoutContainerView", "UILayoutContainerView",
            "UIScrollView", "_UIScrollViewBackgroundView",
        ]
        for seg in ordered {
            // Trim the leading-underscore prefix from generated SwiftUI types.
            if generic.contains(where: { seg == $0 || seg.hasPrefix("\($0)#") || seg.hasPrefix("\($0)[") })
                || seg.hasPrefix("_TtGC") {
                if !skipping {
                    collapsed.append("…")
                    skipping = true
                }
            } else {
                skipping = false
                collapsed.append(seg)
            }
        }
        return collapsed.joined(separator: " > ")
    }

    private static func segmentName(for view: UIView) -> String {
        let cls = String(describing: type(of: view))
        let identifier = view.accessibilityIdentifier?.nilIfEmpty()
        let text = (view as? UILabel)?.text?.trimmingCharacters(in: .whitespacesAndNewlines).truncatedToFirst(24).nilIfEmpty()
            ?? (view as? UIButton)?.titleLabel?.text?.truncatedToFirst(24).nilIfEmpty()
        let label = view.accessibilityLabel?.truncatedToFirst(24).nilIfEmpty()
        if let text { return "\(cls)[\"\(text)\"]" }
        if let label { return "\(cls)[\"\(label)\"]" }
        if let identifier { return "\(cls)#\(identifier)" }
        return cls
    }

    // MARK: Role naming

    private static func roleName(for view: UIView?, traits: UIAccessibilityTraits?) -> String {
        if let traits = traits {
            if traits.contains(.button)        { return "Button" }
            if traits.contains(.link)          { return "Link" }
            if traits.contains(.header)        { return "Header" }
            if traits.contains(.image)         { return "Image" }
            if traits.contains(.searchField)   { return "SearchField" }
            if traits.contains(.staticText)    { return "Text" }
            if traits.contains(.adjustable)    { return "Adjustable" }
            if traits.contains(.tabBar)        { return "TabBar" }
            if traits.contains(.keyboardKey)   { return "Key" }
        }
        if let view = view {
            switch view {
            case is UIButton: return "Button"
            case is UISwitch: return "Switch"
            case is UISlider: return "Slider"
            case is UIStepper: return "Stepper"
            case is UITextField: return "TextField"
            case is UITextView: return "TextView"
            case is UIImageView: return "Image"
            case is UILabel: return "Text"
            case is UITableViewCell: return "Cell"
            case is UICollectionViewCell: return "Cell"
            case is UIScrollView: return "Scroll"
            default:
                let n = String(describing: type(of: view))
                if n.hasPrefix("UI") { return String(n.dropFirst(2)) }
                return n
            }
        }
        return "Element"
    }

    // MARK: Helpers

    private static func firstDescendantLabel(_ view: UIView, depth: Int = 0) -> String? {
        if depth > 6 { return nil }
        for child in view.subviews {
            if let label = (child as? UILabel)?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
                return label
            }
            if let title = (child as? UIButton)?.titleLabel?.text, !title.isEmpty {
                return title
            }
            if let nested = firstDescendantLabel(child, depth: depth + 1) {
                return nested
            }
        }
        return nil
    }

    private static func collectNearby(view: UIView) -> String? {
        guard let parent = view.superview else { return nil }
        let labels = parent.subviews
            .filter { $0 !== view }
            .prefix(4)
            .map { segmentName(for: $0) }
        return labels.isEmpty ? nil : labels.joined(separator: ", ")
    }

    // MARK: Diagnostics

    private static func logProbes(
        pointInWindow: CGPoint,
        root: UIView,
        viewProbe: UIViewProbe.Result?,
        axProbe: AccessibilityProbe.Result?,
        layerProbe: CALayerProbe.Result?
    ) {
        let p = "(\(Int(pointInWindow.x)), \(Int(pointInWindow.y)))"
        print("[Jelly] ──── capture at \(p) ────")
        if let win = root.window {
            print("[Jelly]   host window: \(type(of: win)) frame=\(fmt(win.bounds)) level=\(win.windowLevel.rawValue) hidden=\(win.isHidden)")
            print("[Jelly]   rootVC: \(win.rootViewController.map { String(describing: type(of: $0)) } ?? "nil")")
            print("[Jelly]   root view: \(type(of: root)) frame=\(fmt(root.convert(root.bounds, to: nil))) subviews=\(root.subviews.count)")
            print("[Jelly]   root.accessibilityElements: \(root.accessibilityElements.map { "[\($0.count) entries]" } ?? "nil") isAccessibilityElement=\(root.isAccessibilityElement)")
            for (i, sub) in root.subviews.enumerated() {
                let f = sub.convert(sub.bounds, to: nil)
                let cls = String(describing: type(of: sub))
                let inside = f.contains(pointInWindow) ? "✓" : "✗"
                print("[Jelly]     subview[\(i)] \(inside) \(cls) frame=\(fmt(f)) hidden=\(sub.isHidden) alpha=\(sub.alpha) ax=\(sub.accessibilityElements?.count ?? -1)")
            }
        }
        // Walk every UIView at the press point and dump it — so we can see
        // exactly where the walk dead-ends, whether layers carry deeper
        // content, and how many accessibility elements (if any) live deep
        // in the subtree.
        print("[Jelly]   ── deep view walk at point ──")
        dumpViewTree(root, point: pointInWindow, depth: 0, maxDepth: 16)
        if let v = viewProbe {
            let cls = String(describing: type(of: v.view))
            let label = (v.view as? UILabel)?.text
                ?? (v.view as? UIButton)?.titleLabel?.text
                ?? v.view.accessibilityLabel
            let extra = label.map { " \"\($0)\"" } ?? ""
            print("[Jelly]   UIViewProbe → \(cls)\(extra) frame=\(fmt(v.frameInWindow)) area=\(Int(v.frameInWindow.area))")
        } else {
            print("[Jelly]   UIViewProbe → nil")
        }
        if let a = axProbe {
            let label = a.label ?? a.identifier ?? "?"
            print("[Jelly]   AccessibilityProbe → \"\(label)\" traits=\(traitsDescription(a.traits)) frame=\(fmt(a.frameInWindow)) area=\(Int(a.frameInWindow.area))")
        } else {
            print("[Jelly]   AccessibilityProbe → nil")
        }
        if let l = layerProbe {
            print("[Jelly]   CALayerProbe → \(l.layerClass) kind=\(l.kind) frame=\(fmt(l.frameInWindow)) area=\(Int(l.frameInWindow.area))")
        } else {
            print("[Jelly]   CALayerProbe → nil")
        }
        let all = AccessibilityProbe.allMatches(in: root, pointInWindow: pointInWindow)
        print("[Jelly]   AX candidates at point (\(all.count)):")
        for (i, candidate) in all.sorted(by: { $0.frameInWindow.area < $1.frameInWindow.area }).enumerated() {
            let label = candidate.label ?? candidate.identifier ?? "—"
            print("[Jelly]     [\(i)] \"\(label)\" traits=\(traitsDescription(candidate.traits)) frame=\(fmt(candidate.frameInWindow)) area=\(Int(candidate.frameInWindow.area))")
        }
    }

    private static func dumpViewTree(_ view: UIView, point: CGPoint, depth: Int, maxDepth: Int) {
        guard depth <= maxDepth else { return }
        let frame = view.convert(view.bounds, to: nil)
        guard frame.contains(point) else { return }
        let cls = String(describing: type(of: view))
        var label = ""
        if let t = (view as? UILabel)?.text, !t.isEmpty {
            label = "\"\(t.prefix(30))\""
        } else if let t = (view as? UIButton)?.titleLabel?.text, !t.isEmpty {
            label = "\"\(t.prefix(30))\""
        } else if let t = view.accessibilityLabel, !t.isEmpty {
            label = "ax:\"\(t.prefix(30))\""
        }
        var layerInfo = ""
        if let sublayers = view.layer.sublayers {
            let withContents = sublayers.filter { $0.contents != nil }.count
            layerInfo = " layers=\(sublayers.count) (with-contents=\(withContents))"
        }
        let pad = String(repeating: "  ", count: depth)
        print("[Jelly]   \(pad)└─ \(cls) \(label) frame=\(fmt(frame))\(layerInfo) ax=\(view.accessibilityElements?.count ?? -1) isAxEl=\(view.isAccessibilityElement)")
        for sub in view.subviews {
            dumpViewTree(sub, point: point, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    private static func fmt(_ r: CGRect) -> String {
        "(\(Int(r.origin.x)), \(Int(r.origin.y)), \(Int(r.width))×\(Int(r.height)))"
    }

    private static func traitsDescription(_ traits: UIAccessibilityTraits) -> String {
        var names: [String] = []
        if traits.contains(.button)      { names.append("button") }
        if traits.contains(.link)        { names.append("link") }
        if traits.contains(.header)      { names.append("header") }
        if traits.contains(.image)       { names.append("image") }
        if traits.contains(.searchField) { names.append("searchField") }
        if traits.contains(.staticText)  { names.append("staticText") }
        if traits.contains(.adjustable)  { names.append("adjustable") }
        if traits.contains(.tabBar)      { names.append("tabBar") }
        if traits.contains(.keyboardKey) { names.append("keyboardKey") }
        if traits.contains(.selected)    { names.append("selected") }
        return names.isEmpty ? "—" : names.joined(separator: "|")
    }

    private static func collectNearbyText(view: UIView) -> String? {
        guard let parent = view.superview else { return nil }
        var labels: [String] = []
        for sibling in parent.subviews where sibling !== view {
            let text = (sibling as? UILabel)?.text
                ?? sibling.accessibilityLabel
                ?? firstDescendantLabel(sibling)
            if let text, !text.isEmpty { labels.append(String(text.prefix(40))) }
            if labels.count >= 6 { break }
        }
        return labels.isEmpty ? nil : labels.joined(separator: ", ")
    }
}

private extension Optional where Wrapped == String {
    func nilIfEmpty() -> String? {
        guard let self = self, !self.isEmpty else { return nil }
        return self
    }
}

private extension String {
    func nilIfEmpty() -> String? { isEmpty ? nil : self }
    func truncatedToFirst(_ n: Int) -> String {
        count <= n ? self : String(prefix(n))
    }
}
#endif
