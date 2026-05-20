import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Mirrors `dev.jelly.ui.AnnotationPopup`. Native iOS sheet content for
/// the capture popup: `NavigationStack` + `ScrollView` content, with
/// Cancel / Add as `.topBarLeading` / `.topBarTrailing` toolbar items so
/// the action buttons stay pinned to the top regardless of the sheet
/// detent or scroll position. Comment / intent / severity scroll
/// underneath the toolbar.
struct AnnotationPopup: View {
    let captured: CapturedElement
    let screenshotPath: String?
    /// Screen scale at capture time. Used to reload the saved JPEG with
    /// the right `UIImage.scale` so `image.size` reports in points
    /// (matching `captured.bounds`). Without this we'd be mixing pixels
    /// and points and the stroke would land off the actual element.
    let imageScale: CGFloat
    let accent: Color
    var onCancel: () -> Void
    var onSubmit: (PopupSubmission) -> Void

    @State private var comment: String = ""
    @State private var intent: AnnotationIntent?
    @State private var severity: AnnotationSeverity?

    /// Window-coord bounds (points) of the captured element.
    private var captureBounds: CGRect { captured.bounds }

    private var canSubmit: Bool {
        !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    elementHeader
                    if let screenshotPath {
                        screenshotPreview(path: screenshotPath)
                    }
                    commentField
                    chipGroup(
                        title: "Intent",
                        options: AnnotationIntent.allCases,
                        selection: $intent,
                        label: { $0.label }
                    )
                    chipGroup(
                        title: "Severity",
                        options: AnnotationSeverity.allCases,
                        selection: $severity,
                        label: { $0.label }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .navigationTitle("Add annotation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        onSubmit(PopupSubmission(
                            comment: comment,
                            intent: intent,
                            severity: severity
                        ))
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSubmit)
                }
            }
            .scrollContentBackground(.hidden)
            .background(JellyTheme.background)
        }
        .tint(accent)
    }

    private var elementHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(captured.displayName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(JellyTheme.onSurface)
                .lineLimit(2)
            Text(captured.elementPath)
                .font(.system(size: 12))
                .foregroundColor(JellyTheme.onSurfaceVariant)
                .lineLimit(2)
            if let source = captured.sourceFile {
                Text(source)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(JellyTheme.onSurfaceVariant.opacity(0.8))
            }
        }
    }

    @ViewBuilder
    private func screenshotPreview(path stored: String) -> some View {
        #if canImport(UIKit)
        // Resolve through the screenshot directory in case the absolute
        // path baked into the annotation is from a previous install
        // (different container UUID) and is no longer valid here.
        if let resolved = JellyScreenshot.resolve(storedPath: stored),
           let cg = UIImage(contentsOfFile: resolved)?.cgImage {
            // Reload with the original screen scale so `img.size` is in
            // points (matches `captureBounds`), not pixels.
            let img = UIImage(cgImage: cg, scale: imageScale, orientation: .up)
            // Compute rendered dimensions explicitly so the stroke overlay
            // can be pinned to the exact same rect.
            GeometryReader { geo in
                let aspectH = img.size.width > 0 ? img.size.height / img.size.width : 1
                let maxH: CGFloat = 200
                let scaledH = min(maxH, geo.size.width * aspectH)
                let scaledW = aspectH > 0 ? scaledH / aspectH : geo.size.width
                let scale = img.size.width > 0 ? scaledW / img.size.width : 1

                ZStack(alignment: .topLeading) {
                    Image(uiImage: img)
                        .resizable()
                        .frame(width: scaledW, height: scaledH)
                    if captureBounds.width > 0, captureBounds.height > 0 {
                        // Outset the stroke so it sits *outside* the captured
                        // bounds — never paints over the content the QA is
                        // commenting on. Matches AnnotatedScreenshot.bake.
                        let lineWidth: CGFloat = 2.5
                        let cornerRadius: CGFloat = 6
                        RoundedRectangle(cornerRadius: cornerRadius + lineWidth / 2)
                            .stroke(accent, lineWidth: lineWidth)
                            .frame(
                                width: captureBounds.width * scale + lineWidth,
                                height: captureBounds.height * scale + lineWidth
                            )
                            .offset(
                                x: captureBounds.minX * scale - lineWidth / 2,
                                y: captureBounds.minY * scale - lineWidth / 2
                            )
                    }
                }
                .frame(width: scaledW, height: scaledH)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(JellyTheme.outlineVariant, lineWidth: 1)
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: 200)
        }
        #endif
    }

    private var commentField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Comment")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(JellyTheme.onSurfaceVariant)

            TextEditor(text: $comment)
                .font(.system(size: 14))
                .foregroundColor(JellyTheme.onSurface)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(JellyTheme.surfaceVariant)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(comment.isEmpty ? JellyTheme.outlineVariant : accent.opacity(0.6), lineWidth: 1)
                )
        }
    }

    private func chipGroup<Option: Hashable>(
        title: String,
        options: [Option],
        selection: Binding<Option?>,
        label: @escaping (Option) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(JellyTheme.onSurfaceVariant)
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { opt in
                    Chip(
                        text: label(opt),
                        selected: selection.wrappedValue == opt,
                        accent: accent
                    ) {
                        if selection.wrappedValue == opt {
                            selection.wrappedValue = nil
                        } else {
                            selection.wrappedValue = opt
                        }
                    }
                }
            }
        }
    }
}

private struct Chip: View {
    let text: String
    let selected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(selected ? accent : JellyTheme.onSurface)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? accent.opacity(0.18) : JellyTheme.surfaceVariant)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(selected ? accent : JellyTheme.outlineVariant, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .pressable(scale: 0.95)
    }
}

public struct PopupSubmission: Equatable {
    public let comment: String
    public let intent: AnnotationIntent?
    public let severity: AnnotationSeverity?
}

private extension AnnotationIntent {
    var label: String {
        switch self {
        case .fix: return "Fix"
        case .change: return "Change"
        case .question: return "Question"
        case .approve: return "Approve"
        }
    }
}

private extension AnnotationSeverity {
    var label: String {
        switch self {
        case .blocking: return "Blocking"
        case .important: return "Important"
        case .suggestion: return "Suggestion"
        }
    }
}
