#if canImport(UIKit)
import SwiftUI
import UIKit
import Combine

/// Per-scene attachment of the toolbar + capture overlay windows. Mirrors
/// `dev.jelly.ActivityOverlayController` — except keyed by `UIWindowScene`
/// so iPad Stage Manager / multi-window works correctly. Each scene gets
/// its own pair of windows + its own `JellyOverlayState` so a long-press
/// in window A doesn't affect window B.
@MainActor
final class SceneOverlayController {

    private let config: JellyConfig
    private let store: AnnotationStore
    private var attachments: [ObjectIdentifier: SceneAttachment] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(config: JellyConfig) {
        self.config = config
        self.store = AnnotationStore()
        observe()
    }

    private func observe() {
        let center = NotificationCenter.default
        center.publisher(for: UIScene.didActivateNotification)
            .compactMap { $0.object as? UIWindowScene }
            .sink { [weak self] scene in self?.attachIfNeeded(to: scene) }
            .store(in: &cancellables)
        center.publisher(for: UIScene.didDisconnectNotification)
            .compactMap { $0.object as? UIWindowScene }
            .sink { [weak self] scene in self?.detach(from: scene) }
            .store(in: &cancellables)

        for scene in UIApplication.shared.connectedScenes {
            if let ws = scene as? UIWindowScene { attachIfNeeded(to: ws) }
        }
    }

    func detachAll() {
        for (_, attachment) in attachments {
            attachment.tearDown()
        }
        attachments.removeAll()
        cancellables.removeAll()
    }

    private func attachIfNeeded(to scene: UIWindowScene) {
        let key = ObjectIdentifier(scene)
        if attachments[key] != nil { return }
        let attachment = SceneAttachment(scene: scene, config: config, store: store)
        attachment.start()
        attachments[key] = attachment
    }

    private func detach(from scene: UIWindowScene) {
        let key = ObjectIdentifier(scene)
        attachments[key]?.tearDown()
        attachments.removeValue(forKey: key)
    }
}

@MainActor
private final class SceneAttachment {
    let scene: UIWindowScene
    let config: JellyConfig
    let store: AnnotationStore
    let state = JellyOverlayState()
    let settingsStore: SettingsStore
    private var toolbarWindow: JellyOverlayWindow?
    private var captureWindow: JellyCaptureWindow?
    /// One of these two is active at any moment. The trailing
    /// constraint pins the FAB's right edge (used when the FAB
    /// snaps to the screen's right edge — content expands LEFT
    /// into the viewport). The leading constraint pins the FAB's
    /// left edge (used when snapped to the left — content expands
    /// RIGHT into the viewport). Switching at snap time is what
    /// keeps the action buttons on-screen no matter which edge
    /// the FAB is parked at.
    private var trailingConstraint: NSLayoutConstraint?
    private var leadingConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?
    private weak var toolbarHostingView: UIView?
    private var fabPositionCancellables: Set<AnyCancellable> = []

    init(scene: UIWindowScene, config: JellyConfig, store: AnnotationStore) {
        self.scene = scene
        self.config = config
        self.store = store
        self.settingsStore = SettingsStore()
        // Seed initial settings from config the first time we install.
        if settingsStore.settings.endpoint == nil, let endpoint = config.endpoint {
            settingsStore.update {
                $0.endpoint = endpoint.absoluteString
                $0.syncEnabled = true
                $0.detailLevel = config.detailLevel
                $0.accentColor = config.accentColor
                $0.webhookUrl = config.webhookURL?.absoluteString
            }
        }
        if let sessionId = config.sessionId {
            state.activeSessionId = sessionId
        }
    }

    func start() {
        let toolbar = JellyOverlayWindow(windowScene: scene)
        let capture = JellyCaptureWindow(windowScene: scene, state: state)

        let captureHosting = UIHostingController(rootView: JellyCaptureOverlayView(
            state: state,
            settingsStore: settingsStore,
            store: store,
            config: config,
            hostWindow: { [weak self] in self?.findHostWindow() },
            overlayWindows: { [weak self] in self?.allOverlayWindows() ?? [] }
        ))
        captureHosting.view.backgroundColor = .clear
        capture.rootViewController = captureHosting

        // Toolbar: intrinsic-sized SwiftUI host pinned to the bottom-right of
        // a passthrough container. Critical that the hosting view is NOT
        // full-screen — full-screen would cause UIWindow.hitTest to treat
        // empty space as inside the SwiftUI host and break passthrough.
        // Drag closures capture self weakly so they can update Auto Layout
        // constraints directly during drag (no @Published churn = smooth).
        let toolbarHosting = UIHostingController(rootView: AnchoredFAB(
            state: state,
            settingsStore: settingsStore,
            store: store,
            onDragChanged: { [weak self] dx, dy in self?.handleDragChanged(dx: dx, dy: dy) },
            onDragEnded: { [weak self] in self?.handleDragEnded() }
        ))
        if #available(iOS 16.4, macCatalyst 16.4, visionOS 1.0, *) {
            toolbarHosting.sizingOptions = [.intrinsicContentSize]
        }
        toolbarHosting.view.backgroundColor = .clear
        toolbarHosting.view.translatesAutoresizingMaskIntoConstraints = false

        let toolbarContainer = PassthroughContainerView()
        toolbarContainer.backgroundColor = .clear
        toolbarContainer.addSubview(toolbarHosting.view)

        let toolbarVC = UIViewController()
        toolbarVC.view = toolbarContainer
        toolbarVC.view.backgroundColor = .clear
        toolbarVC.addChild(toolbarHosting)
        toolbarHosting.didMove(toParent: toolbarVC)

        let trailing = toolbarHosting.view.trailingAnchor.constraint(
            equalTo: toolbarContainer.safeAreaLayoutGuide.trailingAnchor,
            constant: -state.fabTrailingInset
        )
        let leading = toolbarHosting.view.leadingAnchor.constraint(
            equalTo: toolbarContainer.safeAreaLayoutGuide.leadingAnchor,
            constant: 20
        )
        let bottom = toolbarHosting.view.bottomAnchor.constraint(
            equalTo: toolbarContainer.safeAreaLayoutGuide.bottomAnchor,
            constant: -state.fabBottomInset
        )
        // Activate trailing initially; if the persisted state says we're
        // on the left side, switch to leading immediately (after layout)
        // so the FAB starts up with the right anchor for its position.
        NSLayoutConstraint.activate([trailing, bottom])
        self.trailingConstraint = trailing
        self.leadingConstraint = leading
        self.bottomConstraint = bottom
        self.toolbarHostingView = toolbarHosting.view

        toolbar.rootViewController = toolbarVC

        // If the FAB was on the left side last session, swap to the
        // leading-anchored constraint after the initial layout pass so
        // intrinsic widths are known. We measure midpoint against the
        // current scene width.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let screenW = self.scene.coordinateSpace.bounds.width
            let toolbarW = self.toolbarHostingView?.bounds.width ?? 60
            let mid = (screenW - toolbarW) / 2
            if self.state.fabTrailingInset > mid {
                self.activateLeadingSide(leadingInset: 20)
            }
        }

        // IMPORTANT: do NOT call makeKeyAndVisible() — that would steal focus
        // from the host app's window and break event delivery. The window is
        // already visible (init sets isHidden = false); we just need it on
        // screen, not key.
        toolbar.isHidden = false
        capture.isHidden = false

        self.toolbarWindow = toolbar
        self.captureWindow = capture

        // Capture window's hitTest reads state directly (synchronously) to
        // decide whether to pass through. No Combine binding needed.
    }

    func tearDown() {
        toolbarWindow?.isHidden = true
        captureWindow?.isHidden = true
        toolbarWindow = nil
        captureWindow = nil
        fabPositionCancellables.removeAll()
    }

    // MARK: - FAB drag

    private var dragStartTrailing: CGFloat?
    private var dragStartBottom: CGFloat?

    fileprivate func handleDragChanged(dx: CGFloat, dy: CGFloat) {
        if dragStartTrailing == nil {
            // Drag math always works in trailing-inset space. If the
            // FAB is currently anchored on the left (leading active),
            // swap to the trailing constraint with the equivalent
            // position before we start.
            ensureTrailingActiveForDrag()
            dragStartTrailing = -(trailingConstraint?.constant ?? 0)
        }
        if dragStartBottom == nil {
            dragStartBottom = -(bottomConstraint?.constant ?? 0)
        }
        guard let startT = dragStartTrailing, let startB = dragStartBottom else { return }
        // No clamping while the gesture is in flight. The FAB tracks
        // the finger one-to-one even past a screen edge; all boundary
        // correction happens once on release in `handleDragEnded`.
        trailingConstraint?.constant = -(startT - dx)
        bottomConstraint?.constant = -(startB - dy)
        toolbarWindow?.layoutIfNeeded()
    }

    fileprivate func handleDragEnded() {
        defer {
            dragStartTrailing = nil
            dragStartBottom = nil
        }
        let currentT = -(trailingConstraint?.constant ?? 0)
        let currentB = -(bottomConstraint?.constant ?? 0)
        let screenW = scene.coordinateSpace.bounds.width
        let screenH = scene.coordinateSpace.bounds.height
        let toolbarW: CGFloat = toolbarHostingView?.bounds.width ?? 60
        let toolbarH: CGFloat = toolbarHostingView?.bounds.height ?? 56

        // Snap X to whichever screen edge is closer.
        let mid = (screenW - toolbarW) / 2
        let goingRight = currentT < mid
        let snapT: CGFloat = goingRight ? 20 : max(20, screenW - toolbarW - 20)

        // Y stays where the user put it but is clamped to the visible
        // viewport.
        let minBottom: CGFloat = 20
        let maxBottom: CGFloat = max(minBottom, screenH - toolbarH - 20)
        let safeB = min(max(currentB, minBottom), maxBottom)

        // Atomically swap which constraint is active inside the spring
        // animation block. When going right, keep the trailing pin so
        // expanded content grows leftward. When going left, switch to
        // a leading pin so expanded content grows rightward.
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0) {
            if goingRight {
                self.activateTrailingSide(trailingInset: 20)
            } else {
                self.activateLeadingSide(leadingInset: 20)
            }
            self.bottomConstraint?.constant = -safeB
            self.toolbarWindow?.layoutIfNeeded()
        }

        // Persist snapped position. `fabTrailingInset` stays the
        // canonical representation regardless of which constraint
        // is currently active — `pinnedToRight` is derived from it.
        state.fabTrailingInset = snapT
        state.fabBottomInset = safeB
    }

    /// Swap to the trailing constraint at the equivalent screen
    /// position. No-op if trailing is already active.
    private func ensureTrailingActiveForDrag() {
        guard trailingConstraint?.isActive != true else { return }
        guard let containerWidth = toolbarHostingView?.superview?.bounds.width,
              let toolbarWidth = toolbarHostingView?.bounds.width,
              let leading = leadingConstraint else { return }
        // Compute equivalent trailing inset from the current leading inset.
        let leadingInset = leading.constant
        let equivalentTrailingInset = containerWidth - toolbarWidth - leadingInset
        leading.isActive = false
        trailingConstraint?.constant = -equivalentTrailingInset
        trailingConstraint?.isActive = true
    }

    /// Activate the trailing constraint with the given inset; deactivate leading.
    private func activateTrailingSide(trailingInset: CGFloat) {
        leadingConstraint?.isActive = false
        trailingConstraint?.constant = -trailingInset
        trailingConstraint?.isActive = true
    }

    /// Activate the leading constraint with the given inset; deactivate trailing.
    private func activateLeadingSide(leadingInset: CGFloat) {
        trailingConstraint?.isActive = false
        leadingConstraint?.constant = leadingInset
        leadingConstraint?.isActive = true
    }

    private func allOverlayWindows() -> [UIWindow] {
        [toolbarWindow, captureWindow].compactMap { $0 }
    }

    private func findHostWindow() -> UIWindow? {
        // Pick the largest .normal-level window that isn't a Jelly overlay.
        // .normal-level filters out our overlays (.alert+1 / .statusBar-1)
        // and system windows like remote keyboard / preview windows. Largest
        // frame gives us the actual host content rather than any auxiliary
        // sized-down window.
        let candidates = scene.windows.filter { w in
            !(w is JellyOverlayMarking)
                && !w.isHidden
                && w.windowLevel == .normal
        }
        if let largest = candidates.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) {
            return largest
        }
        // Fallback: any non-overlay window.
        return scene.windows.first { !($0 is JellyOverlayMarking) }
    }
}

/// SwiftUI FAB sized to its intrinsic content (just the pill). The
/// containing `UIHostingController.view` is intrinsic-sized via
/// `sizingOptions = [.intrinsicContentSize]` and pinned bottom-right by
/// Auto Layout in `SceneAttachment.start()`. Empty space outside the
/// FAB's actual frame is OUTSIDE this view's bounds and is therefore
/// passed through by `PassthroughContainerView.point(inside:)`.
private struct AnchoredFAB: View {
    @ObservedObject var state: JellyOverlayState
    @ObservedObject var settingsStore: SettingsStore
    let store: AnnotationStore
    /// Drag delta from gesture start (cumulative). The host updates Auto
    /// Layout constraints directly — no @Published churn.
    let onDragChanged: (CGFloat, CGFloat) -> Void
    let onDragEnded: () -> Void

    @State private var annotationCount: Int = 0
    @State private var screenKey: String = "default"
    /// First-sample translation captured on the gesture's first
    /// `.onChanged`. We send `value.translation - dragOrigin` to the
    /// host — that way the first call is a (0, 0) no-op instead of
    /// applying the `minimumDistance` threshold as a sudden 10pt
    /// position jump.
    @State private var dragOrigin: CGSize?
    private let cancellableBag = ToolbarCancellableBag()

    var body: some View {
        if state.capturing || state.pending != nil {
            // Hide while capturing so the toolbar never bakes into the
            // screenshot, and while the popup is open so the FAB doesn't
            // float over the comment form.
            EmptyView()
        } else {
            JellyThemed {
                AnnotationToolbar(
                    annotateMode: state.annotateMode,
                    annotationCount: annotationCount,
                    accent: settingsStore.settings.accentColor.color,
                    // The pin chip should always be the segment of the
                    // pill closest to the screen edge, so the action
                    // buttons grow inward into the visible viewport
                    // rather than off-screen. Heuristic: if the trailing
                    // inset is in the smaller half of the screen width,
                    // the FAB is sitting on the right side.
                    pinnedToRight: state.fabTrailingInset
                        < (UIScreen.main.bounds.width - 60) / 2,
                    onTogglePin: { state.annotateMode.toggle() },
                    onOpenReview: { state.reviewOpen = true },
                    onSettings: { state.settingsOpen = true },
                    onClose: { state.annotateMode = false }
                )
                // simultaneousGesture lets the drag coexist with the
                // child Button taps. minimumDistance: 10 gives buttons
                // priority on quick taps; sustained drags after 10pt of
                // travel start moving the FAB. We rebase the translation
                // off the FIRST sample so that the threshold doesn't
                // arrive as a sudden 10pt jump on the FAB's position.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            let origin = dragOrigin ?? value.translation
                            if dragOrigin == nil { dragOrigin = origin }
                            let dx = value.translation.width - origin.width
                            let dy = value.translation.height - origin.height
                            onDragChanged(dx, dy)
                        }
                        .onEnded { _ in
                            dragOrigin = nil
                            onDragEnded()
                        }
                )
            }
            .onAppear { resolveScreenKey(); subscribe() }
        }
    }

    private func resolveScreenKey() {
        // Best effort — read from any UIWindowScene's top VC.
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for w in ws.windows where !(w is JellyOverlayMarking) {
                var top = w.rootViewController
                while let p = top?.presentedViewController { top = p }
                if let top = top {
                    screenKey = String(describing: type(of: top))
                    return
                }
            }
        }
    }

    private func subscribe() {
        store.observe(screenKey: screenKey)
            .receive(on: DispatchQueue.main)
            .sink { annotationCount = $0.count }
            .store(in: cancellableBag)
    }
}

private final class ToolbarCancellableBag {
    var cancellables: Set<AnyCancellable> = []
}

private extension AnyCancellable {
    func store(in bag: ToolbarCancellableBag) {
        bag.cancellables.insert(self)
    }
}

/// `UIView` that returns true from `point(inside:)` only when one of its
/// subviews actually contains the point. Hosts the intrinsic-sized
/// SwiftUI FAB; empty space outside the FAB's frame returns false and the
/// `JellyOverlayWindow` passes the touch through to the host app.
private final class PassthroughContainerView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for sub in subviews where !sub.isHidden && sub.alpha > 0.01 {
            let local = convert(point, to: sub)
            if sub.point(inside: local, with: event) { return true }
        }
        return false
    }
}
#endif
