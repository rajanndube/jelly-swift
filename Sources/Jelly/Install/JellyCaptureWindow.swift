#if canImport(UIKit)
import UIKit

/// Capture-overlay window. Renders saved annotation markers, the live hover
/// rectangle while the user long-presses, the popup, and the review screen
/// / settings sheet. Sits at `.statusBar - 1` so it's above the host app
/// content but below the toolbar window (`.alert + 1`).
///
/// Hit-test passes through unless any UI is active that needs to receive
/// touches: annotateMode (long-press capture), the pending capture popup,
/// the settings sheet, or the review screen. Doing this at the window
/// level (rather than toggling `isUserInteractionEnabled`) avoids a
/// one-runloop-tick race where Combine-driven updates would lag the sheet
/// presentation.
final class JellyCaptureWindow: UIWindow, JellyOverlayMarking {

    weak var state: JellyOverlayState?

    init(windowScene: UIWindowScene, state: JellyOverlayState) {
        self.state = state
        super.init(windowScene: windowScene)
        windowLevel = .statusBar - 1
        backgroundColor = .clear
        isOpaque = false
        isHidden = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let state else { return nil }
        let needsTouches = state.annotateMode
            || state.pending != nil
            || state.settingsOpen
            || state.reviewOpen
        guard needsTouches else { return nil }
        let hit = super.hitTest(point, with: event)
        if hit === self { return nil }
        return hit
    }
}
#endif
