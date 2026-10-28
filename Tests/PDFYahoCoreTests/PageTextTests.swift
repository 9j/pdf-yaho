import XCTest
@testable import PDFYahoCore

final class PageTextTests: XCTestCase {
    func testCopiedTextDropsWordJoinersAndTheSpacesAfterThem() {
        XCTAssertEqual(PageText.plain("재\u{2060} 정\u{2060} 지\u{2060} 침\u{2060} 에 따\u{2060} 라"), "재정지침에 따라")
        XCTAssertEqual(PageText.plain("plain text"), "plain text")
    }
}
