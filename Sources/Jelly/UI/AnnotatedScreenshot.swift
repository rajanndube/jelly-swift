#if canImport(UIKit)
import UIKit

/// Mirrors `dev.jelly.capture.BakedImage` — composites the annotation's
/// bounding-box stroke + caption strip onto the raw screenshot. Used so
/// the saved file is self-contained: any agent / human reading the
/// screenshot sees the highlighted element and the comment without
/// needing the JSON sidecar.
@MainActor
public enum AnnotatedScreenshot {

    public struct CaptionFields {
        public let elementName: String
        public let elementPath: String?
        public let sourceFile: String?
        public let comment: String
        public let intent: String?
        public let severity: String?

        public init(
            elementName: String,
            elementPath: String?,
            sourceFile: String?,
            comment: String,
            intent: String?,
            severity: String?
        ) {
            self.elementName = elementName
            self.elementPath = elementPath
            self.sourceFile = sourceFile
            self.comment = comment
            self.intent = intent
            self.severity = severity
        }
    }

    public static func bake(
        rawPath: String,
        bounds: BoundingBox,
        accent: UIColor,
        caption: CaptionFields,
        outFile: URL,
        imageScale: CGFloat
    ) -> String? {
        // Load the JPEG. `UIImage(contentsOfFile:)` returns scale = 1
        // because JPEG strips scale metadata, so the loaded image's
        // `size` would be in pixels (e.g., 1206×2622 on iPhone 17 Pro).
        // Reconstruct with the original screen scale so `size` reports
        // in points and matches our `bounds` (also in points). All
        // drawing inside this function then operates in points and
        // aligns naturally.
        guard let cg = UIImage(contentsOfFile: rawPath)?.cgImage else { return nil }
        let topImage = UIImage(cgImage: cg, scale: imageScale, orientation: .up)
        let captionLines = composeCaption(caption)
        let captionFont = UIFont.systemFont(ofSize: 14)
        let titleFont = UIFont.systemFont(ofSize: 16, weight: .semibold)
        let tagFont = UIFont.systemFont(ofSize: 13)
        let lineHeight = captionFont.lineHeight * 1.15
        let titleHeight = titleFont.lineHeight * 1.25
        let tagHeight = caption.intent != nil || caption.severity != nil ? tagFont.lineHeight * 1.4 : 0
        let captionPadding: CGFloat = 16
        let captionHeight = titleHeight
            + lineHeight * CGFloat(captionLines.count)
            + tagHeight
            + captionPadding * 2

        let outSize = CGSize(width: topImage.size.width, height: topImage.size.height + captionHeight)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = topImage.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outSize, format: format)
        let composed = renderer.image { ctx in
            let cg = ctx.cgContext

            // 1. Draw the raw screenshot.
            topImage.draw(in: CGRect(x: 0, y: 0, width: topImage.size.width, height: topImage.size.height))

            // 2. Outline the bounding rect with the accent color. The stroke
            // is outset by half its width so it sits entirely *outside* the
            // captured pixels — important for QA reporting color issues, where
            // any inset stroke (or translucent fill) would distort the actual
            // rendered hue under the mark.
            let strokeRect = CGRect(
                x: CGFloat(bounds.x),
                y: CGFloat(bounds.y),
                width: CGFloat(bounds.width),
                height: CGFloat(bounds.height)
            )
            let cornerRadius: CGFloat = 6
            let lineWidth: CGFloat = 2.5
            let outsetRect = strokeRect.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
            let strokePath = CGPath(
                roundedRect: outsetRect,
                cornerWidth: cornerRadius + lineWidth / 2,
                cornerHeight: cornerRadius + lineWidth / 2,
                transform: nil
            )
            cg.addPath(strokePath)
            cg.setStrokeColor(accent.cgColor)
            cg.setLineWidth(lineWidth)
            cg.strokePath()

            // 3. Caption strip background.
            let captionRect = CGRect(
                x: 0,
                y: topImage.size.height,
                width: topImage.size.width,
                height: captionHeight
            )
            cg.setFillColor(UIColor(red: 0x09 / 255, green: 0x09 / 255, blue: 0x0B / 255, alpha: 1).cgColor)
            cg.fill(captionRect)

            // 4. Title.
            var y = topImage.size.height + captionPadding
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.white,
            ]
            (caption.elementName as NSString).draw(
                at: CGPoint(x: captionPadding, y: y),
                withAttributes: titleAttrs
            )
            y += titleHeight

            // 5. Body lines.
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: captionFont,
                .foregroundColor: UIColor(white: 0.95, alpha: 1),
            ]
            for line in captionLines {
                (line as NSString).draw(
                    at: CGPoint(x: captionPadding, y: y),
                    withAttributes: bodyAttrs
                )
                y += lineHeight
            }

            // 6. Tag row.
            if caption.intent != nil || caption.severity != nil {
                var tagSegments: [String] = []
                if let intent = caption.intent { tagSegments.append("intent: \(intent)") }
                if let severity = caption.severity { tagSegments.append("severity: \(severity)") }
                let tagText = tagSegments.joined(separator: " · ")
                let tagAttrs: [NSAttributedString.Key: Any] = [
                    .font: tagFont,
                    .foregroundColor: UIColor(red: 0xA1 / 255, green: 0xA1 / 255, blue: 0xAA / 255, alpha: 1),
                ]
                (tagText as NSString).draw(
                    at: CGPoint(x: captionPadding, y: y),
                    withAttributes: tagAttrs
                )
            }
        }

        guard let data = composed.jpegData(compressionQuality: 0.85) else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: outFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: outFile, options: .atomic)
            return outFile.path
        } catch {
            return nil
        }
    }

    private static func composeCaption(_ caption: CaptionFields) -> [String] {
        var lines: [String] = []
        if let path = caption.elementPath { lines.append("Location: \(path)") }
        if let source = caption.sourceFile { lines.append("Source: \(source)") }
        lines.append("Feedback: \(caption.comment)")
        return lines
    }
}
#endif
