import XCTest
@testable import CapKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// URLProtocol stub so the client can be exercised without a network.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        StubProtocol.requests.append(request)
        guard let handler = StubProtocol.handler else { return }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class CapClientTests: XCTestCase {
    func makeClient(apiKey: String? = "0f8fad5b-d9cb-469f-a165-70867728950e") -> CapClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        StubProtocol.requests = []
        return CapClient(server: CapServer(userInput: "cap.example.com")!, apiKey: apiKey, session: URLSession(configuration: config))
    }

    func respond(_ status: Int, _ json: String) {
        StubProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data(json.utf8))
        }
    }

    func testListCapsBuildsURLAndBearer() async throws {
        respond(200, """
        {"folders":[],"caps":[],"page":2,"limit":30,"total":0,"hasMore":false}
        """)
        let page = try await makeClient().listCaps(spaceId: "spc000000000001", page: 2)
        XCTAssertEqual(page.page, 2)
        let request = StubProtocol.requests.last!
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.path, "/api/mobile/caps")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "spaceId" })?.value, "spc000000000001")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "page" })?.value, "2")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer 0f8fad5b-d9cb-469f-a165-70867728950e")
    }

    func testUnauthorizedMapsToCapError() async {
        respond(401, "{\"_tag\":\"Unauthorized\"}")
        do {
            _ = try await makeClient().bootstrap()
            XCTFail("expected throw")
        } catch let error as CapError {
            XCTAssertEqual(error, .unauthorized)
            XCTAssertTrue(error.isAuthFailure)
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testMissingKeyThrowsBeforeNetwork() async {
        do {
            _ = try await makeClient(apiKey: nil).bootstrap()
            XCTFail("expected throw")
        } catch let error as CapError {
            XCTAssertEqual(error, .notSignedIn)
            XCTAssertTrue(StubProtocol.requests.isEmpty)
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testVerifyEmailStoresKeyAndSendsJSON() async throws {
        respond(200, "{\"type\":\"api_key\",\"apiKey\":\"11111111-2222-3333-4444-555555555555\",\"userId\":\"u1\"}")
        let client = makeClient(apiKey: nil)
        let key = try await client.verifyEmailCode(email: "user@example.com", code: "123456")
        XCTAssertEqual(key.apiKey, "11111111-2222-3333-4444-555555555555")
        let stored = await client.apiKey
        XCTAssertEqual(stored, key.apiKey)
        let request = StubProtocol.requests.last!
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try JSONSerialization.jsonObject(with: bodyData(of: request)) as! [String: String]
        XCTAssertEqual(body, ["email": "user@example.com", "code": "123456"])
    }

    func testPasswordNullIsSentExplicitly() async throws {
        respond(200, ModelDecodingTests.capJSON)
        _ = try await makeClient().updatePassword(id: "cap000000000001", password: nil)
        let request = StubProtocol.requests.last!
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path, "/api/mobile/caps/cap000000000001/password")
        XCTAssertEqual(String(decoding: bodyData(of: request), as: UTF8.self), "{\"password\":null}")
    }

    func testSharingBoolBody() async throws {
        respond(200, ModelDecodingTests.capJSON)
        _ = try await makeClient().updateSharing(id: "x", isPublic: false)
        XCTAssertEqual(String(decoding: bodyData(of: StubProtocol.requests.last!), as: UTF8.self), "{\"public\":false}")
    }

    func testCommentBodyKeepsNullTimestamp() async throws {
        respond(200, """
        {"id":"c1","videoId":"x","type":"text","content":"hi","timestamp":null,"parentCommentId":null,
         "createdAt":"2026-09-14T10:00:00.000Z","updatedAt":"2026-09-14T10:00:00.000Z","author":{"id":"u","name":null,"imageUrl":null}}
        """)
        _ = try await makeClient().createComment(capId: "x", content: "hi", timestamp: nil)
        let body = try JSONSerialization.jsonObject(with: bodyData(of: StubProtocol.requests.last!)) as! [String: Any]
        XCTAssertEqual(body["content"] as? String, "hi")
        // JSONEncoder drops nil optionals; the server treats a missing timestamp as null, which is what we want.
        XCTAssertNil(body["parentCommentId"])
    }

    func testPlayerHeadersOnlyForServerHost() async {
        let client = makeClient()
        let onServer = await client.playerHeaders(for: URL(string: "https://cap.example.com/api/playlist?videoId=x&videoType=segments-master")!)
        XCTAssertEqual(onServer["Authorization"], "Bearer 0f8fad5b-d9cb-469f-a165-70867728950e")
        let storage = await client.playerHeaders(for: URL(string: "https://acct.r2.cloudflarestorage.com/bucket/o/v/result.mp4?X-Amz-Signature=abc")!)
        XCTAssertTrue(storage.isEmpty)
    }

    private func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
