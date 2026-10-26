import AppKit
import PDFKit
import XCTest
@testable import PDFYahoCore

final class ConvertMeasureTests: XCTestCase {
    private func write(_ text: String, ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testLongTextPaginates() throws {
        let body = (1...400).map { "Paragraph \($0): the quick brown fox jumps over the lazy dog." }.joined(separator: "\n")
        let url = try write(body, ext: "txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let doc = try Convert.document(from: url)
        XCTAssertGreaterThan(doc.pageCount, 3)
        XCTAssertTrue(doc.page(at: 0)?.string?.contains("Paragraph 1:") ?? false)
        XCTAssertTrue(doc.page(at: doc.pageCount - 1)?.string?.contains("Paragraph 400") ?? false)
    }

    func testHTMLAndMarkdownConvert() throws {
        let html = try write("<h1>Title</h1><p>Hello <b>world</b></p>", ext: "html")
        let md = try write("Some **bold** text", ext: "md")
        defer { [html, md].forEach { try? FileManager.default.removeItem(at: $0) } }
        XCTAssertTrue(try Convert.document(from: html).page(at: 0)?.string?.contains("Hello world") ?? false)
        XCTAssertTrue(try Convert.document(from: md).page(at: 0)?.string?.contains("Some bold text") ?? false)
    }

    func testWordRoundTrip() throws {
        let source = PDFOpsTests().makeTextDocument(["From Word"])
        let data = try XCTUnwrap(PDFOps.exportData(source, as: .word))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".docx")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(try Convert.document(from: url).page(at: 0)?.string?.contains("From Word") ?? false)
    }

    func testMeasurements() {
        let scale = Measure.Scale(unit: .mm, ratio: 1)
        XCTAssertEqual(scale.length(72), 25.4, accuracy: 0.001)
        XCTAssertEqual(Measure.Scale(unit: .m, ratio: 100).length(72), 2.54, accuracy: 0.001)
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 72, y: 0), CGPoint(x: 72, y: 72), CGPoint(x: 0, y: 72)]
        XCTAssertEqual(Measure.area(square), 5184, accuracy: 0.01)
        XCTAssertEqual(Measure.perimeter(square, closed: true), 288, accuracy: 0.01)
        XCTAssertEqual(Measure.Scale(unit: .inch).format(area: 5184), "1.00 in²")
    }
}
