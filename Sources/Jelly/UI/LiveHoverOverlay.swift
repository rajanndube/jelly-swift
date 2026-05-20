import SwiftUI

/// Mirrors `dev.jelly.ui.LiveHoverOverlay` — drawn while the user is
/// long-pressing in annotate mode. Outlines the currently-targeted
/// element with a stroke + tinted fill and a label chip.
struct LiveHoverOverlay: View {
    let bounds: CGRect
    let label: String
    let accent: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(accent.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(accent, lineWidth: 2.5)
                )
                .frame(width: bounds.width, height: bounds.height)
                .position(x: bounds.midX, y: bounds.midY)

            HoverLabel(label: label, accent: accent)
                .position(
                    x: bounds.minX + min(bounds.width / 2, 100),
                    y: max(bounds.minY - 14, 14)
                )
        }
        .ignoresSafeArea()
    }
}

private struct HoverLabel: View {
    let label: String
    let accent: Color

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(accent)
            )
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
