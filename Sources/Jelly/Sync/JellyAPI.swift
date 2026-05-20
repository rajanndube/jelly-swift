import Foundation

/// URLSession async/await client mirroring `dev.jelly.sync.JellyApi` —
/// itself a port of `package/src/utils/sync.ts`.
///
/// All endpoints share the same wire format as the web and Android clients
/// since `Annotation` is serialized with the same field names. Failures
/// throw `JellyAPIError` — callers should catch and fall back to local-only
/// behavior so a network blip never breaks annotate-mode.
public final class JellyAPI {
    public let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseURL: URL, session: URLSession = .shared) {
        // Trim trailing slash so endpoint paths concatenate cleanly.
        var trimmed = baseURL.absoluteString
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        self.baseURL = URL(string: trimmed) ?? baseURL
        self.session = session
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = []
        self.decoder = JSONDecoder()
    }

    // MARK: - Endpoints

    public func listSessions() async throws -> [Session] {
        try await get("/sessions")
    }

    public func createSession(url: String) async throws -> Session {
        try await post("/sessions", body: CreateSessionRequest(url: url))
    }

    public func getSession(_ sessionId: String) async throws -> SessionWithAnnotations {
        try await get("/sessions/\(sessionId)")
    }

    public func syncAnnotation(sessionId: String, annotation: Annotation) async throws -> Annotation {
        try await post("/sessions/\(sessionId)/annotations", body: annotation)
    }

    public func updateAnnotation(annotationId: String, patch: Annotation) async throws -> Annotation {
        try await patchRequest("/annotations/\(annotationId)", body: patch)
    }

    public func deleteAnnotation(annotationId: String) async throws {
        var request = makeRequest(path: "/annotations/\(annotationId)")
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        try requireOK(response)
    }

    public func requestAction(sessionId: String, output: String) async throws -> ActionResponse {
        try await post("/sessions/\(sessionId)/action", body: ActionRequest(output: output))
    }

    /// Upload the baked screenshot bytes for an annotation. Used by the
    /// local-sync viewer so a paired browser can render the image
    /// alongside the markdown. No-op on backends that don't implement
    /// this endpoint — callers should wrap in `try?` since older servers
    /// respond 404.
    public func uploadAnnotationImage(
        annotationId: String,
        bytes: Data,
        contentType: String = "image/jpeg"
    ) async throws {
        var request = makeRequest(path: "/annotations/\(annotationId)/image")
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = bytes
        let (_, response) = try await session.data(for: request)
        try requireOK(response)
    }

    /// Identify this device + heartbeat. Used by the local-sync viewer
    /// to show "iPhone 17 Pro · iOS 26 — connected" instead of a generic
    /// "listening" label. Called periodically while sync is enabled;
    /// stale silence on the page side implies the SDK has gone away.
    /// Hosted MCP servers typically 404 this and that's fine — callers
    /// wrap in `try?`.
    public func sayHello(_ info: DeviceInfo) async throws {
        var request = makeRequest(path: "/hello")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(info)
        let (_, response) = try await session.data(for: request)
        try requireOK(response)
    }

    // MARK: - HTTP helpers

    private func get<R: Decodable>(_ path: String) async throws -> R {
        var request = makeRequest(path: path)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try requireOK(response)
        return try decode(R.self, from: data, request: request)
    }

    private func post<B: Encodable, R: Decodable>(_ path: String, body: B) async throws -> R {
        var request = makeRequest(path: path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try requireOK(response)
        return try decode(R.self, from: data, request: request)
    }

    private func patchRequest<B: Encodable, R: Decodable>(_ path: String, body: B) async throws -> R {
        var request = makeRequest(path: path)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try requireOK(response)
        return try decode(R.self, from: data, request: request)
    }

    /// Decodes the response, and on failure logs both the request URL
    /// and the actual response body. Without this the user gets the
    /// useless "data couldn't be read because it is missing" message
    /// with no way to see what the server actually sent back.
    private func decode<R: Decodable>(_ type: R.Type, from data: Data, request: URLRequest) throws -> R {
        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            let preview = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
            let url = request.url?.absoluteString ?? "?"
            print("[Jelly] decode FAILED for \(R.self) at \(url): \(error)\n  body: \(preview.prefix(500))")
            throw error
        }
    }

    private func makeRequest(path: String) -> URLRequest {
        let url = baseURL.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path)
        return URLRequest(url: url)
    }

    private func requireOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw JellyAPIError(statusCode: -1, message: "Non-HTTP response")
        }
        if !(200..<300).contains(http.statusCode) {
            throw JellyAPIError(statusCode: http.statusCode, message: "HTTP \(http.statusCode)")
        }
    }
}

public struct JellyAPIError: LocalizedError, CustomStringConvertible {
    public let statusCode: Int
    public let message: String

    public var description: String { "JellyAPIError(\(statusCode)): \(message)" }
    /// Required for `error.localizedDescription` to surface the actual
    /// status code and message. Without this, Swift's bridging falls
    /// back to the unhelpful `(error 1.)`.
    public var errorDescription: String? { description }
}

// MARK: - Request/response wire types

private struct CreateSessionRequest: Codable {
    let url: String
}

private struct ActionRequest: Codable {
    let output: String
}

public struct ActionResponse: Codable, Sendable {
    public let success: Bool
    public let annotationCount: Int
    public let delivered: Delivered

    public struct Delivered: Codable, Sendable {
        public let sseListeners: Int
        public let webhooks: Int
        public let total: Int
    }
}

/// Wire shape for `JellyAPI.sayHello`. Mirrors what the local-sync server
/// reads to render the "which device is connected" indicator on the page.
/// All fields except `platform` are optional — hosted MCP servers may not
/// care, and we don't want a missing field to break the heartbeat.
public struct DeviceInfo: Codable, Sendable, Equatable {
    public let platform: String
    public let model: String?
    public let manufacturer: String?
    public let osVersion: String?
    public let appName: String?
    public let sdkVersion: String?

    public init(
        platform: String,
        model: String? = nil,
        manufacturer: String? = nil,
        osVersion: String? = nil,
        appName: String? = nil,
        sdkVersion: String? = nil
    ) {
        self.platform = platform
        self.model = model
        self.manufacturer = manufacturer
        self.osVersion = osVersion
        self.appName = appName
        self.sdkVersion = sdkVersion
    }
}
