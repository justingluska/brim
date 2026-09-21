import XCTest
@testable import CapKit

/// Decodes real responses captured from a self-hosted Cap (web 0.3.1, image
/// 2026-09-07) on 2026-09-21, with signatures and emails scrubbed. If a server
/// upgrade changes the wire format, refresh these files and see what breaks.
final class LiveFixtureTests: XCTestCase {
    private func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    func testBootstrap() throws {
        let boot = try load("bootstrap", as: Bootstrap.self)
        XCTAssertFalse(boot.organizations.isEmpty)
        XCTAssertNotNil(boot.activeOrganizationId)
        XCTAssertTrue((boot.spaces ?? []).contains { $0.kind == .organization })
    }

    func testCapsPages() throws {
        let mine = try load("caps", as: CapsPage.self)
        XCTAssertFalse(mine.caps.isEmpty)
        XCTAssertTrue(mine.caps.allSatisfy { $0.thumbnailUrl?.contains("/api/mobile/caps/") == true })
        let space = try load("space", as: CapsPage.self)
        XCTAssertGreaterThan(space.total, 0)
    }

    func testDetailPlaybackAnalyticsDownloadConfig() throws {
        let detail = try load("detail", as: CapDetail.self)
        XCTAssertEqual(detail.shareUrl, detail.cap.shareUrl)
        let playback = try load("playback", as: Playback.self)
        XCTAssertTrue(playback.url.contains("X-Amz-"))
        _ = try load("analytics", as: AnalyticsResponse.self)
        let download = try load("download", as: DownloadInfo.self)
        XCTAssertFalse(download.fileName.isEmpty)
        let config = try load("config", as: AuthConfig.self)
        XCTAssertEqual(config.availableProviders, [])
    }
}
