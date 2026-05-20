#if canImport(UIKit)
import UIKit

/// Accessibility-tree probe. Mirrors the *semantic* half of Compose's
/// `SemanticsCapture` — the meaningful semantic layer for SwiftUI-rendered
/// content, since SwiftUI's render tree is private.
///
/// For pure-SwiftUI screens the deepest UIView is usually a generic
/// `_UIHostingView` with no useful labels of its own. The accessibility
/// elements published by SwiftUI carry `accessibilityLabel`,
/// `accessibilityIdentifier`, traits (button / staticText / link / image
/// / etc.), and frames in window coords — exactly the semantic data we
/// need. This probe walks `accessibilityElements` recursively, collects
/// every element whose frame contains the press point, and picks the
/// smallest-area winner.
@MainActor
enum AccessibilityProbe {

    struct Result {
        let label: String?
        let identifier: String?
        let traits: UIAccessibilityTraits
        let value: String?
        let frameInWindow: CGRect
    }

    static func bestMatch(in root: UIView, pointInWindow: CGPoint) -> Result? {
        var best: Result?
        walk(root, pointInWindow: pointInWindow) { candidate in
            if best == nil || candidate.frameInWindow.area < best!.frameInWindow.area {
                best = candidate
            }
        }
        return best
    }

    private static func walk(
        _ object: NSObject,
        pointInWindow: CGPoint,
        emit: (Result) -> Void
    ) {
        // Pull frame in screen / window coords.
        var elementFrame: CGRect = .zero
        if let view = object as? UIView {
            elementFrame = view.convert(view.bounds, to: nil)
        } else {
            elementFrame = object.accessibilityFrame
        }

        let containsPoint = !elementFrame.isEmpty && elementFrame.contains(pointInWindow)
        let isElement = object.isAccessibilityElement
        let label = (object.accessibilityLabel?.isEmpty == false) ? object.accessibilityLabel : nil
        let identifier: String? = {
            // accessibilityIdentifier lives on UIView and UIAccessibilityElement.
            // NSObject conforms informally — bridge through a shared @objc protocol.
            if let identified = object as? AXIdentified, let id = identified.accessibilityIdentifier, !id.isEmpty {
                return id
            }
            return nil
        }()
        let traits = object.accessibilityTraits
        let value = (object.accessibilityValue?.isEmpty == false) ? object.accessibilityValue : nil

        // Don't require `isAccessibilityElement` here — SwiftUI publishes
        // its semantic tree at the host view level via `accessibilityElements`
        // (UIAccessibilityElement instances). Those are valid hits even when
        // the parent UIView itself isn't flagged as an element.
        if containsPoint, (label != nil || identifier != nil || traits != .none || isElement) {
            emit(.init(
                label: label,
                identifier: identifier,
                traits: traits,
                value: value,
                frameInWindow: elementFrame
            ))
        }

        // Recurse into accessibility children. Apple's UIAccessibilityContainer
        // is an informal protocol on NSObject — bridge through our @objc
        // protocol with optional selectors so we can call them safely.
        if let container = object as? AXContainer {
            if let count = container.accessibilityElementCount?(), count > 0 {
                for i in 0..<count {
                    if let child = container.accessibilityElement?(at: i) as? NSObject {
                        walk(child, pointInWindow: pointInWindow, emit: emit)
                    }
                }
            }
        }
        if let elements = object.accessibilityElements as? [NSObject] {
            for child in elements {
                walk(child, pointInWindow: pointInWindow, emit: emit)
            }
        }
        if let view = object as? UIView, view.accessibilityElements == nil {
            for sub in view.subviews { walk(sub, pointInWindow: pointInWindow, emit: emit) }
        }
    }
}

extension CGRect {
    var area: CGFloat { width * height }
}

/// Bridge for UIAccessibilityContainer's informal selectors.
@objc private protocol AXContainer {
    @objc optional func accessibilityElementCount() -> Int
    @objc optional func accessibilityElement(at index: Int) -> Any?
}

/// Bridge for accessibilityIdentifier (UIView + UIAccessibilityElement both
/// expose it through the UIAccessibilityIdentification protocol; NSObject
/// doesn't, so we cast through this).
@objc private protocol AXIdentified {
    @objc var accessibilityIdentifier: String? { get }
}
#endif
