import Foundation

/// Mirrors `OutputDetailLevel` in `package/src/utils/generate-output.ts:7-15`
/// and `dev.jelly.output.DetailLevel` (jelly-android).
public enum JellyDetailLevel: String, Codable, Sendable, CaseIterable {
    /// Element + source file + comment only.
    case compact
    /// Adds elementPath + composable hierarchy.
    case standard
    /// Adds classes/testTag + position + nearby context.
    case detailed
    /// Adds full path, accessibility, computed styles, environment.
    case forensic
}
