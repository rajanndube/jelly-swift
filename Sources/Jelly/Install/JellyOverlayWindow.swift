#if canImport(UIKit)
import UIKit

/// Hosts the toolbar / FAB. Mirrors Android's `TYPE_APPLICATION_PANEL`
/// window — but `windowLevel = .alert + 1` is strictly better than the
/// Android workaround: it sits above SwiftUI `.sheet` and `.fullScreenCover`
/// (both presented inside the host window's responder chain) without any
/// focus-bumper hack.
///
/// `hitTest` overridden to filter out hits to the window itself (transparent
/// area) so taps outside the FAB pass through to the host app's window.
/// Heavy lifting (refusing hits in empty SwiftUI space) is done by
/// `PassthroughContainerView.point(inside:)`, which only accepts hits that
/// land inside a real subview — so an intrinsic-sized SwiftUI FAB pinned
/// bottom-right becomes naturally pass-through everywhere else.
final class JellyOverlayWindow: UIWindow, JellyOverlayMarking {

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = .alert + 1
        backgroundColor = .clear
        isOpaque = false
        isHidden = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        // Filter out the window itself — never claim a touch on transparent
        // window background; let it fall through to the host app window.
        if hit === self { return nil }
        return hit
    }
}
#endif
