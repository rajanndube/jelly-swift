import SwiftUI

/// Mirrors `dev.jelly.theme.JellyMotion` — named easing curves and timing
/// constants used across the Jelly overlay UI. Centralized so the whole
/// SDK has a coherent feel.
///
/// Storyboard:
///
///       0ms   user presses something
///     100ms   press feedback completes (scale 0.97)
///     180ms   tooltip / chip entrance
///     220ms   popup scale + fade in (anchored to trigger)
///     320ms   bottom sheet slide up
///
/// Stagger between cards in lists: 50ms.
/// Press feedback uses a slow press (160ms) and fast release (120ms) — slow
/// where the user is deciding, fast where the system is responding.
public enum JellyMotion {

    public static let pressDownMs = 160
    public static let pressUpMs = 120
    public static let chipMs = 180
    public static let popupMs = 220
    public static let sheetMs = 320
    public static let staggerStepMs = 50

    public static func pressDown() -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: Double(pressDownMs) / 1000.0)
    }

    public static func pressUp() -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: Double(pressUpMs) / 1000.0)
    }

    public static func popup() -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: Double(popupMs) / 1000.0)
    }

    public static func chip() -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: Double(chipMs) / 1000.0)
    }

    public static func sheet() -> Animation {
        .timingCurve(0.32, 0.72, 0, 1, duration: Double(sheetMs) / 1000.0)
    }
}
