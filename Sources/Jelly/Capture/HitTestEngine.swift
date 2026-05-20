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

        // Pick the tighter winner — same arbitration as Android's
        // `shouldPreferSlot`. Accessibility hits usually carry a real
        // semantic label, so prefer them unless the view-probe found a
        // strictly-tighter bound.
        let preferAx: Bool = {
            guard let ax = axProbe else { return false }
            guard let v = viewProbe else { return true }
            // Both probes hit. Use accessibility unless the view probe is
            // tighter by ≥1.6× (the same heuristic Android uses).
            let viewArea = v.frameInWindow.area
            let axArea = ax.frameInWindow.area
            if viewArea < 1 || axArea < 1 { return true }
            return axArea / viewArea < 1.6
        }()

        if preferAx, let ax = axProbe {
            return buildFromAccessibility(ax: ax, viewProbe: viewProbe, root: root)
        }
        if let v = viewProbe {
            return buildFromView(view: v.view, frame: v.frameInWindow, ax: axProbe)
        }
        if let ax = axProbe {
            return buildFromAccessibility(ax: ax, viewProbe: nil, root: root)
        }
        return nil
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
