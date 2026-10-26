import AppKit
import PDFKit
import XCTest
@testable import PagecraftCore

final class RichAnnotationTests: XCTestCase {
    private func roundTrip(_ doc: PDFDocument) throws -> PDFDocument {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(doc.write(to: url))
        return try XCTUnwrap(PDFDocument(url: url))
    }

    private func redPixels(_ page: PDFPage, in rect: CGRect) -> Int {
        guard let cg = PDFOps.renderImage(page, scale: 1) else { return 0 }
        let rep = NSBitmapImageRep(cgImage: cg)
        var n = 0
        for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: 3) {
            for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: 3) {
                if let c = rep.colorAt(x: x, y: rep.pixelsHigh - y), c.redComponent > 0.7, c.greenComponent < 0.35 { n += 1 }
            }
        }
        return n
    }

    func testImageAnnotationPersists() throws {
        let doc = PDFOpsTests().makeTextDocument(["image"])
        let red = NSImage(size: NSSize(width: 50, height: 50), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }
        doc.page(at: 0)?.addAnnotation(ImageAnnotation(image: red, bounds: CGRect(x: 100, y: 100, width: 100, height: 100)))
        let back = try roundTrip(doc)
        let page = try XCTUnwrap(back.page(at: 0))
        XCTAssertEqual(page.annotations.count, 1)
        XCTAssertGreaterThan(redPixels(page, in: CGRect(x: 110, y: 110, width: 80, height: 80)), 100)
    }

    func testTextStampPersists() throws {
        let doc = PDFOpsTests().makeTextDocument(["stamp"])
        let stamp = TextStampAnnotation.make(title: "REJECTED", subtitle: "by QA", tint: .red, at: CGPoint(x: 300, y: 300))
        doc.page(at: 0)?.addAnnotation(stamp)
        let back = try roundTrip(doc)
        let page = try XCTUnwrap(back.page(at: 0))
        XCTAssertEqual(page.annotations.first?.contents, "REJECTED · by QA")
        XCTAssertGreaterThan(redPixels(page, in: stamp.bounds), 20)
    }

    func testPolygonClosesPath() throws {
        let a = try XCTUnwrap(Annotations.polyline([.zero, CGPoint(x: 100, y: 0), CGPoint(x: 50, y: 80)], closed: true, color: .blue, lineWidth: 2))
        XCTAssertEqual(a.type, "Ink")
        XCTAssertEqual(a.paths?.first?.elementCount, 4)
        XCTAssertNil(Annotations.polyline([.zero], closed: false, color: .blue, lineWidth: 2))
    }

    func testLineStyleRoundTrips() {
        let a = Annotations.shape(.rectangle, from: .zero, to: CGPoint(x: 10, y: 10), color: .red, lineWidth: 3)
        Annotations.setLineStyle(.dotted, of: a)
        XCTAssertEqual(Annotations.lineStyle(of: a), .dotted)
        XCTAssertEqual(a.border?.lineWidth, 3)
        Annotations.setLineStyle(.dashed, of: a)
        XCTAssertEqual(Annotations.lineStyle(of: a), .dashed)
    }

    func testReorder() {
        let page = PDFOps.blankPage()
        let a = Annotations.shape(.rectangle, from: .zero, to: CGPoint(x: 10, y: 10), color: .red, lineWidth: 1)
        let b = Annotations.shape(.oval, from: .zero, to: CGPoint(x: 10, y: 10), color: .red, lineWidth: 1)
        page.addAnnotation(a); page.addAnnotation(b)
        Annotations.reorder(b, on: page, toFront: false)
        XCTAssertTrue(page.annotations.first === b)
        Annotations.reorder(b, on: page, toFront: true)
        XCTAssertTrue(page.annotations.last === b)
    }

    func testTypedSignatureAndLibrary() throws {
        let typed = try XCTUnwrap(SavedSignature.typed("Jane Doe", font: NSFont(name: "Snell Roundhand", size: 40) ?? .systemFont(ofSize: 40)))
        XCTAssertGreaterThan(typed.aspectRatio, 2)
        let a = try XCTUnwrap(typed.annotation(center: CGPoint(x: 200, y: 200), width: 150, color: .black))
        XCTAssertEqual(a.bounds.width, 150, accuracy: 0.5)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "pagecraft-sig-tests"))
        SignatureLibrary.save([typed], defaults)
        XCTAssertEqual(SignatureLibrary.load(defaults).map(\.id), [typed.id])
        defaults.removePersistentDomain(forName: "pagecraft-sig-tests")
    }
}

final class MultiLineMarkupTests: XCTestCase {
    func testOneHighlightCoversSeveralLines() throws {
        let doc = PDFOpsTests().makeTextDocument(["First line of text"])
        let page = try XCTUnwrap(doc.page(at: 0))
        let lines = [CGRect(x: 72, y: 700, width: 200, height: 20), CGRect(x: 72, y: 676, width: 120, height: 20)]
        let a = try XCTUnwrap(Annotations.markup(.highlight, lines: lines, color: .yellow))
        XCTAssertEqual(a.bounds, CGRect(x: 72, y: 676, width: 200, height: 44))
        XCTAssertEqual(Annotations.lineRects(of: a), lines)
        page.addAnnotation(a)
        XCTAssertTrue(Annotations.markedText(a, on: page)?.contains("First line") ?? false)
        XCTAssertNil(Annotations.markup(.highlight, lines: [], color: .yellow))
    }
}
