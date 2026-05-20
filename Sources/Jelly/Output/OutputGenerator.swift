import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 1:1 port of `dev.jelly.output.OutputGenerator` (jelly-android), which itself
/// is a 1:1 port of `generateOutput()` in
/// `package/src/utils/generate-output.ts:27-129`.
///
/// The output format is the contract that downstream AI agents read, so
/// byte-for-byte parity matters where the field exists on iOS. Web-only fields
/// (`cssClasses`, `computedStyles`, `fullPath`) are simply absent on iOS
/// annotations and the corresponding lines are skipped — matching how the web
/// version skips empty fields.
///
/// On iOS, the `**Composables:**` line is repurposed for the SwiftUI
/// view-type hierarchy (sourced from the nearest `UIHostingController`'s root
/// view type) so existing agent prompts that look for `**React:**`
/// /`**Composables:**` still find the equivalent metadata.
public struct OutputGenerator {
    public let viewportWidth: Int
    public let viewportHeight: Int
    public let nowIso: () -> String
    public let deviceInfo: String
    public let devicePixelRatio: Float

    public init(
        viewportWidth: Int,
        viewportHeight: Int,
        nowIso: @escaping () -> String = OutputGenerator.defaultNowIso,
        deviceInfo: String = OutputGenerator.defaultDeviceInfo(),
        devicePixelRatio: Float = OutputGenerator.defaultDevicePixelRatio()
    ) {
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.nowIso = nowIso
        self.deviceInfo = deviceInfo
        self.devicePixelRatio = devicePixelRatio
    }

    public func generate(
        annotations: [Annotation],
        screenKey: String,
        detailLevel: JellyDetailLevel = .standard
    ) -> String {
        if annotations.isEmpty { return "" }

        let viewport = "\(viewportWidth)×\(viewportHeight)"
        var sb = ""
        sb.append("## Page Feedback: ")
        sb.append(screenKey)
        sb.append("\n")

        switch detailLevel {
        case .forensic:
            sb.append("\n**Environment:**\n")
            sb.append("- Viewport: ")
            sb.append(viewport)
            sb.append("\n")
            sb.append("- Screen: ")
            sb.append(screenKey)
            sb.append("\n")
            sb.append("- Device: ")
            sb.append(deviceInfo)
            sb.append("\n")
            sb.append("- Timestamp: ")
            sb.append(nowIso())
            sb.append("\n")
            sb.append("- Device Pixel Ratio: ")
            sb.append(formatRatio(devicePixelRatio))
            sb.append("\n")
            sb.append("\n---\n")
        case .compact:
            break
        case .standard, .detailed:
            sb.append("**Viewport:** ")
            sb.append(viewport)
            sb.append("\n")
        }
        sb.append("\n")

        for (index, annotation) in annotations.enumerated() {
            let i = index + 1
            switch detailLevel {
            case .compact:
                sb.append("\(i). **")
                sb.append(annotation.element)
                sb.append("**")
                if let source = annotation.sourceFile {
                    sb.append(" (")
                    sb.append(source)
                    sb.append(")")
                }
                sb.append(": ")
                sb.append(annotation.comment)
                if let selectedText = annotation.selectedText {
                    sb.append(" (re: \"")
                    sb.append(takeFirst(selectedText, 30))
                    if selectedText.count > 30 {
                        sb.append("...")
                    }
                    sb.append("\")")
                }
                sb.append("\n")

            case .forensic:
                sb.append("### ")
                sb.append("\(i)")
                sb.append(". ")
                sb.append(annotation.element)
                sb.append("\n")
                if annotation.isMultiSelect == true, annotation.fullPath != nil {
                    sb.append("*Forensic data shown for first element of selection*\n")
                }
                if let fullPath = annotation.fullPath {
                    sb.append("**Full Path:** ")
                    sb.append(fullPath)
                    sb.append("\n")
                }
                if let cssClasses = annotation.cssClasses {
                    sb.append("**Classes:** ")
                    sb.append(cssClasses)
                    sb.append("\n")
                }
                if let box = annotation.boundingBox {
                    sb.append("**Position:** x:")
                    sb.append("\(roundedInt(box.x))")
                    sb.append(", y:")
                    sb.append("\(roundedInt(box.y))")
                    sb.append(" (")
                    sb.append("\(roundedInt(box.width))")
                    sb.append("×")
                    sb.append("\(roundedInt(box.height))")
                    sb.append("px)\n")
                }
                sb.append("**Annotation at:** ")
                sb.append(formatPercent(annotation.x))
                sb.append("% from left, ")
                sb.append("\(roundedInt(annotation.y))")
                sb.append("px from top\n")
                if let selectedText = annotation.selectedText {
                    sb.append("**Selected text:** \"")
                    sb.append(selectedText)
                    sb.append("\"\n")
                }
                if let nearbyText = annotation.nearbyText, annotation.selectedText == nil {
                    sb.append("**Context:** ")
                    sb.append(takeFirst(nearbyText, 100))
                    sb.append("\n")
                }
                if let computedStyles = annotation.computedStyles {
                    sb.append("**Computed Styles:** ")
                    sb.append(computedStyles)
                    sb.append("\n")
                }
                if let accessibility = annotation.accessibility {
                    sb.append("**Accessibility:** ")
                    sb.append(accessibility)
                    sb.append("\n")
                }
                if let nearbyElements = annotation.nearbyElements {
                    sb.append("**Nearby Elements:** ")
                    sb.append(nearbyElements)
                    sb.append("\n")
                }
                if let source = annotation.sourceFile {
                    sb.append("**Source:** ")
                    sb.append(source)
                    sb.append("\n")
                }
                if let composables = annotation.composableHierarchy {
                    sb.append("**Composables:** ")
                    sb.append(composables)
                    sb.append("\n")
                }
                if annotation.screenshotPath != nil {
                    sb.append("**Screenshot:** [attached]\n")
                }
                sb.append("**Feedback:** ")
                sb.append(annotation.comment)
                sb.append("\n\n")

            case .standard, .detailed:
                sb.append("### ")
                sb.append("\(i)")
                sb.append(". ")
                sb.append(annotation.element)
                sb.append("\n")
                sb.append("**Location:** ")
                sb.append(annotation.elementPath)
                sb.append("\n")
                if let source = annotation.sourceFile {
                    sb.append("**Source:** ")
                    sb.append(source)
                    sb.append("\n")
                }
                if let composables = annotation.composableHierarchy {
                    sb.append("**Composables:** ")
                    sb.append(composables)
                    sb.append("\n")
                }
                if detailLevel == .detailed {
                    if let accessibility = annotation.accessibility {
                        sb.append("**Accessibility:** ")
                        sb.append(accessibility)
                        sb.append("\n")
                    }
                    if let cssClasses = annotation.cssClasses {
                        sb.append("**Classes:** ")
                        sb.append(cssClasses)
                        sb.append("\n")
                    }
                    if let box = annotation.boundingBox {
                        sb.append("**Position:** ")
                        sb.append("\(roundedInt(box.x))")
                        sb.append("px, ")
                        sb.append("\(roundedInt(box.y))")
                        sb.append("px (")
                        sb.append("\(roundedInt(box.width))")
                        sb.append("×")
                        sb.append("\(roundedInt(box.height))")
                        sb.append("px)\n")
                    }
                    if let nearbyText = annotation.nearbyText {
                        sb.append("**Context:** ")
                        sb.append(takeFirst(nearbyText, 100))
                        sb.append("\n")
                    }
                }
                if let selectedText = annotation.selectedText {
                    sb.append("**Selected text:** \"")
                    sb.append(selectedText)
                    sb.append("\"\n")
                }
                if annotation.screenshotPath != nil {
                    sb.append("**Screenshot:** [attached]\n")
                }
                sb.append("**Feedback:** ")
                sb.append(annotation.comment)
                sb.append("\n\n")
            }
        }

        return sb.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Defaults

    public static let defaultNowIso: @Sendable () -> String = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    public static func defaultDeviceInfo() -> String {
        #if canImport(UIKit)
        let device = UIDevice.current
        return "Apple \(device.model); iOS \(device.systemVersion)"
        #else
        return "Apple device"
        #endif
    }

    public static func defaultDevicePixelRatio() -> Float {
        #if canImport(UIKit)
        return Float(UIScreen.main.scale)
        #else
        return 1.0
        #endif
    }

    // MARK: Helpers

    /// Mirrors Kotlin's `Float.roundToInt()` semantics — half-away-from-zero
    /// rounding to Int. Swift's default `.toNearestOrEven` (banker's rounding)
    /// would diverge on `.5` boundaries.
    private func roundedInt(_ value: Float) -> Int {
        Int((value).rounded(.toNearestOrAwayFromZero))
    }

    /// Mirrors Kotlin's `String.take(n)` — returns the first `n` characters.
    private func takeFirst(_ value: String, _ count: Int) -> String {
        if value.count <= count { return value }
        let endIndex = value.index(value.startIndex, offsetBy: count)
        return String(value[value.startIndex..<endIndex])
    }

    /// Reproduces Kotlin's `String.format("%.1f", x)` — one decimal, locale-invariant
    /// (`.` separator) so the markdown is byte-identical across locales.
    private func formatPercent(_ value: Float) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// Reproduces Kotlin's default `Float.toString()` for the device-pixel-ratio
    /// line: integer values render without a decimal (`2`), non-integer values
    /// keep their natural representation (`2.5`). The Android default
    /// `1f.toString()` is `"1.0"`, so we mirror that exactly.
    private func formatRatio(_ value: Float) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        return String(value)
    }
}
