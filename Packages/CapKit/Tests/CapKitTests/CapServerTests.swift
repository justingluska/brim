import XCTest
@testable import CapKit

final class CapServerTests: XCTestCase {
    func testNormalizesUserInput() {
        XCTAssertEqual(CapServer(userInput: "cap.example.com")?.baseURL.absoluteString, "https://cap.example.com")
        XCTAssertEqual(CapServer(userInput: "https://cap.example.com/")?.baseURL.absoluteString, "https://cap.example.com")
        XCTAssertEqual(CapServer(userInput: "  HTTPS://Cap.So/dashboard/caps?x=1#frag ")?.baseURL.absoluteString, "https://cap.so")
        XCTAssertEqual(CapServer(userInput: "http://localhost:3000")?.baseURL.absoluteString, "http://localhost:3000")
        XCTAssertEqual(CapServer(userInput: "http://localhost:3000")?.displayHost, "localhost:3000")
    }

    func testRejectsGarbage() {
        XCTAssertNil(CapServer(userInput: ""))
        XCTAssertNil(CapServer(userInput: "   "))
        XCTAssertNil(CapServer(userInput: "ftp://cap.so"))
        XCTAssertNil(CapServer(userInput: "https://"))
    }

    func testCloudDetection() {
        XCTAssertTrue(CapServer(userInput: "cap.so")!.isCloud)
        XCTAssertFalse(CapServer(userInput: "cap.example.com")!.isCloud)
    }

    func testBrowserSignInURL() {
        let url = CapServer.cloud.browserSignInURL(provider: .google)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.path, "/api/mobile/session/request")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "redirectUri" })?.value, "cap://auth")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "provider" })?.value, "google")
        XCTAssertNil(CapServer.cloud.browserSignInURL().query?.range(of: "provider"))
    }

    func testParsesAuthCallback() {
        let ok = CapServer.parseAuthCallback(URL(string: "cap://auth?api_key=0f8fad5b-d9cb-469f-a165-70867728950e&user_id=usr000000000001")!)
        XCTAssertEqual(ok?.apiKey, "0f8fad5b-d9cb-469f-a165-70867728950e")
        XCTAssertEqual(ok?.userId, "usr000000000001")
        XCTAssertNil(CapServer.parseAuthCallback(URL(string: "cap://other?api_key=x")!))
        XCTAssertNil(CapServer.parseAuthCallback(URL(string: "https://cap.so/auth?api_key=x")!))
        XCTAssertNil(CapServer.parseAuthCallback(URL(string: "cap://auth?user_id=x")!))
    }
}
