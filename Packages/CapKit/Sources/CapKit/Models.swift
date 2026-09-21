import Foundation

// Wire types for Cap's mobile API. Field names mirror the server contract
// (packages/web-domain/src/Mobile.ts in CapSoftware/Cap) exactly, except where
// a name collides with a Swift keyword (`public`, `protected`).

public struct AuthConfig: Codable, Sendable, Equatable {
    public var appleAuthAvailable: Bool
    public var googleAuthAvailable: Bool
    public var workosAuthAvailable: Bool

    public var availableProviders: [AuthProvider] {
        var out: [AuthProvider] = []
        if googleAuthAvailable { out.append(.google) }
        if appleAuthAvailable { out.append(.apple) }
        if workosAuthAvailable { out.append(.workos) }
        return out
    }
}

public struct APIKeyResponse: Codable, Sendable, Equatable {
    public var type: String
    public var apiKey: String
    public var userId: String
}

public struct SuccessResponse: Codable, Sendable { public var success: Bool }

public struct CapUser: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String?
    public var lastName: String?
    public var email: String
    public var imageUrl: String?
    public var activeOrganizationId: String

    public var displayName: String {
        let full = [name, lastName].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? email : full
    }
}

public enum OrgRole: String, Codable, Sendable { case owner, admin, member }

public struct CapOrganization: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var iconUrl: String?
    public var role: OrgRole
}

public struct CapSpace: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case organization, space }
    public enum Privacy: String, Codable, Sendable { case Public, Private }
    public var id: String
    public var name: String
    public var iconUrl: String?
    public var kind: Kind
    public var privacy: Privacy
    public var role: OrgRole?
    public var canManage: Bool
    public var hasPassword: Bool
}

public enum FolderColor: String, Codable, Sendable { case normal, blue, red, yellow }

public struct CapFolder: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var color: FolderColor
    public var parentId: String?
    public var videoCount: Int
}

public enum UploadPhase: String, Codable, Sendable {
    case uploading, processing, generating_thumbnail, complete, error
}

public struct UploadProgress: Codable, Sendable, Equatable {
    public var uploaded: Double
    public var total: Double
    public var phase: UploadPhase
    public var processingProgress: Double
    public var processingMessage: String?
    public var processingError: String?
}

public struct CapSummary: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var shareUrl: String
    public var title: String
    public var createdAt: String
    public var updatedAt: String
    public var ownerId: String?
    public var ownerName: String
    public var durationSeconds: Double?
    /// An authenticated `/api/mobile/caps/{id}/thumbnail?v=…` URL on the
    /// server; it 302s to a short-lived storage URL. Fetch with the bearer
    /// token and let the redirect drop it (see `CapClient.thumbnailData`).
    public var thumbnailUrl: String?
    public var thumbnailCacheKey: String?
    public var folderId: String?
    public var isPublic: Bool
    public var isProtected: Bool
    public var viewCount: Int
    public var commentCount: Int
    public var reactionCount: Int
    public var upload: UploadProgress?
    public var ownedByCurrentUser: Bool?

    enum CodingKeys: String, CodingKey {
        case id, shareUrl, title, createdAt, updatedAt, ownerId, ownerName, durationSeconds
        case thumbnailUrl, thumbnailCacheKey, folderId
        case isPublic = "public"
        case isProtected = "protected"
        case viewCount, commentCount, reactionCount, upload, ownedByCurrentUser
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id); hasher.combine(updatedAt) }

    public var createdDate: Date? { ISO8601.parse(createdAt) }
    public var isReady: Bool { upload == nil || upload?.phase == .complete }
}

public struct CapComment: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case text, emoji }
    public struct Author: Codable, Sendable, Equatable {
        public var id: String
        public var name: String?
        public var imageUrl: String?
    }
    public var id: String
    public var videoId: String
    public var type: Kind
    public var content: String
    public var timestamp: Double?
    public var parentCommentId: String?
    public var createdAt: String
    public var updatedAt: String
    public var author: Author

    public var createdDate: Date? { ISO8601.parse(createdAt) }
}

public struct CapChapter: Codable, Sendable, Equatable, Identifiable {
    public var title: String
    public var start: Double
    public var id: Double { start }
}

public enum TranscriptionStatus: String, Codable, Sendable {
    case PROCESSING, COMPLETE, ERROR, SKIPPED, NO_AUDIO
}

public struct CapDetail: Codable, Sendable, Equatable {
    public var cap: CapSummary
    public var summary: String?
    public var chapters: [CapChapter]
    public var transcriptionStatus: TranscriptionStatus?
    public var comments: [CapComment]
    public var shareUrl: String
}

public struct CapsPage: Codable, Sendable, Equatable {
    public var folders: [CapFolder]
    public var caps: [CapSummary]
    public var page: Int
    public var limit: Int
    public var total: Int
    public var collectionTotal: Int?
    public var hasMore: Bool
}

public struct Bootstrap: Codable, Sendable, Equatable {
    public var user: CapUser
    public var organizations: [CapOrganization]
    public var activeOrganizationId: String?
    public var rootFolders: [CapFolder]
    public var spaces: [CapSpace]?
}

public struct Playback: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case mp4, hls }
    public var kind: Kind
    public var url: String
    public var transcriptUrl: String?
}

public struct DownloadInfo: Codable, Sendable, Equatable {
    public var fileName: String
    public var url: String
}

public enum AnalyticsRange: String, Codable, Sendable, CaseIterable {
    case day = "24h", week = "7d", month = "30d", lifetime
}

public struct AnalyticsBreakdown: Codable, Sendable, Equatable {
    public var name: String
    public var subtitle: String?
    public var views: Int
    public var percentage: Double
}

public struct AnalyticsData: Codable, Sendable, Equatable {
    public struct Counts: Codable, Sendable, Equatable {
        public var caps: Int; public var views: Int; public var comments: Int; public var reactions: Int
    }
    public struct Bucket: Codable, Sendable, Equatable {
        public var bucket: String; public var caps: Int; public var views: Int; public var comments: Int; public var reactions: Int
    }
    public struct Breakdowns: Codable, Sendable, Equatable {
        public var countries: [AnalyticsBreakdown]
        public var cities: [AnalyticsBreakdown]
        public var browsers: [AnalyticsBreakdown]
        public var operatingSystems: [AnalyticsBreakdown]
        public var devices: [AnalyticsBreakdown]
    }
    public var capName: String
    public var counts: Counts
    public var chart: [Bucket]
    public var breakdowns: Breakdowns
}

public struct AnalyticsResponse: Codable, Sendable, Equatable {
    public var available: Bool
    public var data: AnalyticsData?
}

/// ISO-8601 parsing for the server's JS `toISOString()` output
/// ("2026-09-13T12:00:00.000Z") with a fallback for whole seconds.
public enum ISO8601 {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    public static func parse(_ s: String) -> Date? {
        fractional.date(from: s) ?? plain.date(from: s)
    }
}
