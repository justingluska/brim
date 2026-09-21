import XCTest
@testable import CapKit

final class ModelDecodingTests: XCTestCase {
    // Shapes copied from the server contract (Mobile.ts) and a live self-hosted response.
    static let capJSON = """
    {
      "id": "cap000000000001",
      "shareUrl": "https://cap.example.com/s/cap000000000001",
      "title": "Sample cap",
      "createdAt": "2026-09-13T18:04:11.000Z",
      "updatedAt": "2026-09-13T18:04:11.000Z",
      "ownerId": "usr000000000001",
      "ownerName": "Test User",
      "durationSeconds": 902.4,
      "thumbnailUrl": "https://cap.example.com/api/mobile/caps/cap000000000001/thumbnail?v=1789668251000",
      "thumbnailCacheKey": "cap-thumbnail:cap000000000001:1789668251000",
      "folderId": null,
      "public": true,
      "protected": false,
      "viewCount": 3,
      "commentCount": 0,
      "reactionCount": 0,
      "upload": null
    }
    """

    func testDecodesCapSummary() throws {
        let cap = try JSONDecoder().decode(CapSummary.self, from: Data(Self.capJSON.utf8))
        XCTAssertEqual(cap.id, "cap000000000001")
        XCTAssertTrue(cap.isPublic)
        XCTAssertFalse(cap.isProtected)
        XCTAssertNil(cap.folderId)
        XCTAssertNil(cap.upload)
        XCTAssertTrue(cap.isReady)
        XCTAssertEqual(cap.durationSeconds, 902.4)
        XCTAssertNotNil(cap.createdDate)
        XCTAssertEqual(Int(cap.createdDate!.timeIntervalSince1970), 1789322651) // 2026-09-13T18:04:11Z
    }

    func testDecodesUploadInProgress() throws {
        var json = Self.capJSON
        json = json.replacingOccurrences(of: "\"upload\": null", with: """
        "upload": {"uploaded": 10, "total": 100, "phase": "processing", "processingProgress": 0.4, "processingMessage": "Transcoding", "processingError": null}
        """)
        let cap = try JSONDecoder().decode(CapSummary.self, from: Data(json.utf8))
        XCTAssertEqual(cap.upload?.phase, .processing)
        XCTAssertFalse(cap.isReady)
    }

    func testDecodesCapsPage() throws {
        let json = """
        {"folders":[{"id":"f1","name":"Clients","color":"blue","parentId":null,"videoCount":4}],
         "caps":[\(Self.capJSON)],"page":1,"limit":30,"total":96,"collectionTotal":96,"hasMore":true}
        """
        let page = try JSONDecoder().decode(CapsPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.folders.first?.color, .blue)
        XCTAssertEqual(page.caps.count, 1)
        XCTAssertTrue(page.hasMore)
    }

    func testDecodesBootstrap() throws {
        let json = """
        {"user":{"id":"usr000000000001","name":"Test","lastName":"User","email":"user@example.com","imageUrl":null,"activeOrganizationId":"org000000000001"},
         "organizations":[{"id":"org000000000001","name":"Example Org","iconUrl":null,"role":"owner"}],
         "activeOrganizationId":"org000000000001",
         "rootFolders":[],
         "spaces":[{"id":"org000000000001","name":"Example Org","iconUrl":null,"kind":"organization","privacy":"Private","role":"owner","canManage":true,"hasPassword":false},
                   {"id":"spc000000000001","name":"Training","iconUrl":null,"kind":"space","privacy":"Private","role":null,"canManage":true,"hasPassword":false}]}
        """
        let boot = try JSONDecoder().decode(Bootstrap.self, from: Data(json.utf8))
        XCTAssertEqual(boot.user.displayName, "Test User")
        XCTAssertEqual(boot.spaces?.count, 2)
        XCTAssertEqual(boot.spaces?[1].kind, .space)
        XCTAssertNil(boot.spaces?[1].role)
    }

    func testBootstrapWithoutSpacesKey() throws {
        let json = """
        {"user":{"id":"u","name":null,"email":"a@b.co","imageUrl":null,"activeOrganizationId":"o"},
         "organizations":[],"activeOrganizationId":null,"rootFolders":[]}
        """
        let boot = try JSONDecoder().decode(Bootstrap.self, from: Data(json.utf8))
        XCTAssertNil(boot.spaces)
        XCTAssertEqual(boot.user.displayName, "a@b.co")
    }

    func testDecodesDetailAndPlayback() throws {
        let detail = """
        {"cap":\(Self.capJSON),"summary":null,"chapters":[{"title":"Intro","start":0},{"title":"Setup","start":42.5}],
         "transcriptionStatus":"COMPLETE",
         "comments":[{"id":"c1","videoId":"cap000000000001","type":"emoji","content":"🔥","timestamp":12.5,"parentCommentId":null,
                      "createdAt":"2026-09-14T10:00:00.000Z","updatedAt":"2026-09-14T10:00:00.000Z",
                      "author":{"id":"u2","name":"Dani","imageUrl":null}}],
         "shareUrl":"https://cap.example.com/s/cap000000000001"}
        """
        let d = try JSONDecoder().decode(CapDetail.self, from: Data(detail.utf8))
        XCTAssertEqual(d.chapters.count, 2)
        XCTAssertEqual(d.transcriptionStatus, .COMPLETE)
        XCTAssertEqual(d.comments.first?.type, .emoji)

        let playback = try JSONDecoder().decode(Playback.self, from: Data("""
        {"kind":"mp4","url":"https://acct.r2.cloudflarestorage.com/bucket/o/v/result.mp4?X-Amz-Expires=3600","transcriptUrl":null}
        """.utf8))
        XCTAssertEqual(playback.kind, .mp4)
        XCTAssertNil(playback.transcriptUrl)
    }

    func testDecodesAuthConfigAndKey() throws {
        let cfg = try JSONDecoder().decode(AuthConfig.self, from: Data("""
        {"appleAuthAvailable":false,"googleAuthAvailable":true,"workosAuthAvailable":false}
        """.utf8))
        XCTAssertEqual(cfg.availableProviders, [.google])
        let key = try JSONDecoder().decode(APIKeyResponse.self, from: Data("""
        {"type":"api_key","apiKey":"0f8fad5b-d9cb-469f-a165-70867728950e","userId":"usr000000000001"}
        """.utf8))
        XCTAssertEqual(key.apiKey.count, 36)
    }

    func testServerErrorBody() throws {
        let e = try JSONDecoder().decode(ServerErrorBody.self, from: Data("""
        {"_tag":"HttpApiDecodeError","message":"email is missing","issues":[]}
        """.utf8))
        XCTAssertEqual(e.bestMessage, "email is missing")
        let tagOnly = try JSONDecoder().decode(ServerErrorBody.self, from: Data("{\"_tag\":\"Unauthorized\"}".utf8))
        XCTAssertEqual(tagOnly.bestMessage, "Unauthorized")
    }
}
