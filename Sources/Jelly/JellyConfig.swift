import Foundation

/// Mirrors `dev.jelly.JellyConfig`.
public struct JellyConfig: Sendable {
    public var detailLevel: JellyDetailLevel
    public var accentColor: JellyAccentColor
    public var endpoint: URL?
    public var sessionId: String?
    public var webhookURL: URL?
    public var copyToClipboard: Bool
    public var captureScreenshots: Bool
    /// Identifier for the current screen. Used as the storage key so each
    /// screen has its own annotation list. Defaults to the top view
    /// controller's class name when nil.
    public var screenKey: String?

    public init(
        detailLevel: JellyDetailLevel = .standard,
        accentColor: JellyAccentColor = .indigo,
        endpoint: URL? = nil,
        sessionId: String? = nil,
        webhookURL: URL? = nil,
        copyToClipboard: Bool = true,
        captureScreenshots: Bool = true,
        screenKey: String? = nil
    ) {
        self.detailLevel = detailLevel
        self.accentColor = accentColor
        self.endpoint = endpoint
        self.sessionId = sessionId
        self.webhookURL = webhookURL
        self.copyToClipboard = copyToClipboard
        self.captureScreenshots = captureScreenshots
        self.screenKey = screenKey
    }
}
