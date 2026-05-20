import Foundation

public struct Session: Codable, Hashable, Sendable {
    public var id: String
    /// Tolerant defaults — minimal MCP servers (like jelly-local-sync)
    /// only return `{id, url, createdAt}` from `POST /sessions`, so
    /// every other field has to be optional or we'll fail to decode.
    public var url: String?
    public var status: SessionStatus?
    public var createdAt: String?
    public var updatedAt: String?
    public var projectId: String?

    public init(
        id: String,
        url: String? = nil,
        status: SessionStatus? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        projectId: String? = nil
    ) {
        self.id = id
        self.url = url
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.projectId = projectId
    }
}

public enum SessionStatus: String, Codable, Hashable, Sendable {
    case active
    case approved
    case closed
}

public struct SessionWithAnnotations: Codable, Hashable, Sendable {
    public var id: String
    public var url: String?
    public var status: SessionStatus?
    public var createdAt: String?
    public var updatedAt: String?
    public var projectId: String?
    public var annotations: [Annotation]

    public init(
        id: String,
        url: String? = nil,
        status: SessionStatus? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        projectId: String? = nil,
        annotations: [Annotation] = []
    ) {
        self.id = id
        self.url = url
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.projectId = projectId
        self.annotations = annotations
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, status, createdAt, updatedAt, projectId, annotations
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.url = try c.decodeIfPresent(String.self, forKey: .url)
        self.status = try c.decodeIfPresent(SessionStatus.self, forKey: .status)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        self.updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        self.projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        // Annotations key may be absent (server returns it only on
        // GET /sessions/:id, not on session-creating POSTs).
        self.annotations = try c.decodeIfPresent([Annotation].self, forKey: .annotations) ?? []
    }
}
