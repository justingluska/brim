import XCTest

/// Walks the demo library and attaches a PNG of each main screen to the test
/// results. The README screenshots come from these attachments, so they never
/// contain anyone's real recordings. Run with the Brim scheme's tests.
final class ScreenshotTests: XCTestCase {
    private let firstCapTitle = "Onboarding walkthrough for new teammates"

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.appearance = .light
    }

    @MainActor
    func testCaptureScreens() throws {
        XCUIDevice.shared.appearance = .light
        let app = XCUIApplication()
        app.launchArguments = ["-BrimDemo"]
        app.launch()

        // Library
        let firstCap = app.staticTexts[firstCapTitle].firstMatch
        XCTAssertTrue(firstCap.waitForExistence(timeout: 30), "demo library did not load")
        settle(2)   // thumbnails are drawn asynchronously
        snap("01-library")

        // Player and details
        firstCap.tap()
        XCTAssertTrue(app.buttons["Share"].firstMatch.waitForExistence(timeout: 20), "cap detail did not open")
        settle(4)   // let the sample video render a frame
        snap("02-player")

        app.swipeUp()
        settle(1)
        snap("03-comments")

        // Settings
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(firstCap.waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Accounts"].firstMatch.waitForExistence(timeout: 10) || app.navigationBars["Settings"].exists)
        settle(1)
        snap("04-settings")

        // Dark mode: the appearance only applies reliably to a fresh launch.
        app.terminate()
        XCUIDevice.shared.appearance = .dark
        app.launch()
        XCTAssertTrue(firstCap.waitForExistence(timeout: 30))
        settle(2)
        snap("05-library-dark")
        firstCap.tap()
        XCTAssertTrue(app.buttons["Share"].firstMatch.waitForExistence(timeout: 20))
        settle(4)
        snap("06-player-dark")

        // Sign-in, from a clean launch without the demo flag
        app.terminate()
        XCUIDevice.shared.appearance = .light
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["Continue"].firstMatch.waitForExistence(timeout: 20), "sign-in screen did not appear")
        settle(1)
        snap("07-sign-in")
    }

    /// Screenshots need the UI to finish animating; this is a test-only pause,
    /// not a synchronization mechanism for app code.
    private func settle(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        attachment.name = "brim-\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
