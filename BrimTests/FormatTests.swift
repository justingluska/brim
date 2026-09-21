import XCTest
@testable import Brim

final class FormatTests: XCTestCase {
    func testDuration() {
        XCTAssertEqual(Format.duration(0), "0:00")
        XCTAssertEqual(Format.duration(264.3), "4:24")
        XCTAssertEqual(Format.duration(902.4), "15:02")
        XCTAssertEqual(Format.duration(3725), "1:02:05")
        XCTAssertEqual(Format.duration(nil), "--:--")
        XCTAssertEqual(Format.duration(-1), "--:--")
    }

    func testCount() {
        XCTAssertEqual(Format.count(1, "view"), "1 view")
        XCTAssertEqual(Format.count(2, "view"), "2 views")
        XCTAssertEqual(Format.count(1, "cap"), "1 cap")
    }
}
