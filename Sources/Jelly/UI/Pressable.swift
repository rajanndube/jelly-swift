import SwiftUI

/// Mirrors `dev.jelly.ui.Pressable.pressScale()` — scale-down on press
/// (160ms slow press) and scale-up on release (120ms fast release). The
/// asymmetry is intentional: slow where the user is deciding, fast where
/// the system is responding.
public struct PressableScale: ViewModifier {
    var scale: CGFloat
    @State private var isPressed = false

    public init(scale: CGFloat = 0.95) {
        self.scale = scale
    }

    public func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scale : 1.0)
            .animation(isPressed ? JellyMotion.pressDown() : JellyMotion.pressUp(), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

public extension View {
    func pressable(scale: CGFloat = 0.95) -> some View {
        modifier(PressableScale(scale: scale))
    }
}
