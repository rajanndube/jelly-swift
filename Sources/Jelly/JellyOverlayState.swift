import Foundation
import Combine
import CoreGraphics

/// Mirrors `dev.jelly.JellyOverlayState`. Shared mutable state between the
/// **capture overlay** (markers / modal / popup / settings / review) and
/// the **toolbar overlay** (the FAB on its own UIWindow). Both overlays
/// observe this single instance so a tap on the FAB still flips
/// `annotateMode` for the capture overlay, etc.
@MainActor
public final class JellyOverlayState: ObservableObject {
    @Published public var annotateMode: Bool = false
    @Published public var settingsOpen: Bool = false
    @Published public var reviewOpen: Bool = false
    @Published public var capturing: Bool = false
    @Published public var pending: PendingCapture?
    @Published public var liveHover: CapturedElement?
    @Published public var activeSessionId: String?
    /// The endpoint URL string the cached `activeSessionId` was created
    /// against. When the user pastes a different URL (e.g. after the
    /// browser viewer refreshes and rotates its room token), we drop
    /// the cached session and create a new one in the new room.
    @Published public var activeSessionEndpoint: String?

    /// Insets from the trailing edge / bottom edge of the safe area,
    /// in points. Updated as the user drags the FAB. Persisted across
    /// scenes within a session; default = 20 / 20 (anchored bottom-right).
    @Published public var fabTrailingInset: CGFloat = 20
    @Published public var fabBottomInset: CGFloat = 20

    public init() {}
}

public struct PendingCapture: Equatable, Identifiable {
    public let id: String
    public let captured: CapturedElement
    public let pointInWindow: CGPoint
    public let screenshotPath: String?
    /// The host window's `screen.scale` at capture time. Required to
    /// reload the saved screenshot with the right `UIImage.scale` so that
    /// `image.size` reports in points (matching `captured.bounds`) rather
    /// than pixels.
    public let imageScale: CGFloat

    public init(
        id: String,
        captured: CapturedElement,
        pointInWindow: CGPoint,
        screenshotPath: String?,
        imageScale: CGFloat
    ) {
        self.id = id
        self.captured = captured
        self.pointInWindow = pointInWindow
        self.screenshotPath = screenshotPath
        self.imageScale = imageScale
    }
}
