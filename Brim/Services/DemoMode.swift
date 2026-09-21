import Foundation
import UIKit
import CapKit

/// Demo mode: a made-up library served from inside the app, so Brim can be
/// explored (and screenshotted, and reviewed) without a Cap account.
///
/// It works by handing `CapClient` a URLSession whose only protocol is
/// `DemoURLProtocol`. Every screen runs its normal code path; the requests
/// just never leave the process. Nothing here is real data: the people,
/// titles, thumbnails and the bundled sample video are all synthetic.
enum Demo {
    static let server = CapServer(baseURL: URL(string: "https://demo.brim.invalid")!)
    static let apiKey = "00000000-0000-4000-8000-00000000d3m0"
    static let accountId = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let userId = "demo-user"
    /// `-BrimDemo` on the command line starts the app straight in the demo and
    /// keeps it away from the Keychain. Used by the screenshot UI tests.
    static let launchArgument = "-BrimDemo"

    static var isRequestedAtLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func makeClient() -> CapClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DemoURLProtocol.self]
        return CapClient(server: server, apiKey: apiKey, session: URLSession(configuration: config))
    }

    static func makeAccount() -> Account {
        Account(id: accountId, server: server, apiKey: apiKey, userId: userId,
                email: "alex@example.com", displayName: "Alex Rivera", addedAt: Date(), isDemo: true)
    }
}

/// JSON null for a missing value.
private func orNull(_ value: Any?) -> Any { value ?? NSNull() }

// MARK: - Sample content

private struct DemoCap {
    var id: String
    var title: String
    var minutesAgo: Double
    var duration: Double
    var views: Int
    var isPublic: Bool
    var hasPassword: Bool
    var folderId: String?
    var spaces: [String]
    var style: Int
}

private struct DemoComment {
    var id: String
    var capId: String
    var isEmoji: Bool
    var content: String
    var timestamp: Double?
    var authorId: String
    var authorName: String
    var minutesAgo: Double
}

/// In-memory state so renames, visibility changes, comments and deletes behave
/// for the length of a session. Guarded by a lock: URLProtocol callbacks arrive
/// on URLSession's own threads.
private final class DemoStore: @unchecked Sendable {
    static let shared = DemoStore()
    private let lock = NSLock()
    private var nextId = 100

    private var caps: [DemoCap] = [
        DemoCap(id: "demo-cap-01", title: "Onboarding walkthrough for new teammates", minutesAgo: 35, duration: 264, views: 18, isPublic: true, hasPassword: false, folderId: nil, spaces: ["demo-space-eng"], style: 0),
        DemoCap(id: "demo-cap-02", title: "Bug repro: checkout button on Safari", minutesAgo: 190, duration: 52, views: 7, isPublic: true, hasPassword: false, folderId: nil, spaces: ["demo-space-eng"], style: 1),
        DemoCap(id: "demo-cap-03", title: "Design feedback on the new settings page", minutesAgo: 26 * 60, duration: 431, views: 12, isPublic: false, hasPassword: false, folderId: nil, spaces: ["demo-space-design"], style: 2),
        DemoCap(id: "demo-cap-04", title: "Q3 roadmap review", minutesAgo: 3 * 24 * 60, duration: 1284, views: 41, isPublic: true, hasPassword: true, folderId: nil, spaces: ["demo-org"], style: 3),
        DemoCap(id: "demo-cap-05", title: "How to deploy the docs site", minutesAgo: 6 * 24 * 60, duration: 318, views: 23, isPublic: true, hasPassword: false, folderId: nil, spaces: ["demo-space-eng"], style: 1),
        DemoCap(id: "demo-cap-06", title: "Weekly update: growth experiments", minutesAgo: 15 * 24 * 60, duration: 602, views: 56, isPublic: true, hasPassword: false, folderId: nil, spaces: ["demo-org"], style: 3),
        DemoCap(id: "demo-cap-07", title: "Setting up your laptop on day one", minutesAgo: 20 * 24 * 60, duration: 745, views: 30, isPublic: true, hasPassword: false, folderId: "demo-folder-onboarding", spaces: [], style: 0),
        DemoCap(id: "demo-cap-08", title: "Where everything lives in the wiki", minutesAgo: 22 * 24 * 60, duration: 203, views: 27, isPublic: true, hasPassword: false, folderId: "demo-folder-onboarding", spaces: [], style: 2),
    ]

    private var comments: [DemoComment] = [
        DemoComment(id: "demo-c-1", capId: "demo-cap-01", isEmoji: false, content: "Super clear. Can we link this from the welcome doc?", timestamp: 42, authorId: "demo-sam", authorName: "Sam Chen", minutesAgo: 28),
        DemoComment(id: "demo-c-2", capId: "demo-cap-01", isEmoji: false, content: "The part about access requests changed last week, I'll record a short follow-up.", timestamp: 131, authorId: "demo-priya", authorName: "Priya Patel", minutesAgo: 21),
        DemoComment(id: "demo-c-3", capId: "demo-cap-01", isEmoji: false, content: "Added to the onboarding checklist.", timestamp: 204, authorId: Demo.userId, authorName: "Alex Rivera", minutesAgo: 9),
        DemoComment(id: "demo-c-4", capId: "demo-cap-01", isEmoji: true, content: "🔥", timestamp: 12, authorId: "demo-sam", authorName: "Sam Chen", minutesAgo: 30),
        DemoComment(id: "demo-c-5", capId: "demo-cap-01", isEmoji: true, content: "👍", timestamp: 77, authorId: "demo-priya", authorName: "Priya Patel", minutesAgo: 25),
        DemoComment(id: "demo-c-6", capId: "demo-cap-01", isEmoji: true, content: "🎉", timestamp: 250, authorId: "demo-sam", authorName: "Sam Chen", minutesAgo: 20),
        DemoComment(id: "demo-c-7", capId: "demo-cap-02", isEmoji: false, content: "Reproduced on Safari 18 too.", timestamp: 19, authorId: "demo-sam", authorName: "Sam Chen", minutesAgo: 120),
    ]

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    // MARK: JSON builders

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func stamp(minutesAgo: Double) -> String {
        Self.iso.string(from: Date().addingTimeInterval(-minutesAgo * 60))
    }

    private func summary(_ cap: DemoCap) -> [String: Any] {
        let own = comments.filter { $0.capId == cap.id }
        return [
            "id": cap.id,
            "shareUrl": "https://cap.example.com/s/\(cap.id)",
            "title": cap.title,
            "createdAt": stamp(minutesAgo: cap.minutesAgo),
            "updatedAt": stamp(minutesAgo: cap.minutesAgo),
            "ownerId": Demo.userId,
            "ownerName": "Alex Rivera",
            "durationSeconds": cap.duration,
            "thumbnailUrl": "\(Demo.server.baseURL.absoluteString)/api/mobile/caps/\(cap.id)/thumbnail?v=\(cap.style)",
            "thumbnailCacheKey": "demo-thumbnail:\(cap.id):\(cap.style)",
            "folderId": orNull(cap.folderId),
            "public": cap.isPublic,
            "protected": cap.hasPassword,
            "viewCount": cap.views,
            "commentCount": own.filter { !$0.isEmoji }.count,
            "reactionCount": own.filter { $0.isEmoji }.count,
            "upload": NSNull(),
            "ownedByCurrentUser": true,
        ]
    }

    private func json(_ c: DemoComment) -> [String: Any] {
        [
            "id": c.id, "videoId": c.capId, "type": c.isEmoji ? "emoji" : "text", "content": c.content,
            "timestamp": orNull(c.timestamp), "parentCommentId": NSNull(),
            "createdAt": stamp(minutesAgo: c.minutesAgo), "updatedAt": stamp(minutesAgo: c.minutesAgo),
            "author": ["id": c.authorId, "name": c.authorName, "imageUrl": NSNull()],
        ]
    }

    private var folders: [[String: Any]] {
        [[
            "id": "demo-folder-onboarding", "name": "Onboarding", "color": "blue", "parentId": NSNull(),
            "videoCount": caps.filter { $0.folderId == "demo-folder-onboarding" }.count,
        ]]
    }

    // MARK: Endpoints

    func bootstrap() -> [String: Any] {
        locked {
            [
                "user": ["id": Demo.userId, "name": "Alex", "lastName": "Rivera", "email": "alex@example.com",
                         "imageUrl": NSNull(), "activeOrganizationId": "demo-org"],
                "organizations": [["id": "demo-org", "name": "Acme Studio", "iconUrl": NSNull(), "role": "owner"]],
                "activeOrganizationId": "demo-org",
                "rootFolders": folders,
                "spaces": [
                    ["id": "demo-org", "name": "Acme Studio", "iconUrl": NSNull(), "kind": "organization", "privacy": "Private", "role": "owner", "canManage": true, "hasPassword": false],
                    ["id": "demo-space-eng", "name": "Engineering", "iconUrl": NSNull(), "kind": "space", "privacy": "Private", "role": "admin", "canManage": true, "hasPassword": false],
                    ["id": "demo-space-design", "name": "Design", "iconUrl": NSNull(), "kind": "space", "privacy": "Private", "role": "member", "canManage": false, "hasPassword": false],
                ],
            ]
        }
    }

    func list(spaceId: String?, folderId: String?) -> [String: Any] {
        locked {
            let matching: [DemoCap]
            if let folderId {
                matching = caps.filter { $0.folderId == folderId }
            } else if let spaceId {
                matching = caps.filter { $0.spaces.contains(spaceId) }
            } else {
                matching = caps.filter { $0.folderId == nil }
            }
            return [
                "folders": (folderId == nil && spaceId == nil) ? folders : [],
                "caps": matching.map(summary),
                "page": 1, "limit": 30, "total": matching.count, "collectionTotal": matching.count, "hasMore": false,
            ]
        }
    }

    func detail(id: String) -> [String: Any]? {
        locked {
            guard let cap = caps.first(where: { $0.id == id }) else { return nil }
            let chapters: [[String: Any]] = cap.id == "demo-cap-01"
                ? [["title": "Welcome", "start": 0], ["title": "Accounts and access", "start": 48], ["title": "Your first week", "start": 126], ["title": "Who to ask", "start": 212]]
                : []
            let summaryText = orNull(cap.id == "demo-cap-01"
                ? "A tour of the tools, accounts and people a new teammate needs in their first week."
                : nil)
            return [
                "cap": summary(cap), "summary": summaryText, "chapters": chapters,
                "transcriptionStatus": "COMPLETE",
                "comments": comments.filter { $0.capId == id }.map(json),
                "shareUrl": "https://cap.example.com/s/\(cap.id)",
            ]
        }
    }

    func style(of id: String) -> Int? {
        locked { caps.first(where: { $0.id == id })?.style }
    }

    func update(id: String, _ change: (inout DemoCapEdit) -> Void) -> [String: Any]? {
        locked {
            guard let i = caps.firstIndex(where: { $0.id == id }) else { return nil }
            var edit = DemoCapEdit(title: caps[i].title, isPublic: caps[i].isPublic, hasPassword: caps[i].hasPassword)
            change(&edit)
            caps[i].title = edit.title
            caps[i].isPublic = edit.isPublic
            caps[i].hasPassword = edit.hasPassword
            return summary(caps[i])
        }
    }

    func delete(id: String) {
        locked { caps.removeAll { $0.id == id } }
    }

    func addComment(capId: String, content: String, timestamp: Double?, isEmoji: Bool) -> [String: Any] {
        locked {
            nextId += 1
            let comment = DemoComment(id: "demo-c-\(nextId)", capId: capId, isEmoji: isEmoji, content: content,
                                      timestamp: timestamp, authorId: Demo.userId, authorName: "Alex Rivera", minutesAgo: 0)
            comments.append(comment)
            return json(comment)
        }
    }

    func deleteComment(id: String) {
        locked { comments.removeAll { $0.id == id } }
    }

    func analytics(id: String) -> [String: Any] {
        locked {
            let cap = caps.first { $0.id == id }
            let views = cap?.views ?? 0
            func rows(_ names: [(String, Double)]) -> [[String: Any]] {
                names.map { item -> [String: Any] in
                    ["name": item.0, "subtitle": NSNull(), "views": Int(Double(views) * item.1), "percentage": item.1 * 100]
                }
            }
            return [
                "available": true,
                "data": [
                    "capName": cap?.title ?? "",
                    "counts": ["caps": 1, "views": views, "comments": 3, "reactions": 3],
                    "chart": [],
                    "breakdowns": [
                        "countries": rows([("United States", 0.5), ("Canada", 0.2), ("Germany", 0.2), ("Japan", 0.1)]),
                        "cities": rows([("New York", 0.3), ("Toronto", 0.2)]),
                        "browsers": rows([("Chrome", 0.6), ("Safari", 0.3), ("Firefox", 0.1)]),
                        "operatingSystems": rows([("macOS", 0.6), ("iOS", 0.25), ("Windows", 0.15)]),
                        "devices": rows([("Desktop", 0.7), ("Mobile", 0.3)]),
                        "topCaps": [],
                    ],
                ],
            ]
        }
    }
}

struct DemoCapEdit {
    var title: String
    var isPublic: Bool
    var hasPassword: Bool
}

// MARK: - The fake server

final class DemoURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == Demo.server.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return finish(status: 400, json: ["_tag": "BadRequest"]) }
        let method = request.httpMethod ?? "GET"
        let parts = url.path.split(separator: "/").map(String.init).dropFirst(2)   // drop "api", "mobile"
        let path = Array(parts)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let body = (try? JSONSerialization.jsonObject(with: Self.bodyData(of: request))) as? [String: Any] ?? [:]
        let store = DemoStore.shared

        switch (method, path.count) {
        case ("GET", 2) where path == ["session", "config"]:
            return finish(json: ["appleAuthAvailable": false, "googleAuthAvailable": false, "workosAuthAvailable": false])
        case ("POST", 2) where path == ["session", "revoke"]:
            return finish(json: ["success": true])
        case ("GET", 1) where path == ["bootstrap"]:
            return finish(json: store.bootstrap())
        case ("PATCH", 2) where path == ["user", "active-organization"]:
            return finish(json: store.bootstrap())
        case ("GET", 1) where path == ["caps"]:
            let spaceId = query.first { $0.name == "spaceId" }?.value
            let folderId = query.first { $0.name == "folderId" }?.value
            return finish(json: store.list(spaceId: spaceId, folderId: folderId))
        case ("GET", 2) where path[0] == "caps":
            guard let detail = store.detail(id: path[1]) else { return finish(status: 404, json: ["_tag": "NotFound"]) }
            return finish(json: detail)
        case ("DELETE", 2) where path[0] == "caps":
            store.delete(id: path[1])
            return finish(json: ["success": true])
        case ("DELETE", 2) where path[0] == "comments":
            store.deleteComment(id: path[1])
            return finish(json: ["success": true])
        case (_, 3) where path[0] == "caps":
            return capAction(method: method, id: path[1], action: path[2], body: body)
        default:
            return finish(status: 404, json: ["_tag": "NotFound"])
        }
    }

    private func capAction(method: String, id: String, action: String, body: [String: Any]) {
        let store = DemoStore.shared
        switch (method, action) {
        case ("GET", "playback"):
            guard let video = Bundle.main.url(forResource: "demo", withExtension: "mp4") else {
                return finish(status: 404, json: ["_tag": "NotFound"])
            }
            finish(json: ["kind": "mp4", "url": video.absoluteString, "transcriptUrl": NSNull()])
        case ("GET", "download"):
            guard let video = Bundle.main.url(forResource: "demo", withExtension: "mp4") else {
                return finish(status: 404, json: ["_tag": "NotFound"])
            }
            finish(json: ["fileName": "brim-demo.mp4", "url": video.absoluteString])
        case ("GET", "thumbnail"):
            guard let style = store.style(of: id) else { return finish(status: 404, json: ["_tag": "NotFound"]) }
            finish(status: 200, data: DemoArtwork.png(style: style), contentType: "image/png")
        case ("GET", "analytics"):
            finish(json: store.analytics(id: id))
        case ("PATCH", "title"):
            let title = (body["title"] as? String) ?? ""
            reply(store.update(id: id) { $0.title = title })
        case ("PATCH", "sharing"):
            let isPublic = (body["public"] as? Bool) ?? true
            reply(store.update(id: id) { $0.isPublic = isPublic })
        case ("PATCH", "password"):
            let hasPassword = body["password"] is String
            reply(store.update(id: id) { $0.hasPassword = hasPassword })
        case ("POST", "comments"), ("POST", "reactions"):
            let content = (body["content"] as? String) ?? ""
            finish(json: store.addComment(capId: id, content: content, timestamp: body["timestamp"] as? Double, isEmoji: action == "reactions"))
        default:
            finish(status: 404, json: ["_tag": "NotFound"])
        }
    }

    private func reply(_ summary: [String: Any]?) {
        if let summary { finish(json: summary) } else { finish(status: 404, json: ["_tag": "NotFound"]) }
    }

    private func finish(status: Int = 200, json: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        finish(status: status, data: data, contentType: "application/json")
    }

    private func finish(status: Int, data: Data, contentType: String) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType])
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// URLSession hands protocols the body as a stream, not as `httpBody`.
    private static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

// MARK: - Generated thumbnails

/// Draws stand-in "screen recordings": an app window on a gradient, in four
/// looks. Pure Core Graphics, so there is no stock imagery in the repository.
enum DemoArtwork {
    private static let size = CGSize(width: 640, height: 360)

    static func png(style: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(style: style, in: context.cgContext)
        }
        return image.pngData() ?? Data()
    }

    private static func draw(style: Int, in ctx: CGContext) {
        let palettes: [(UInt32, UInt32)] = [(0x2EB4FF, 0x005CB1), (0x7F5AF0, 0x2CB67D), (0xFF8A5B, 0xD6336C), (0x14B8A6, 0x1E3A8A)]
        let (a, b) = palettes[abs(style) % palettes.count]
        let colors = [UIColor(hex: a).cgColor, UIColor(hex: b).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }

        let dark = style % 2 == 1
        let window = CGRect(x: 70, y: 44, width: 500, height: 272)
        let windowFill = dark ? UIColor(hex: 0x11161D) : UIColor(hex: 0xF8F9FB)
        let line = dark ? UIColor(hex: 0x3A4654) : UIColor(hex: 0xB9C2CC)
        let strong = dark ? UIColor(hex: 0xE6EDF3) : UIColor(hex: 0x0D1B2A)

        ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 24, color: UIColor.black.withAlphaComponent(0.35).cgColor)
        fill(ctx, UIBezierPath(roundedRect: window, cornerRadius: 10), windowFill)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        // Title bar with traffic lights.
        fill(ctx, UIBezierPath(roundedRect: CGRect(x: window.minX, y: window.minY, width: window.width, height: 24),
                               byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 10, height: 10)),
             dark ? UIColor(hex: 0x1B222C) : UIColor(hex: 0xE6E8EC))
        for (i, hex) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() {
            fill(ctx, UIBezierPath(ovalIn: CGRect(x: window.minX + 10 + CGFloat(i) * 12, y: window.minY + 8, width: 8, height: 8)), UIColor(hex: hex))
        }

        // Sidebar.
        fill(ctx, UIBezierPath(rect: CGRect(x: window.minX, y: window.minY + 24, width: 110, height: window.height - 24)),
             dark ? UIColor(hex: 0x161C24) : UIColor(hex: 0xEEF1F5))
        fill(ctx, bar(window.minX + 12, window.minY + 40, 76, 7), UIColor(hex: a))
        for i in 0..<5 {
            fill(ctx, bar(window.minX + 12, window.minY + 60 + CGFloat(i) * 16, CGFloat(50 + (i * 17) % 40), 6), line)
        }

        let x = window.minX + 130
        let top = window.minY + 42
        switch abs(style) % 4 {
        case 1:   // code editor: indented lines in a few accent colors
            let accents: [UInt32] = [0x7F5AF0, 0x2CB67D, 0xFF8A5B, 0x2EB4FF]
            for i in 0..<13 {
                let indent = CGFloat((i * 7) % 4) * 14
                fill(ctx, bar(x + indent, top + CGFloat(i) * 16, CGFloat(90 + (i * 53) % 210), 7), UIColor(hex: accents[i % accents.count]).withAlphaComponent(0.85))
            }
        case 3:   // dashboard: stat tiles and a bar chart
            for i in 0..<3 {
                fill(ctx, UIBezierPath(roundedRect: CGRect(x: x + CGFloat(i) * 118, y: top, width: 106, height: 52), cornerRadius: 6), UIColor(hex: a).withAlphaComponent(0.18))
                fill(ctx, bar(x + CGFloat(i) * 118 + 10, top + 12, 40, 6), line)
                fill(ctx, bar(x + CGFloat(i) * 118 + 10, top + 28, 64, 10), strong)
            }
            let heights: [CGFloat] = [40, 72, 56, 96, 64, 110, 84, 124, 100]
            for (i, h) in heights.enumerated() {
                fill(ctx, UIBezierPath(roundedRect: CGRect(x: x + CGFloat(i) * 38, y: window.maxY - 20 - h, width: 24, height: h), cornerRadius: 3), UIColor(hex: i % 2 == 0 ? a : b))
            }
        default:  // document / product page: heading, paragraph, cards, button
            fill(ctx, bar(x, top, 210, 13), strong)
            for i in 0..<3 {
                fill(ctx, bar(x, top + 28 + CGFloat(i) * 13, CGFloat(330 - i * 28), 6), line)
            }
            let tints: [UInt32] = [0xC5EAFF, 0xD9F5E5, 0xFFE9C2]
            for (i, tint) in tints.enumerated() {
                fill(ctx, UIBezierPath(roundedRect: CGRect(x: x + CGFloat(i) * 116, y: top + 80, width: 104, height: 70), cornerRadius: 6),
                     UIColor(hex: tint).withAlphaComponent(dark ? 0.35 : 1))
            }
            fill(ctx, UIBezierPath(roundedRect: CGRect(x: x, y: top + 168, width: 78, height: 22), cornerRadius: 5), UIColor(hex: b))
        }
    }

    private static func bar(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> UIBezierPath {
        UIBezierPath(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: height / 2)
    }

    private static func fill(_ ctx: CGContext, _ path: UIBezierPath, _ color: UIColor) {
        ctx.setFillColor(color.cgColor)
        ctx.addPath(path.cgPath)
        ctx.fillPath()
    }
}
