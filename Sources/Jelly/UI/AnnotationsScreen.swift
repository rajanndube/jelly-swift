import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Mirrors `dev.jelly.ui.AnnotationsScreen` — review screen showing all
/// saved annotations with their baked screenshots, copy/share/clear
/// actions, and per-annotation delete.
struct AnnotationsScreen: View {
    let annotations: [Annotation]
    let accent: Color
    var onDismiss: () -> Void
    var onCopyAll: () -> Void
    /// Returns the share items (markdown + images) for "share all".
    var buildShareAll: () -> [Any]
    var onClearAll: () -> Void
    var onDeleteOne: (Annotation) -> Void
    /// Returns the share items for a single annotation.
    var buildShareOne: (Annotation) -> [Any]

    @State private var sharePayload: SharePayload?
    @State private var showClearAllConfirmation: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if annotations.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(annotations.enumerated()), id: \.element.id) { index, annotation in
                            AnnotationCard(
                                number: index + 1,
                                annotation: annotation,
                                accent: accent,
                                onShare: { sharePayload = SharePayload(items: buildShareOne(annotation)) },
                                onDelete: { onDeleteOne(annotation) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(JellyTheme.background.ignoresSafeArea())
        // Destructive confirmation before wiping every annotation —
        // clear-all is irreversible (annotations + their baked images
        // are removed from local storage), so iOS-standard alert with
        // a destructive Delete action.
        .alert("Delete all annotations?", isPresented: $showClearAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete all", role: .destructive) { onClearAll() }
        } message: {
            Text("Are you sure you want to delete all the annotations? This action is not reversible.")
        }
        // Native share sheet — presented from inside this view's modal
        // stack so it sits on top of the AnnotationsScreen rather than
        // behind it (which is what `topVC.present(activity)` from a
        // different window would do).
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(JellyTheme.onSurface)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(JellyTheme.surfaceVariant))
            }
            .buttonStyle(.plain)

            Text("Annotations")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(JellyTheme.onSurface)

            Text("\(annotations.count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(accent))

            Spacer()

            ActionPill(systemName: "doc.on.doc", action: onCopyAll)
            ActionPill(systemName: "square.and.arrow.up", action: {
                sharePayload = SharePayload(items: buildShareAll())
            })
            ActionPill(systemName: "trash", tint: JellyTheme.error) {
                showClearAllConfirmation = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(JellyTheme.surface)
        .overlay(Rectangle().frame(height: 1).foregroundColor(JellyTheme.outlineVariant), alignment: .bottom)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(JellyTheme.onSurfaceVariant)
            Text("No annotations yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(JellyTheme.onSurfaceVariant)
            Text("Long-press any element while annotate mode is on.")
                .font(.system(size: 12))
                .foregroundColor(JellyTheme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}

private struct AnnotationCard: View {
    let number: Int
    let annotation: Annotation
    let accent: Color
    var onShare: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(accent).frame(width: 36, height: 36)
                    Text("\(number)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(annotation.element)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(JellyTheme.onSurface)
                        .lineLimit(2)
                    Text(annotation.elementPath)
                        .font(.system(size: 11))
                        .foregroundColor(JellyTheme.onSurfaceVariant)
                        .lineLimit(2)
                    if let source = annotation.sourceFile {
                        Text(source)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(JellyTheme.onSurfaceVariant.opacity(0.8))
                    }
                }

                Spacer()
            }

            #if canImport(UIKit)
            // Resolve through the screenshot directory — the stored
            // absolute path may be from a previous install with a
            // different container UUID; the file lives at the same
            // basename under the current install's imageDirectory().
            if let path = JellyScreenshot.resolve(storedPath: annotation.screenshotPath),
               let uiImg = UIImage(contentsOfFile: path) {
                Image(uiImage: uiImg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(JellyTheme.outlineVariant, lineWidth: 1))
            }
            #endif

            Text(annotation.comment)
                .font(.system(size: 13))
                .foregroundColor(JellyTheme.onSurface)

            HStack(spacing: 6) {
                if let intent = annotation.intent {
                    Tag(text: intent.rawValue, accent: accent)
                }
                if let severity = annotation.severity {
                    Tag(text: severity.rawValue, accent: accent)
                }
                if annotation.syncedTo != nil {
                    Tag(text: "synced", accent: JellyTheme.outline)
                }
                Spacer()
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13))
                        .foregroundColor(JellyTheme.onSurfaceVariant)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(JellyTheme.surfaceVariant))
                }
                .buttonStyle(.plain)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(JellyTheme.error)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(JellyTheme.surfaceVariant))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(JellyTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(JellyTheme.outlineVariant, lineWidth: 1))
        )
    }
}

private struct Tag: View {
    let text: String
    let accent: Color
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(accent.opacity(0.15)))
    }
}

private struct ActionPill: View {
    let systemName: String
    var tint: Color = JellyTheme.onSurface
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(JellyTheme.surfaceVariant))
        }
        .buttonStyle(.plain)
    }
}

/// Identifiable wrapper so we can drive `.sheet(item:)` with arbitrary
/// activity items.
struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// SwiftUI wrapper around `UIActivityViewController`. Presented via
/// `.sheet(item:)` from inside `AnnotationsScreen` so the share sheet
/// rides the same modal stack as the screen and lands ON TOP, not behind.
#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
