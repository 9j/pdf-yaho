import PDFKit
import XCTest
@testable import PagecraftCore

final class PageLabelTests: XCTestCase {
    private func document(pages: Int) -> PDFDocument {
        let doc = PDFDocument()
        for i in 0..<pages { doc.insert(PDFOps.blankPage(), at: i) }
        return PDFDocument(data: doc.dataRepresentation()!)!
    }

    private let ranges = [
        PageLabelRange(startPage: 0, style: .lowerRoman),
        PageLabelRange(startPage: 3, style: .decimal, prefix: "A-", firstNumber: 5),
        PageLabelRange(startPage: 5, style: .upperLetters, prefix: "부록 "),
    ]

    func testFormatting() {
        XCTAssertEqual(PageLabels.roman(1994), "MCMXCIV")
        XCTAssertEqual(PageLabels.letters(27), "AA")
        XCTAssertEqual(PageLabels.label(forPage: 2, in: ranges), "iii")
        XCTAssertEqual(PageLabels.label(forPage: 4, in: ranges), "A-6")
        XCTAssertEqual(PageLabels.label(forPage: 5, in: ranges), "부록 A")
        XCTAssertNil(PageLabels.label(forPage: 0, in: []))
    }

    func testWriteAndReadBack() throws {
        let doc = document(pages: 6)
        let data = try XCTUnwrap(PDFOps.data(doc, options: PDFOps.WriteOptions(pageLabels: ranges)))
        let back = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(back.pageCount, 6)
        XCTAssertEqual(PageLabels.read(from: back), ranges)
        XCTAssertEqual(back.page(at: 1)?.label, "ii")
        XCTAssertEqual(back.page(at: 3)?.label, "A-5")
        XCTAssertEqual(back.page(at: 5)?.label, "부록 A")
    }

    func testReplacingAndClearingLabels() throws {
        let first = try XCTUnwrap(PDFOps.data(document(pages: 4), options: PDFOps.WriteOptions(pageLabels: ranges)))
        let relabelled = try XCTUnwrap(PDFOps.data(PDFDocument(data: first)!, options: PDFOps.WriteOptions(pageLabels: [PageLabelRange(startPage: 0, style: .upperRoman)])))
        XCTAssertEqual(PageLabels.read(from: PDFDocument(data: relabelled)!), [PageLabelRange(startPage: 0, style: .upperRoman)])
        let cleared = try XCTUnwrap(PDFOps.data(PDFDocument(data: relabelled)!, options: PDFOps.WriteOptions(pageLabels: [])))
        XCTAssertEqual(PageLabels.read(from: PDFDocument(data: cleared)!), [])
    }

    func testLabelsSurviveEncryption() throws {
        let options = PDFOps.WriteOptions(userPassword: "pw", pageLabels: ranges)
        let data = try XCTUnwrap(PDFOps.data(document(pages: 6), options: options))
        let back = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertTrue(back.isLocked)
        XCTAssertTrue(back.unlock(withPassword: "pw"))
        XCTAssertEqual(back.page(at: 4)?.label, "A-6")
        XCTAssertEqual(back.page(at: 5)?.label, "부록 A")

        let ownerOnly = try XCTUnwrap(PDFOps.data(document(pages: 6), options: PDFOps.WriteOptions(ownerPassword: "owner", pageLabels: ranges)))
        let ownerDoc = try XCTUnwrap(PDFDocument(data: ownerOnly))  // a page's label needs its document alive
        XCTAssertEqual(ownerDoc.page(at: 5)?.label, "부록 A")
    }

    func testRemovingKeyKeepsOtherEntries() {
        let dict = "<< /Type /Catalog /PageLabels 12 0 R /Pages 2 0 R /Names << /Dests (x) >> >>"
        let out = PageLabels.removingKey("PageLabels", from: dict)
        XCTAssertFalse(out.contains("PageLabels"))
        XCTAssertTrue(out.contains("/Pages 2 0 R"))
        XCTAssertTrue(out.contains("/Names << /Dests (x) >>"))
    }
}
