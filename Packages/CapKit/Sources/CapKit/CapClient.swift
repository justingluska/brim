import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for Cap's mobile API (`/api/mobile`), the same API the official Cap
/// iOS app uses. Works against cap.so and any self-hosted Cap that ships that
/// route (every image since mid-2026). Authentication is a per-device API key
/// sent as `Authorization: Bearer <key>`.
public actor CapClient {
    public let server: CapServer
    public private(set) var apiKey: String?
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(server: CapServer, apiKey: String? = nil, session: URLSession? = nil) {
        self.server = server
        self.apiKey = apiKey
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.httpAdditionalHeaders = ["Accept": "application/json", "User-Agent": CapClient.userAgent]
            self.session = URLSession(configuration: config, delegate: RedirectPolicy(), delegateQueue: nil)
        }
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    public static let userAgent = "Brim/\(CapClient.version) (unofficial Cap client; +https://github.com/justingluska/brim)"
    public static var version: String { "0.1" }

    public func setAPIKey(_ key: String?) { apiKey = key }

    // MARK: Session

    public func authConfig() async throws -> AuthConfig {
        try await get("session/config", authenticated: false)
    }

    public func requestEmailCode(email: String) async throws {
        let _: SuccessResponse = try await post("session/email/request", body: ["email": email], authenticated: false)
    }

    public func verifyEmailCode(email: String, code: String) async throws -> APIKeyResponse {
        let response: APIKeyResponse = try await post("session/email/verify", body: ["email": email, "code": code], authenticated: false)
        apiKey = response.apiKey
        return response
    }

    public func revokeSession() async throws {
        let _: SuccessResponse = try await post("session/revoke", body: EmptyBody())
        apiKey = nil
    }

    // MARK: Account

    public func bootstrap() async throws -> Bootstrap {
        try await get("bootstrap")
    }

    public func setActiveOrganization(_ organizationId: String) async throws -> Bootstrap {
        try await patch("user/active-organization", body: ["organizationId": organizationId])
    }

    // MARK: Caps

    public func listCaps(folderId: String? = nil, spaceId: String? = nil, page: Int = 1, limit: Int = 30) async throws -> CapsPage {
        var query = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: String(limit))]
        if let folderId { query.append(URLQueryItem(name: "folderId", value: folderId)) }
        if let spaceId { query.append(URLQueryItem(name: "spaceId", value: spaceId)) }
        return try await get("caps", query: query)
    }

    public func cap(id: String) async throws -> CapDetail {
        try await get("caps/\(encode(id))")
    }

    public func playback(id: String) async throws -> Playback {
        try await get("caps/\(encode(id))/playback")
    }

    public func download(id: String) async throws -> DownloadInfo {
        try await get("caps/\(encode(id))/download")
    }

    public func analytics(id: String, range: AnalyticsRange = .week) async throws -> AnalyticsResponse {
        try await get("caps/\(encode(id))/analytics", query: [URLQueryItem(name: "range", value: range.rawValue)])
    }

    @discardableResult
    public func updateTitle(id: String, title: String) async throws -> CapSummary {
        try await patch("caps/\(encode(id))/title", body: ["title": title])
    }

    @discardableResult
    public func updateSharing(id: String, isPublic: Bool) async throws -> CapSummary {
        try await patch("caps/\(encode(id))/sharing", body: ["public": isPublic])
    }

    @discardableResult
    public func updatePassword(id: String, password: String?) async throws -> CapSummary {
        try await patch("caps/\(encode(id))/password", body: ["password": password])
    }

    public func deleteCap(id: String) async throws {
        let _: SuccessResponse = try await delete("caps/\(encode(id))")
    }

    // MARK: Comments & reactions

    public func createComment(capId: String, content: String, timestamp: Double?, parentCommentId: String? = nil) async throws -> CapComment {
        struct Body: Encodable { var content: String; var timestamp: Double?; var parentCommentId: String? }
        return try await post("caps/\(encode(capId))/comments", body: Body(content: content, timestamp: timestamp, parentCommentId: parentCommentId), encodeNulls: true)
    }

    public func deleteComment(id: String) async throws {
        let _: SuccessResponse = try await delete("comments/\(encode(id))")
    }

    public func createReaction(capId: String, emoji: String, timestamp: Double?) async throws -> CapComment {
        struct Body: Encodable { var content: String; var timestamp: Double? }
        return try await post("caps/\(encode(capId))/reactions", body: Body(content: emoji, timestamp: timestamp), encodeNulls: true)
    }

    // MARK: Folders

    public func createFolder(name: String, color: FolderColor? = nil, spaceId: String? = nil) async throws -> CapFolder {
        struct Body: Encodable { var name: String; var color: FolderColor?; var spaceId: String? }
        return try await post("folders", body: Body(name: name, color: color, spaceId: spaceId))
    }

    // MARK: Binary fetches

    /// Fetches an authenticated server URL (thumbnail) that redirects to
    /// storage. Returns raw image bytes.
    public func thumbnailData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        if url.host?.lowercased() == server.host.lowercased(), let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { throw CapError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw mapError(status: http.statusCode, data: data) }
        return data
    }

    /// Headers AVPlayer should attach when the playback URL lives on the Cap
    /// server itself (segment playlists). Storage URLs are pre-signed and get none.
    public func playerHeaders(for url: URL) -> [String: String] {
        guard url.host?.lowercased() == server.host.lowercased(), let apiKey else { return [:] }
        return ["Authorization": "Bearer \(apiKey)"]
    }

    // MARK: Plumbing

    private struct EmptyBody: Encodable {}

    private func encode(_ pathComponent: String) -> String {
        pathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pathComponent
    }

    private func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/mobile/" + path
        components.queryItems = query.isEmpty ? nil : query
        return components.url!
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], authenticated: Bool = true) async throws -> T {
        try await send(method: "GET", path: path, query: query, body: nil as Data?, authenticated: authenticated)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B, authenticated: Bool = true, encodeNulls: Bool = false) async throws -> T {
        try await send(method: "POST", path: path, body: try encodeBody(body, encodeNulls: encodeNulls), authenticated: authenticated)
    }

    private func patch<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await send(method: "PATCH", path: path, body: try encodeBody(body, encodeNulls: true), authenticated: true)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        try await send(method: "DELETE", path: path, body: nil as Data?, authenticated: true)
    }

    private func encodeBody<B: Encodable>(_ body: B, encodeNulls: Bool) throws -> Data {
        // Dictionaries with Optional values need explicit null handling so
        // `{"password": null}` is sent rather than `{}`.
        if let dict = body as? [String: String?] {
            let obj = dict.mapValues { $0 as Any? }.mapValues { $0 ?? NSNull() }
            return try JSONSerialization.data(withJSONObject: obj)
        }
        if let dict = body as? [String: Bool] {
            return try JSONSerialization.data(withJSONObject: dict)
        }
        if let dict = body as? [String: String] {
            return try JSONSerialization.data(withJSONObject: dict)
        }
        return try encoder.encode(body)
    }

    private func send<T: Decodable>(method: String, path: String, query: [URLQueryItem] = [], body: Data?, authenticated: Bool) async throws -> T {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method
        if authenticated {
            guard let apiKey else { throw CapError.notSignedIn }
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { throw CapError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw mapError(status: http.statusCode, data: data) }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CapError.decoding(String(describing: error))
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as CapError {
            throw error
        } catch {
            throw CapError.network(error.localizedDescription)
        }
    }

    private func mapError(status: Int, data: Data) -> CapError {
        let body = try? decoder.decode(ServerErrorBody.self, from: data)
        let message = body?.bestMessage
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden(message)
        case 404: return .notFound
        case 400, 422: return .badRequest(message)
        default: return .server(status: status, message: message)
        }
    }
}
