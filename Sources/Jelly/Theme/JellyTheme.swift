import SwiftUI

/// Mirrors `dev.jelly.theme.JellyTheme`. The SDK overlay UI always renders
/// dark — modern devtool aesthetic (Linear / Vercel / Raycast) — regardless
/// of the host app's color scheme. The host's `content()` is rendered
/// outside this theme wrapper, so its own appearance is preserved.
public enum JellyTheme {
    // Zinc palette, hex values match Android byte-for-byte.
    public static let background      = Color(red: 0x09 / 255, green: 0x09 / 255, blue: 0x0B / 255) // zinc-950
    public static let surface         = Color(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255) // zinc-900
    public static let surfaceVariant  = Color(red: 0x27 / 255, green: 0x27 / 255, blue: 0x2A / 255) // zinc-800
    public static let surfaceHigh     = Color(red: 0x3F / 255, green: 0x3F / 255, blue: 0x46 / 255) // zinc-700

    public static let onBackground       = Color(red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255) // zinc-50
    public static let onSurface          = Color(red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255)
    public static let onSurfaceVariant   = Color(red: 0xA1 / 255, green: 0xA1 / 255, blue: 0xAA / 255) // zinc-400

    public static let outline        = Color(red: 0x52 / 255, green: 0x52 / 255, blue: 0x5B / 255) // zinc-600
    public static let outlineVariant = Color(red: 0x2E / 255, green: 0x2E / 255, blue: 0x32 / 255) // subtle

    public static let error    = Color(red: 0xF8 / 255, green: 0x71 / 255, blue: 0x71 / 255) // red-400
    public static let onError  = Color(red: 0x09 / 255, green: 0x09 / 255, blue: 0x0B / 255)
}

/// Wraps `content` in the SDK's forced-dark theme. Apply only to overlay UI
/// — never to host content.
public struct JellyThemed<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder _ content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .preferredColorScheme(.dark)
            .environment(\.colorScheme, .dark)
            .tint(JellyTheme.onSurface)
    }
}
