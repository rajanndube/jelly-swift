import Foundation
import Combine

/// User-mutable settings (detail level, accent color, sync prefs) persisted to
/// the SDK's private `UserDefaults` suite. Mirrors
/// `dev.jelly.storage.SettingsStore` and the localStorage settings keys in
/// the web version (`outputDetail`, `annotationColorId`, etc.).
public struct JellySettings: Codable, Equatable, Sendable {
    public var detailLevel: JellyDetailLevel
    public var accentColor: JellyAccentColor
    public var syncEnabled: Bool
    public var endpoint: String?
    public var webhookUrl: String?

    public init(
        detailLevel: JellyDetailLevel = .standard,
        accentColor: JellyAccentColor = .indigo,
        syncEnabled: Bool = false,
        endpoint: String? = nil,
        webhookUrl: String? = nil
    ) {
        self.detailLevel = detailLevel
        self.accentColor = accentColor
        self.syncEnabled = syncEnabled
        self.endpoint = endpoint
        self.webhookUrl = webhookUrl
    }
}

public final class SettingsStore: ObservableObject {

    private enum Keys {
        static let detailLevel = "settings.detailLevel"
        static let accentColor = "settings.accentColor"
        static let syncEnabled = "settings.syncEnabled"
        static let endpoint    = "settings.endpoint"
        static let webhookUrl  = "settings.webhookUrl"
    }

    private let defaults: UserDefaults

    @Published public private(set) var settings: JellySettings

    public init(suiteName: String = AnnotationStore.suiteName) {
        let store = UserDefaults(suiteName: suiteName) ?? .standard
        self.defaults = store
        self.settings = SettingsStore.read(from: store)
    }

    public func update(_ transform: (inout JellySettings) -> Void) {
        var next = settings
        transform(&next)
        write(next)
        settings = next
    }

    public func replace(_ next: JellySettings) {
        write(next)
        settings = next
    }

    private func write(_ next: JellySettings) {
        defaults.set(next.detailLevel.rawValue, forKey: Keys.detailLevel)
        defaults.set(next.accentColor.rawValue, forKey: Keys.accentColor)
        defaults.set(next.syncEnabled, forKey: Keys.syncEnabled)
        if let endpoint = next.endpoint, !endpoint.isEmpty {
            defaults.set(endpoint, forKey: Keys.endpoint)
        } else {
            defaults.removeObject(forKey: Keys.endpoint)
        }
        if let webhook = next.webhookUrl, !webhook.isEmpty {
            defaults.set(webhook, forKey: Keys.webhookUrl)
        } else {
            defaults.removeObject(forKey: Keys.webhookUrl)
        }
    }

    private static func read(from defaults: UserDefaults) -> JellySettings {
        let detail = (defaults.string(forKey: Keys.detailLevel)
            .flatMap(JellyDetailLevel.init(rawValue:))) ?? .standard
        let accent = (defaults.string(forKey: Keys.accentColor)
            .flatMap(JellyAccentColor.init(rawValue:))) ?? .indigo
        let syncEnabled = defaults.bool(forKey: Keys.syncEnabled)
        let endpoint = defaults.string(forKey: Keys.endpoint)
        let webhook = defaults.string(forKey: Keys.webhookUrl)
        return JellySettings(
            detailLevel: detail,
            accentColor: accent,
            syncEnabled: syncEnabled,
            endpoint: endpoint,
            webhookUrl: webhook
        )
    }
}
