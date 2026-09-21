import Foundation

public enum CapError: Error, LocalizedError, Sendable, Equatable {
    /// 401 from the server: the stored key was revoked (signing in on another
    /// phone replaces it) or never existed on this server.
    case unauthorized
    case forbidden(String?)
    case notFound
    case badRequest(String?)
    case server(status: Int, message: String?)
    case invalidResponse
    case decoding(String)
    case network(String)
    case notSignedIn

    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "Your session is no longer valid. Sign in again."
        case .forbidden(let m): return m ?? "You don't have access to that."
        case .notFound: return "Not found. It may have been deleted."
        case .badRequest(let m): return m ?? "The server rejected the request."
        case .server(let status, let m): return m ?? "Server error (\(status))."
        case .invalidResponse: return "Unexpected response from the server."
        case .decoding(let m): return "Could not read the server's response: \(m)"
        case .network(let m): return m
        case .notSignedIn: return "Not signed in."
        }
    }

    public var isAuthFailure: Bool {
        if case .unauthorized = self { return true }
        return false
    }
}

/// Effect HttpApi error bodies look like {"_tag":"Unauthorized"} or
/// {"_tag":"HttpApiDecodeError","message":"…","issues":[…]}. Decode leniently.
struct ServerErrorBody: Decodable {
    var tag: String?
    var message: String?
    var error: String?
    enum CodingKeys: String, CodingKey { case tag = "_tag", message, error }

    var bestMessage: String? { message ?? error ?? tag }
}
