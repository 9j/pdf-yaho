import AppKit
import PDFKit
import XCTest
@testable import PDFYahoCore

final class PageOpsTests: XCTestCase {
    private func doc(_ texts: [String]) -> PDFDocument { PDFOpsTests().makeTextDocument(texts) }

    func testRedrawKeepsTextAndResizes() throws {
        let source = doc(["Keep this text"])
        let page = try XCTUnwrap(source.page(at: 0))
        page.addAnnotation(Annotations.shape(.rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200), color: .red, lineWidth: 2))
        let a4 = try XCTUnwrap(PageOps.redrawn(page, size: PageOps.PaperSize.a4.size))
        XCTAssertEqual(a4.bounds(for: .mediaBox).size, PageOps.PaperSize.a4.size)
        XCTAssertTrue(a4.string?.contains("Keep this text") ?? false)
        XCTAssertEqual(a4.annotations.count, 1)
        XCTAssertLessThan(a4.annotations[0].bounds.width, 100)
    }

    func testRedrawBakesRotation() throws {
        let source = doc(["rotated"])
        let page = try XCTUnwrap(source.page(at: 0))
        page.rotation = 90
        let flat = try XCTUnwrap(PageOps.redrawn(page, size: CGSize(width: 792, height: 612)))
        XCTAssertEqual(flat.rotation, 0)
        XCTAssertTrue(flat.string?.contains("rotated") ?? false)
    }

    func testContentBoundsFindsText() throws {
        let source = doc(["Margins"])
        let page = try XCTUnwrap(source.page(at: 0))
        let bounds = try XCTUnwrap(PageOps.contentBounds(page))
        XCTAssertGreaterThan(bounds.minX, 60)
        XCTAssertLessThan(bounds.maxX, 300)
        XCTAssertGreaterThan(bounds.minY, 680)
        XCTAssertNil(PageOps.contentBounds(PDFOps.blankPage()))
    }

    func testSplitModes() {
        let d = doc(["1", "2", "3", "4", "5"])
        XCTAssertEqual(PageOps.split(d, mode: .everyPages(2)).map(\.document.pageCount), [2, 2, 1])
        XCTAssertEqual(PageOps.split(d, mode: .oddEven).map(\.document.pageCount), [3, 2])
        let ranges = PageOps.parseRanges("1-2, 5", pageCount: 5)
        XCTAssertEqual(ranges, [0...1, 4...4])
        XCTAssertEqual(PageOps.split(d, mode: .ranges(ranges!)).map(\.name), ["pages 1-2", "page 5"])
        XCTAssertNil(PageOps.parseRanges("3-9", pageCount: 5))
        XCTAssertNil(PageOps.parseRanges("x", pageCount: 5))
    }

    func testStampTokensAndBates() throws {
        var stamp = PageOps.Stamp(template: "{bates} · {page}/{total} · {file}", position: .topRight, firstNumber: 7,
                                  batesPrefix: "ACME", batesDigits: 4)
        XCTAssertEqual(stamp.text(pageIndex: 1, total: 3, fileName: "brief"), "ACME0008 · 8/9 · brief")
        stamp.template = "{page}"
        let d = doc(["a", "b", "c"])
        let added = PageOps.addStamp(stamp, to: d, pages: [0, 2], fileName: "x")
        XCTAssertEqual(added.count, 2)
        XCTAssertGreaterThan(added[0].annotation.bounds.minY, 700, "top position")
        XCTAssertEqual(PageOps.removeStamps(from: d).count, 2)
    }
}
