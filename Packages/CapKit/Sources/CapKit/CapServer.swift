import Foundation

/// A Cap deployment: cap.so itself or any self-hosted instance.
public struct CapServer: Hashable, Codable, Sendable {
    /// Origin only (scheme + host + optional port), no path, no trailing slash.
    public let baseURL: URL

    public static let cloud = CapServer(baseURL: URL(string: "https://cap.so")!)

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// Accepts what a person types: "cap.example.com", "https://cap.example.com/",
    /// "http://localhost:3000", "cap.so/dashboard". Returns nil for anything
    /// that does not resolve to an http(s) origin with a host.
    public init?(userInput: String) {
        var text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "https://" + text
        }
        guard var components = URLComponents(string: text),
              let host = components.host, !host.isEmpty,
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else { return nil }
        components.scheme = scheme
        components.host = host.lowercased()
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        guard let url = components.url else { return nil }
        self.baseURL = url
    }

    public var isCloud: Bool { self == .cloud }

    /// "cap.so", "cap.example.com", "localhost:3000".
    public var displayHost: String {
        guard let host = baseURL.host else { return baseURL.absoluteString }
        if let port = baseURL.port { return "\(host):\(port)" }
        return host
    }

    public var host: String { baseURL.host ?? "" }

    /// The web sign-in flow's `/api/mobile/session/request` URL. The server
    /// only accepts `cap://auth` as the redirect, so the app catches that
    /// scheme inside an ASWebAuthenticationSession (it never leaves the app).
    public func browserSignInURL(provider: AuthProvider? = nil, organizationId: String? = nil) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/mobile/session/request"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "redirectUri", value: "cap://auth")]
        if let provider { items.append(URLQueryItem(name: "provider", value: provider.rawValue)) }
        if let organizationId { items.append(URLQueryItem(name: "organizationId", value: organizationId)) }
        components.queryItems = items
        return components.url!
    }

    /// Parses the `cap://auth?api_key=…&user_id=…` callback.
    public static func parseAuthCallback(_ url: URL) -> (apiKey: String, userId: String)? {
        guard url.scheme?.lowercased() == "cap", url.host?.lowercased() == "auth",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let key = items.first(where: { $0.name == "api_key" })?.value, !key.isEmpty
        else { return nil }
        let userId = items.first(where: { $0.name == "user_id" })?.value ?? ""
        return (key, userId)
    }
}

public enum AuthProvider: String, Codable, Sendable, CaseIterable {
    case apple, google, workos
}
