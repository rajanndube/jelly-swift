import SwiftUI

/// Mirrors `dev.jelly.ui.AnnotationToolbar` — the FAB pill. Compact when
/// inactive (just the pin), expands to show List / Settings / Close
/// buttons when active.
struct AnnotationToolbar: View {
    let annotateMode: Bool
    let annotationCount: Int
    let accent: Color
    /// True when the FAB is anchored to the right edge of the screen
    /// (the pin chip touches the right edge). The pin chip is then
    /// rendered last in the HStack so it stays on the right and the
    /// action buttons appear to its left, expanding inward into the
    /// viewport. When false (FAB on left edge) the pin renders first
    /// and buttons appear to its right.
    var pinnedToRight: Bool = true
    var onTogglePin: () -> Void
    var onOpenReview: () -> Void
    var onSettings: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if pinnedToRight {
                actionButtons
                pinChip
            } else {
                pinChip
                actionButtons
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(JellyTheme.surface)
                .overlay(Capsule().stroke(JellyTheme.outlineVariant, lineWidth: 1))
        )
        .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
        .animation(JellyMotion.popup(), value: annotateMode)
    }

    private var pinChip: some View {
        PinChip(
            annotateMode: annotateMode,
            annotationCount: annotationCount,
            accent: accent,
            action: onTogglePin
        )
    }

    @ViewBuilder
    private var actionButtons: some View {
        if annotateMode {
            IconButton(systemName: "list.bullet", action: onOpenReview)
            IconButton(systemName: "gearshape", action: onSettings)
            IconButton(systemName: "xmark", action: onClose)
        }
    }
}

private struct PinChip: View {
    let annotateMode: Bool
    let annotationCount: Int
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(annotateMode ? accent : JellyTheme.surfaceVariant)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle().stroke(JellyTheme.outlineVariant, lineWidth: 1)
                    )
                Image(systemName: "mappin")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(annotateMode ? .white : JellyTheme.onSurface)

                if annotationCount > 0 {
                    Text(annotationCount > 9 ? "9+" : "\(annotationCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(accent))
                        .overlay(Circle().stroke(JellyTheme.surface, lineWidth: 2))
                        .offset(x: 14, y: -14)
                }
            }
        }
        .buttonStyle(.plain)
        .pressable(scale: 0.92)
    }
}

private struct IconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(JellyTheme.surfaceVariant)
                    .frame(width: 40, height: 40)
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(JellyTheme.onSurface)
            }
        }
        .buttonStyle(.plain)
        .pressable(scale: 0.9)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}
