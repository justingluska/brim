import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Drops the Authorization header when a redirect leaves the Cap server.
/// Thumbnails and playback redirect to pre-signed object-storage URLs; S3-style
/// storage rejects a request that carries both a query signature and an
/// Authorization header, and the bearer key must never be sent to a third
/// party anyway.
final class RedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        let originalHost = task.originalRequest?.url?.host?.lowercased()
        let newHost = request.url?.host?.lowercased()
        var next = request
        if originalHost != newHost {
            next.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(next)
    }
}
