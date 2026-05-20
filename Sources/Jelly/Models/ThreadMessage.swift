import Foundation

public struct ThreadMessage: Codable, Hashable, Sendable {
    public var id: String
    public var role: ThreadRole
    public var content: String
    public var timestamp: Int64

    public init(id: String, role: ThreadRole, content: String, timestamp: Int64) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

public enum ThreadRole: String, Codable, Hashable, Sendable {
    case human
    case agent
}
