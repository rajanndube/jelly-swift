import SwiftUI

/// Mirrors `dev.jelly.ui.AnnotationMarker` — the numbered dot that sits at
/// the centre of a saved annotation's bounding box.
struct AnnotationMarker: View {
    let number: Int
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(accent)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)

            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
        }
    }
}
