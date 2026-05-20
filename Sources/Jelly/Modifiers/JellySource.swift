#if canImport(UIKit)
import SwiftUI
import UIKit

/// Mirrors Android's `Modifier.jellySource(file, line)`. Tag a SwiftUI
/// view with `(file, line)` source coordinates so any annotation captured
/// inside it picks up that source via the ancestor walk in
/// `JellySourceRegistry`. The compiler captures `#fileID` / `#line` at
/// the call site, so values are correct without runtime stack walking.
///
/// Usage:
/// ```swift
/// struct LoginScreen: View {
///     var body: some View {
///         VStack { ... }
///             .jellySource()  // captures the call-site of `.jellySource()`
///     }
/// }
/// ```
public extension View {
    func jellySource(file: StaticString = #fileID, line: UInt = #line) -> some View {
        self.background(
            JellySourceMarker(source: JellySourceInfo(file: "\(file)", line: Int(line)))
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }
}

/// Invisible `UIViewRepresentable` that registers itself with
/// `JellySourceRegistry` for ancestor lookup at hit-test time. The
/// underlying `UIView` is zero-frame, non-hit-testing, and accessibility-
/// hidden so it never appears in the host app's UI or accessibility tree.
private struct JellySourceMarker: UIViewRepresentable {
    let source: JellySourceInfo

    func makeUIView(context: Context) -> JellySourceMarkerView {
        let view = JellySourceMarkerView(source: source)
        return view
    }

    func updateUIView(_ uiView: JellySourceMarkerView, context: Context) {
        uiView.update(source: source)
    }
}

final class JellySourceMarkerView: UIView {
    private(set) var source: JellySourceInfo

    init(source: JellySourceInfo) {
        self.source = source
        super.init(frame: .zero)
        isHidden = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(source: JellySourceInfo) {
        self.source = source
        if let parent = superview {
            JellySourceRegistry.shared.tag(parent, with: source)
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if let parent = superview {
            JellySourceRegistry.shared.tag(parent, with: source)
        }
    }

    override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        if let old = superview {
            JellySourceRegistry.shared.untag(old)
        }
    }
}
#endif
