import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Mirrors `dev.jelly.theme.AccentColor` (jelly-android) — same hex values
/// across both platforms so QA gets visual parity.
public enum JellyAccentColor: String, Codable, Sendable, CaseIterable {
    case indigo
    case blue
    case cyan
    case green
    case yellow
    case orange
    case red

    /// Hex value matching the Android AccentColor enum.
    public var hex: UInt32 {
        switch self {
        case .indigo: return 0x6366F1
        case .blue:   return 0x3B82F6
        case .cyan:   return 0x06B6D4
        case .green:  return 0x10B981
        case .yellow: return 0xEAB308
        case .orange: return 0xF97316
        case .red:    return 0xEF4444
        }
    }

    public var color: Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255.0,
              green: Double((hex >> 8) & 0xFF) / 255.0,
              blue: Double(hex & 0xFF) / 255.0)
    }

    #if canImport(UIKit)
    public var uiColor: UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
    #endif
}
