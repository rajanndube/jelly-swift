#if canImport(UIKit)
import SwiftUI
import UIKit
import Combine
import UniformTypeIdentifiers

/// SwiftUI content of the **capture window**. Mirrors the relevant slice of
/// `dev.jelly.JellyOverlayContent` — saved markers, the long-press capture
/// gesture, the live-hover overlay, the popup, the settings sheet, and the
/// review screen.
struct JellyCaptureOverlayView: View {
    @ObservedObject var state: JellyOverlayState
    @ObservedObject var settingsStore: SettingsStore
    let store: AnnotationStore
    let config: JellyConfig
    /// The window we're capturing into — used to source-host hit-tests
    /// when the user long-presses.
    let hostWindow: () -> UIWindow?
    let overlayWindows: () -> [UIWindow]

    @State private var annotations: [Annotation] = []
    @State private var screenKey: String = "default"
    @State private var catchUpStatus = CatchUpSyncStatus()
    private let cancellableBag = CancellableBag()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Saved annotation markers — drawn over content, never block taps.
                if !state.capturing {
                    ForEach(Array(annotations.enumerated()), id: \.element.id) { index, annotation in
                        if let box = annotation.boundingBox {
                            AnnotationMarker(number: index + 1, accent: settingsStore.settings.accentColor.color)
                                .position(x: CGFloat(box.x + box.width / 2),
                                          y: CGFloat(box.y + box.height / 2))
                        }
                    }
                }

                // Capture-mode touch surface — only enabled in annotate mode.
                if state.annotateMode, state.pending == nil, !state.capturing {
                    CaptureTouchSurface(state: state, hostWindow: hostWindow, store: store, settingsStore: settingsStore, config: config, screenKey: $screenKey, overlayWindows: overlayWindows)
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                // Live-hover stroke + label.
                if state.annotateMode, !state.capturing, let hover = state.liveHover {
                    LiveHoverOverlay(
                        bounds: hover.bounds,
                        label: hover.displayName,
                        accent: settingsStore.settings.accentColor.color
                    )
                }
            }
            .onAppear { resolveScreenKey(); subscribe() }
            // Heartbeat to /hello so the local-sync viewer can show
            // device identity + liveness ("iPhone 17 Pro · iOS 26 —
            // connected") instead of a generic "listening" label. Tied
            // to (syncEnabled, endpoint) so it auto-cancels when the
            // user toggles sync off or pastes a different URL. 12s
            // cadence: the browser's active "is the device still
            // alive?" probe waits 15s for any response and the passive
            // 18s threshold flips the dot from green to yellow — 12s
            // leaves a 3s safety margin and tolerates one missed ping.
            .task(id: heartbeatKey) {
                guard settingsStore.settings.syncEnabled,
                      let urlString = settingsStore.settings.endpoint,
                      let url = URL(string: urlString) else { return }
                let api = JellyAPI(baseURL: url)
                let info = Self.makeDeviceInfo()
                while !Task.isCancelled {
                    try? await api.sayHello(info)
                    try? await Task.sleep(nanoseconds: 12_000_000_000)
                }
            }
            // Native bottom-sheet for the capture popup. Driven by the
            // PendingCapture identity (.sheet(item:)), so each capture
            // presents a fresh sheet and tapping the sheet's handle / drag
            // dismiss cleans up via onDismiss.
            .sheet(item: Binding(
                get: { state.pending },
                set: { state.pending = $0 }
            ), onDismiss: { state.liveHover = nil }) { pending in
                JellyThemed {
                    AnnotationPopup(
                        captured: pending.captured,
                        screenshotPath: pending.screenshotPath,
                        imageScale: pending.imageScale,
                        accent: settingsStore.settings.accentColor.color,
                        onCancel: {
                            if let path = JellyScreenshot.resolve(storedPath: pending.screenshotPath) {
                                try? FileManager.default.removeItem(atPath: path)
                            }
                            state.pending = nil
                        },
                        onSubmit: { submission in
                            Task { @MainActor in
                                await submitAnnotation(pending: pending, submission: submission)
                            }
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $state.settingsOpen, onDismiss: {
                catchUpStatus.lastResult = nil
            }) {
                JellyThemed {
                    SettingsSheet(
                        settings: Binding(
                            get: { settingsStore.settings },
                            set: { settingsStore.replace($0) }
                        ),
                        onDismiss: { state.settingsOpen = false },
                        catchUpStatus: catchUpStatus,
                        onPushPending: { performCatchUpSync() }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .onAppear { recomputePendingCount() }
                    .onChange(of: annotations) { _ in recomputePendingCount() }
                }
            }
            .fullScreenCover(isPresented: $state.reviewOpen) {
                JellyThemed {
                    AnnotationsScreen(
                        annotations: annotations,
                        accent: settingsStore.settings.accentColor.color,
                        onDismiss: { state.reviewOpen = false },
                        onCopyAll: { copyAll() },
                        buildShareAll: { buildShareItems(annotations: annotations) },
                        onClearAll: { clearAll() },
                        onDeleteOne: { deleteOne($0) },
                        buildShareOne: { buildShareItems(annotations: [$0]) }
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func resolveScreenKey() {
        if let configured = config.screenKey {
            screenKey = configured
        } else if let topVC = topViewController() {
            screenKey = String(describing: type(of: topVC))
        } else {
            screenKey = "default"
        }
    }

    private func subscribe() {
        store.observe(screenKey: screenKey)
            .receive(on: DispatchQueue.main)
            .sink { annotations = $0 }
            .store(in: cancellableBag)
    }

    @MainActor
    private func submitAnnotation(pending: PendingCapture, submission: PopupSubmission) async {
        let viewportWidth = Int(hostWindow()?.bounds.width ?? 0)
        let bakedPath: String? = {
            // Resolve the raw capture path through the screenshot
            // directory in case the absolute path on the pending
            // capture is from a previous container UUID.
            guard let raw = JellyScreenshot.resolve(storedPath: pending.screenshotPath) else { return nil }
            // Application Support so the file survives app restarts and
            // iOS storage-pressure purges — see `JellyScreenshot.imageDirectory`.
            let baked = JellyScreenshot.imageDirectory()
                .appendingPathComponent("\(pending.id)-baked.jpg")
            let result = AnnotatedScreenshot.bake(
                rawPath: raw,
                bounds: BoundingBox(pending.captured.bounds),
                accent: settingsStore.settings.accentColor.uiColor,
                caption: AnnotatedScreenshot.CaptionFields(
                    elementName: pending.captured.displayName,
                    elementPath: pending.captured.elementPath,
                    sourceFile: pending.captured.sourceFile,
                    comment: submission.comment,
                    intent: submission.intent?.rawValue,
                    severity: submission.severity?.rawValue
                ),
                outFile: baked,
                imageScale: pending.imageScale
            )
            if result != nil {
                try? FileManager.default.removeItem(atPath: raw)
            }
            return result ?? raw
        }()

        let annotation = buildAnnotation(
            id: pending.id,
            captured: pending.captured,
            pointInWindow: pending.pointInWindow,
            submission: submission,
            screenKey: screenKey,
            viewportWidth: viewportWidth,
            screenshotPath: bakedPath
        )

        // Optimistic local persistence first so the UI is responsive even
        // if the network is slow.
        var updated = annotations
        updated.append(annotation)
        store.save(screenKey: screenKey, annotations: updated)
        state.pending = nil

        // Best-effort sync.
        if settingsStore.settings.syncEnabled,
           let urlString = settingsStore.settings.endpoint,
           let url = URL(string: urlString) {
            // Use the user-pasted URL verbatim as the API base. For the
            // jelly-local-sync browser viewer that's `http://host:port/r/<token>`
            // — the `/r/<token>` is the room namespace and the standard
            // /sessions/... and /annotations/.../image paths are appended
            // underneath it.
            let baseURL = resolveBaseURL(url)
            let api = JellyAPI(baseURL: baseURL)
            // Refresh the cached session if the URL has rotated.
            resetSessionIfEndpointChanged(baseURL.absoluteString)
            do {
                let sessionId: String
                if let existing = state.activeSessionId {
                    sessionId = existing
                } else {
                    sessionId = try await api.createSession(url: "screen:\(screenKey)").id
                    print("[Jelly] sync: created session \(sessionId) at \(baseURL.absoluteString)")
                }
                state.activeSessionId = sessionId
                var withSession = annotation
                withSession.sessionId = sessionId
                let synced = try await api.syncAnnotation(sessionId: sessionId, annotation: withSession)
                var withSynced = synced
                withSynced.syncedTo = sessionId
                let final = updated.map { $0.id == annotation.id ? withSynced : $0 }
                store.save(screenKey: screenKey, annotations: final)
                print("[Jelly] sync: posted annotation \(synced.id) to \(baseURL.absoluteString)")

                // Upload the baked screenshot bytes so a paired browser
                // viewer can render the image alongside the markdown.
                // Mirrors the Android `uploadAnnotationImage` step.
                // Wrapped in do/catch so older servers (no endpoint, 404)
                // don't break the rest of sync.
                if let path = bakedPath,
                   let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                    let contentType = path.lowercased().hasSuffix(".webp")
                        ? "image/webp"
                        : path.lowercased().hasSuffix(".png")
                            ? "image/png"
                            : "image/jpeg"
                    do {
                        try await api.uploadAnnotationImage(
                            annotationId: synced.id,
                            bytes: data,
                            contentType: contentType
                        )
                        print("[Jelly] sync: uploaded image (\(data.count) bytes) for \(synced.id)")
                    } catch {
                        print("[Jelly] sync: image upload skipped (\(error.localizedDescription)) — server may not implement /annotations/{id}/image")
                    }
                }
            } catch {
                print("[Jelly] sync FAILED at \(baseURL.absoluteString): \(error.localizedDescription)")
                if let urlError = error as? URLError {
                    print("[Jelly] sync URLError code: \(urlError.code.rawValue) — \(urlError.code)")
                }
            }
        }
    }

    /// Resolves the base URL for the JellyAPI client. The user-pasted
    /// URL is used as-is — `/r/<token>` (room namespace) is preserved
    /// in the path so the standard `/sessions/...` and
    /// `/annotations/.../image` paths get appended underneath it.
    /// See `jelly-local-sync/README.md` for the wire contract.
    private func resolveBaseURL(_ url: URL) -> URL { url }

    /// If the configured endpoint changed since `activeSessionId` was
    /// minted (e.g. the browser viewer refreshed and rotated its room
    /// token), drop the cached session so we create a fresh one inside
    /// the new room. Additionally, when transitioning between two
    /// non-empty endpoints (i.e. the user explicitly changed URLs
    /// mid-session), invalidate the `syncedTo` flag on every stored
    /// annotation — the new room's session is empty and the phone's
    /// "this is synced" claim is no longer true. The transition from
    /// nil → endpoint at app launch is excluded: the server may still
    /// hold the data from a previous run, so a forced re-push there
    /// would be redundant.
    private func resetSessionIfEndpointChanged(_ endpoint: String) {
        let previous = state.activeSessionEndpoint
        guard previous != endpoint else { return }
        state.activeSessionId = nil
        state.activeSessionEndpoint = endpoint
        if let previous, !previous.isEmpty, !endpoint.isEmpty {
            invalidateAllSyncFlags(reason: "endpoint changed from \(previous) to \(endpoint)")
        }
    }

    /// Walks every stored screen key and clears `syncedTo` on every
    /// annotation. Called when we detect the endpoint URL has rotated
    /// — the phone's previous "synced" claims point at a session that
    /// no longer exists on the (new) server, so they must be treated
    /// as pending again. Annotations themselves stay on the phone;
    /// only the sync flag is cleared.
    private func invalidateAllSyncFlags(reason: String) {
        let all = store.enumerateAll()
        var cleared = 0
        for (key, anns) in all {
            let touched = anns.contains { $0.syncedTo != nil }
            guard touched else { continue }
            let updated = anns.map { ann -> Annotation in
                var copy = ann
                copy.syncedTo = nil
                return copy
            }
            store.save(screenKey: key, annotations: updated)
            cleared += anns.filter { $0.syncedTo != nil }.count
        }
        if cleared > 0 {
            print("[Jelly] sync: invalidated \(cleared) syncedTo flag(s) — \(reason)")
        }
    }

    /// Identity used by the `.task(id:)` heartbeat — when this changes
    /// (sync turned off / on, endpoint URL changed) the running task is
    /// cancelled and a fresh one starts against the new config.
    private var heartbeatKey: String {
        let on = settingsStore.settings.syncEnabled ? "1" : "0"
        return "\(on)|\(settingsStore.settings.endpoint ?? "")"
    }

    /// Builds the `DeviceInfo` payload for the `/hello` heartbeat.
    /// Static so we only read `UIDevice` / `Bundle.main` once per task.
    private static func makeDeviceInfo() -> DeviceInfo {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
        return DeviceInfo(
            platform: "ios",
            // Machine identifier ("iPhone17,1") is more useful than
            // UIDevice.current.model ("iPhone") for the viewer to
            // surface — the server can map it to a marketing name.
            model: machine.isEmpty ? UIDevice.current.model : machine,
            manufacturer: "Apple",
            osVersion: UIDevice.current.systemVersion,
            appName: appName,
            sdkVersion: nil
        )
    }

    /// Recomputes `catchUpStatus.pendingCount` by enumerating every
    /// stored screen key and counting annotations with `syncedTo == nil`.
    /// Run when the settings sheet opens and after each push completes.
    private func recomputePendingCount() {
        let pending = store.enumerateAll().values.reduce(0) { acc, list in
            acc + list.filter { $0.syncedTo == nil }.count
        }
        catchUpStatus.pendingCount = pending
    }

    /// Tap handler for the catch-up sync button. Runs the verify-and-push
    /// pipeline (`pushUnsyncedAnnotations` queries the server first, then
    /// pushes only annotations the server doesn't already have) and
    /// updates `catchUpStatus` so the sheet renders progress + result.
    private func performCatchUpSync() {
        guard !catchUpStatus.isPushing else { return }
        guard settingsStore.settings.syncEnabled,
              let urlString = settingsStore.settings.endpoint,
              let url = URL(string: urlString) else { return }
        catchUpStatus.isPushing = true
        catchUpStatus.lastResult = nil
        Task { @MainActor in
            let api = JellyAPI(baseURL: resolveBaseURL(url))
            let result = await pushUnsyncedAnnotations(store: store, api: api)
            let totalLocal = store.enumerateAll().values.reduce(0) { $0 + $1.count }
            let msg: String
            switch (result.attempted, result.synced, result.failed, result.skipped) {
            case (0, 0, 0, 0):
                msg = totalLocal == 0
                    ? "Nothing to sync."
                    : "Couldn't reach endpoint."
            case (_, _, _, _) where result.synced == 0 && result.failed > 0 && result.skipped == 0:
                msg = "Couldn't reach endpoint — \(result.failed) failed."
            case (_, _, 0, _) where result.attempted == 0:
                msg = "All \(result.skipped) already on server."
            case (_, _, 0, 0):
                msg = "Pushed \(result.synced) of \(result.attempted)."
            case (_, _, 0, _):
                msg = "Pushed \(result.synced), \(result.skipped) already on server."
            default:
                msg = "Pushed \(result.synced), \(result.failed) failed, \(result.skipped) already on server."
            }
            recomputePendingCount()
            catchUpStatus.isPushing = false
            catchUpStatus.lastResult = msg
            print("[Jelly] catchUp: \(msg)")
        }
    }

    private func copyAll() {
        let md = OutputGenerator(
            viewportWidth: Int(hostWindow()?.bounds.width ?? 0),
            viewportHeight: Int(hostWindow()?.bounds.height ?? 0)
        ).generate(annotations: annotations, screenKey: screenKey, detailLevel: settingsStore.settings.detailLevel)
        UIPasteboard.general.string = md
    }

    private func deleteOne(_ annotation: Annotation) {
        if let path = JellyScreenshot.resolve(storedPath: annotation.screenshotPath) {
            try? FileManager.default.removeItem(atPath: path)
        }
        let updated = annotations.filter { $0.id != annotation.id }
        store.save(screenKey: screenKey, annotations: updated)
    }

    private func clearAll() {
        for a in annotations {
            if let path = JellyScreenshot.resolve(storedPath: a.screenshotPath) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        store.save(screenKey: screenKey, annotations: [])
    }

    /// Returns activity items (markdown + screenshot images) for the
    /// given annotations. Used by the share sheet inside `AnnotationsScreen`.
    private func buildShareItems(annotations subset: [Annotation]) -> [Any] {
        let md = OutputGenerator(
            viewportWidth: Int(hostWindow()?.bounds.width ?? 0),
            viewportHeight: Int(hostWindow()?.bounds.height ?? 0)
        ).generate(annotations: subset, screenKey: screenKey, detailLevel: settingsStore.settings.detailLevel)
        var items: [Any] = [md]
        for a in subset {
            if let path = JellyScreenshot.resolve(storedPath: a.screenshotPath),
               let img = UIImage(contentsOfFile: path) {
                items.append(img)
            }
        }
        return items
    }

    private func topViewController() -> UIViewController? {
        guard let window = hostWindow() else { return nil }
        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Captures the long-press gesture and runs the hit-test on touch-up.
private struct CaptureTouchSurface: UIViewRepresentable {
    @ObservedObject var state: JellyOverlayState
    let hostWindow: () -> UIWindow?
    let store: AnnotationStore
    @ObservedObject var settingsStore: SettingsStore
    let config: JellyConfig
    @Binding var screenKey: String
    let overlayWindows: () -> [UIWindow]

    func makeUIView(context: Context) -> CaptureTouchView {
        let v = CaptureTouchView()
        v.onTouchBegan = { point, win in
            performHit(point, sourceWindow: win)
        }
        v.onTouchMoved = { point, win in
            performHit(point, sourceWindow: win)
        }
        v.onTouchEnded = { point, win in
            commitHit(point, sourceWindow: win)
        }
        v.onTouchCancelled = {
            state.liveHover = nil
        }
        v.backgroundColor = UIColor.black.withAlphaComponent(0.04)
        return v
    }

    func updateUIView(_ uiView: CaptureTouchView, context: Context) {}

    private func performHit(_ point: CGPoint, sourceWindow: UIWindow) {
        guard let host = hostWindow() else { return }
        let pointInHost = host.convert(point, from: sourceWindow)
        if let element = HitTestEngine.capture(in: host, pointInWindow: pointInHost, skippingWindows: overlayWindows()) {
            if state.liveHover != element {
                state.liveHover = element
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
            }
        }
    }

    private func commitHit(_ point: CGPoint, sourceWindow: UIWindow) {
        guard let host = hostWindow() else { return }
        let pointInHost = host.convert(point, from: sourceWindow)
        let element = state.liveHover ?? HitTestEngine.capture(in: host, pointInWindow: pointInHost, skippingWindows: overlayWindows())
        state.liveHover = nil
        guard let element else { return }

        let pendingId = UUID().uuidString
        Task { @MainActor in
            var screenshotPath: String?
            if config.captureScreenshots {
                state.capturing = true
                // Skip a runloop tick so SwiftUI removes the touch surface
                // before we capture.
                try? await Task.sleep(nanoseconds: 16_000_000)
                screenshotPath = JellyScreenshot.captureWindow(
                    annotationId: pendingId,
                    window: host,
                    excluding: overlayWindows()
                )
                state.capturing = false
            }
            state.pending = PendingCapture(
                id: pendingId,
                captured: element,
                pointInWindow: pointInHost,
                screenshotPath: screenshotPath,
                imageScale: host.screen.scale
            )
        }
    }
}

private final class CaptureTouchView: UIView {
    var onTouchBegan: ((CGPoint, UIWindow) -> Void)?
    var onTouchMoved: ((CGPoint, UIWindow) -> Void)?
    var onTouchEnded: ((CGPoint, UIWindow) -> Void)?
    var onTouchCancelled: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let win = self.window else { return }
        onTouchBegan?(t.location(in: nil), win)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let win = self.window else { return }
        onTouchMoved?(t.location(in: nil), win)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let win = self.window else { return }
        onTouchEnded?(t.location(in: nil), win)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouchCancelled?()
    }
}

private func buildAnnotation(
    id: String,
    captured: CapturedElement,
    pointInWindow: CGPoint,
    submission: PopupSubmission,
    screenKey: String,
    viewportWidth: Int,
    screenshotPath: String?
) -> Annotation {
    let accessibilityBits: String? = {
        var parts: [String] = []
        if let role = captured.role { parts.append("role=\(role)") }
        if let cd = captured.contentDescription { parts.append("contentDescription=\"\(cd)\"") }
        if let testTag = captured.testTag { parts.append("testTag=\(testTag)") }
        if let state = captured.stateDescription { parts.append("state=\(state)") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }()
    let xPercent: Float = viewportWidth > 0
        ? (Float(pointInWindow.x) / Float(viewportWidth)) * 100
        : 0

    return Annotation(
        id: id,
        x: xPercent,
        y: Float(pointInWindow.y),
        comment: submission.comment,
        element: captured.displayName,
        elementPath: captured.elementPath,
        timestamp: Int64(Date().timeIntervalSince1970 * 1000),
        boundingBox: BoundingBox(captured.bounds),
        nearbyText: captured.nearbyText,
        nearbyElements: captured.nearbyElements,
        accessibility: accessibilityBits,
        composableHierarchy: captured.composableName,
        sourceFile: captured.sourceFile,
        screenshotPath: screenshotPath,
        url: "screen:\(screenKey)",
        intent: submission.intent,
        severity: submission.severity
    )
}

/// Holds Combine cancellables for a SwiftUI struct.
private final class CancellableBag {
    var cancellables: Set<AnyCancellable> = []
}

private extension AnyCancellable {
    func store(in bag: CancellableBag) {
        bag.cancellables.insert(self)
    }
}
#endif
