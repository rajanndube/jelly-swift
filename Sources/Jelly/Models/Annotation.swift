import Foundation

/// Mirrors `dev.jelly.model.Annotation` (jelly-android) and the `Annotation`
/// type in the web SDK's `package/src/types.ts`. The wire format matches
/// byte-for-byte so the same MCP `/sessions` endpoint and downstream agents
/// work for all clients. The two non-trivial mappings are
/// `composableHierarchy` ↔ `"reactComponents"` and `syncedTo` ↔ `"_syncedTo"`.
public struct Annotation: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var x: Float
    public var y: Float
    public var comment: String
    public var element: String
    public var elementPath: String
    public var timestamp: Int64
    public var selectedText: String?
    public var boundingBox: BoundingBox?
    public var nearbyText: String?
    public var cssClasses: String?
    public var nearbyElements: String?
    public var computedStyles: String?
    public var fullPath: String?
    public var accessibility: String?
    public var isMultiSelect: Bool?
    public var isFixed: Bool?
    public var composableHierarchy: String?
    public var sourceFile: String?
    public var drawingIndex: Int?
    public var elementBoundingBoxes: [BoundingBox]?
    public var kind: AnnotationKind?
    public var placement: PlacementData?
    public var rearrange: RearrangeData?

    public var screenshotPath: String?

    public var sessionId: String?
    public var url: String?
    public var intent: AnnotationIntent?
    public var severity: AnnotationSeverity?
    public var status: AnnotationStatus?
    public var thread: [ThreadMessage]?
    public var createdAt: String?
    public var updatedAt: String?
    public var resolvedAt: String?
    public var resolvedBy: ResolvedBy?
    public var authorId: String?

    public var syncedTo: String?

    public init(
        id: String,
        x: Float,
        y: Float,
        comment: String,
        element: String,
        elementPath: String,
        timestamp: Int64,
        selectedText: String? = nil,
        boundingBox: BoundingBox? = nil,
        nearbyText: String? = nil,
        cssClasses: String? = nil,
        nearbyElements: String? = nil,
        computedStyles: String? = nil,
        fullPath: String? = nil,
        accessibility: String? = nil,
        isMultiSelect: Bool? = nil,
        isFixed: Bool? = nil,
        composableHierarchy: String? = nil,
        sourceFile: String? = nil,
        drawingIndex: Int? = nil,
        elementBoundingBoxes: [BoundingBox]? = nil,
        kind: AnnotationKind? = nil,
        placement: PlacementData? = nil,
        rearrange: RearrangeData? = nil,
        screenshotPath: String? = nil,
        sessionId: String? = nil,
        url: String? = nil,
        intent: AnnotationIntent? = nil,
        severity: AnnotationSeverity? = nil,
        status: AnnotationStatus? = nil,
        thread: [ThreadMessage]? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        resolvedAt: String? = nil,
        resolvedBy: ResolvedBy? = nil,
        authorId: String? = nil,
        syncedTo: String? = nil
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.comment = comment
        self.element = element
        self.elementPath = elementPath
        self.timestamp = timestamp
        self.selectedText = selectedText
        self.boundingBox = boundingBox
        self.nearbyText = nearbyText
        self.cssClasses = cssClasses
        self.nearbyElements = nearbyElements
        self.computedStyles = computedStyles
        self.fullPath = fullPath
        self.accessibility = accessibility
        self.isMultiSelect = isMultiSelect
        self.isFixed = isFixed
        self.composableHierarchy = composableHierarchy
        self.sourceFile = sourceFile
        self.drawingIndex = drawingIndex
        self.elementBoundingBoxes = elementBoundingBoxes
        self.kind = kind
        self.placement = placement
        self.rearrange = rearrange
        self.screenshotPath = screenshotPath
        self.sessionId = sessionId
        self.url = url
        self.intent = intent
        self.severity = severity
        self.status = status
        self.thread = thread
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resolvedAt = resolvedAt
        self.resolvedBy = resolvedBy
        self.authorId = authorId
        self.syncedTo = syncedTo
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case x
        case y
        case comment
        case element
        case elementPath
        case timestamp
        case selectedText
        case boundingBox
        case nearbyText
        case cssClasses
        case nearbyElements
        case computedStyles
        case fullPath
        case accessibility
        case isMultiSelect
        case isFixed
        case composableHierarchy = "reactComponents"
        case sourceFile
        case drawingIndex
        case elementBoundingBoxes
        case kind
        case placement
        case rearrange
        case screenshotPath
        case sessionId
        case url
        case intent
        case severity
        case status
        case thread
        case createdAt
        case updatedAt
        case resolvedAt
        case resolvedBy
        case authorId
        case syncedTo = "_syncedTo"
    }
}

public enum AnnotationKind: String, Codable, Hashable, Sendable {
    case feedback
    case placement
    case rearrange
}

public enum AnnotationIntent: String, Codable, Hashable, Sendable, CaseIterable {
    case fix
    case change
    case question
    case approve
}

public enum AnnotationSeverity: String, Codable, Hashable, Sendable, CaseIterable {
    case blocking
    case important
    case suggestion
}

public enum AnnotationStatus: String, Codable, Hashable, Sendable {
    case pending
    case acknowledged
    case resolved
    case dismissed
}

public enum ResolvedBy: String, Codable, Hashable, Sendable {
    case human
    case agent
}

public struct PlacementData: Codable, Hashable, Sendable {
    public var componentType: String
    public var width: Float
    public var height: Float
    public var scrollY: Float
    public var text: String?

    public init(componentType: String, width: Float, height: Float, scrollY: Float, text: String? = nil) {
        self.componentType = componentType
        self.width = width
        self.height = height
        self.scrollY = scrollY
        self.text = text
    }
}

public struct RearrangeData: Codable, Hashable, Sendable {
    public var selector: String
    public var label: String
    public var tagName: String
    public var originalRect: BoundingBox
    public var currentRect: BoundingBox

    public init(
        selector: String,
        label: String,
        tagName: String,
        originalRect: BoundingBox,
        currentRect: BoundingBox
    ) {
        self.selector = selector
        self.label = label
        self.tagName = tagName
        self.originalRect = originalRect
        self.currentRect = currentRect
    }
}
