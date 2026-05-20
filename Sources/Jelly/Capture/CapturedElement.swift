import Foundation
import CoreGraphics

/// Mirrors `dev.jelly.capture.CapturedElement` (jelly-android) and the data
/// the web `identifyElement()` returns
/// (`package/src/utils/element-identification.ts:103-216`).
///
/// Bounds are in the **screen / window coord space** so the live preview,
/// the hit-test, and the baked stroke rectangle all align without per-call
/// coord conversion.
public struct CapturedElement: Sendable, Hashable {
    /// Human-readable name shown in the popup header. e.g. `Button "Save"`.
    public let displayName: String

    /// Parent chain readable path. e.g. `Form > Section > Button`.
    public let elementPath: String

    public let role: String?
    public let contentDescription: String?
    public let text: String?
    public let testTag: String?
    public let stateDescription: String?

    public let bounds: CGRect

    public let nearbyElements: String?
    public let nearbyText: String?

    /// SwiftUI view-type name from the nearest `UIHostingController` root,
    /// when available. Stored on `Annotation.composableHierarchy` so the
    /// markdown shows up under `**Composables:**` for downstream agents.
    public let composableName: String?

    /// Optional `file:line` source attribution. Tier 1 (`.jellySource()`)
    /// is preferred; Tier 3 (install-site) is the fallback.
    public let sourceFile: String?

    public init(
        displayName: String,
        elementPath: String,
        role: String? = nil,
        contentDescription: String? = nil,
        text: String? = nil,
        testTag: String? = nil,
        stateDescription: String? = nil,
        bounds: CGRect,
        nearbyElements: String? = nil,
        nearbyText: String? = nil,
        composableName: String? = nil,
        sourceFile: String? = nil
    ) {
        self.displayName = displayName
        self.elementPath = elementPath
        self.role = role
        self.contentDescription = contentDescription
        self.text = text
        self.testTag = testTag
        self.stateDescription = stateDescription
        self.bounds = bounds
        self.nearbyElements = nearbyElements
        self.nearbyText = nearbyText
        self.composableName = composableName
        self.sourceFile = sourceFile
    }
}
