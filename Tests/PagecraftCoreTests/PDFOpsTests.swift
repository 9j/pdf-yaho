import AppKit
import PDFKit
import XCTest
@testable import PagecraftCore

final class PDFOpsTests: XCTestCase {
    /// A document whose pages contain real, extractable text.
    func makeTextDocument(_ texts: [String]) -> PDFDocument {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: PDFOps.letter)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        for text in texts {
            ctx.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            (text as NSString).draw(at: CGPoint(x: 72, y: 700), withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return PDFDocument(data: data as Data)!
    }

    func testBlankPageHasRequestedSize() {
        let page = PDFOps.blankPage(size: PDFOps.a4)
        XCTAssertEqual(page.bounds(for: .mediaBox).size, PDFOps.a4)
    }

    func testMergeAndExtract() {
        let a = makeTextDocument(["alpha", "beta"])
        let b = makeTextDocument(["gamma"])
        let merged = PDFOps.merge([a, b])
        XCTAssertEqual(merged.pageCount, 3)
        XCTAssertEqual(a.pageCount, 2, "sources are untouched")
        let extracted = PDFOps.extract([2, 0], from: merged)
        XCTAssertEqual(extracted.pageCount, 2)
        XCTAssertTrue(extracted.page(at: 0)?.string?.contains("alpha") ?? false)
        XCTAssertTrue(extracted.page(at: 1)?.string?.contains("gamma") ?? false)
    }

    func testMoveAndSetPagesRoundTrip() {
        let doc = makeTextDocument(["one", "two", "three", "four"])
        let original = PDFOps.pages(of: doc)
        let moved = PDFOps.moved(original, from: IndexSet([0]), to: 3)
        PDFOps.setPages(moved, in: doc)
        XCTAssertEqual(PDFOps.pages(of: doc).compactMap { $0.string?.trimmingCharacters(in: .whitespacesAndNewlines) },
                       ["two", "three", "one", "four"])
        PDFOps.setPages(original, in: doc)
        XCTAssertEqual(PDFOps.pages(of: doc), original)
    }

    func testMoveToEnd() {
        let pages = (0..<3).map { _ in PDFPage() }
        XCTAssertEqual(PDFOps.moved(pages, from: IndexSet([0]), to: 3), [pages[1], pages[2], pages[0]])
        XCTAssertEqual(PDFOps.moved(pages, from: IndexSet([2]), to: 0), [pages[2], pages[0], pages[1]])
    }

    func testPageNumbersAddAndRemove() {
        let doc = makeTextDocument(["a", "b", "c"])
        let added = PDFOps.addPageNumbers(to: doc)
        XCTAssertEqual(added.count, 3)
        XCTAssertEqual(added[1].annotation.contents, "2 / 3")
        XCTAssertEqual(PDFOps.removePageNumbers(from: doc).count, 3)
        XCTAssertTrue(PDFOps.pages(of: doc).allSatisfy { $0.annotations.isEmpty })
    }

    func testTextAndMarkdownExport() {
        let doc = makeTextDocument(["Hello world", "Second page"])
        XCTAssertTrue(PDFOps.plainText(doc).contains("Hello world"))
        let md = PDFOps.markdown(doc, title: "Doc")
        XCTAssertTrue(md.hasPrefix("# Doc"))
        XCTAssertTrue(md.contains("## Page 2\n\nSecond page"))
    }

    func testRasterizeRemovesTextAndKeepsSize() throws {
        let doc = makeTextDocument(["Secret account 1234"])
        let page = try XCTUnwrap(doc.page(at: 0))
        page.addAnnotation(Annotations.redaction(bounds: CGRect(x: 60, y: 690, width: 300, height: 30)))
        let flat = try XCTUnwrap(PDFOps.rasterized(page))
        XCTAssertEqual(flat.bounds(for: .mediaBox).size, PDFOps.letter)
        XCTAssertFalse(flat.string?.contains("Secret") ?? false)
    }

    func testRenderHonoursRotation() throws {
        let page = PDFOps.blankPage()
        page.rotation = 90
        let image = try XCTUnwrap(PDFOps.renderImage(page, scale: 1))
        XCTAssertEqual(image.width, 792)
        XCTAssertEqual(image.height, 612)
    }

    func testFlattenedWriteBurnsInAnnotations() throws {
        let doc = makeTextDocument(["x"])
        doc.page(at: 0)?.addAnnotation(Annotations.shape(.rectangle, from: .init(x: 10, y: 10), to: .init(x: 100, y: 100),
                                                          color: .red, lineWidth: 2))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(PDFOps.write(doc, to: url, options: .init(flatten: true)))
        let reread = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertTrue(reread.page(at: 0)?.annotations.isEmpty ?? false)
    }

    func testPasswordWrite() throws {
        let doc = makeTextDocument(["x"])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(PDFOps.write(doc, to: url, options: .init(userPassword: "hunter2")))
        let reread = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertTrue(reread.isLocked)
        XCTAssertTrue(reread.unlock(withPassword: "hunter2"))
    }

    func testImagesBecomePages() {
        let image = NSImage(size: NSSize(width: 200, height: 100), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        XCTAssertEqual(PDFOps.document(fromImages: [image, image]).pageCount, 2)
    }
}

final class AnnotationTests: XCTestCase {
    func testInkPathsAreRelativeToBounds() throws {
        let ink = try XCTUnwrap(Annotations.ink(strokes: [[CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 150)]],
                                                color: .red, lineWidth: 2))
        XCTAssertTrue(ink.bounds.contains(CGPoint(x: 100, y: 100)))
        XCTAssertTrue(ink.bounds.contains(CGPoint(x: 200, y: 150)))
        let pathBounds = try XCTUnwrap(ink.paths?.first?.bounds)
        XCTAssertLessThan(pathBounds.minX, 10, "path is in annotation space, not page space")
    }

    func testArrowEndpoints() {
        let start = CGPoint(x: 50, y: 60), end = CGPoint(x: 150, y: 20)
        let a = Annotations.shape(.arrow, from: start, to: end, color: .blue, lineWidth: 2)
        XCTAssertEqual(a.type, "Line")
        XCTAssertEqual(a.endLineStyle, .openArrow)
        XCTAssertEqual(a.startPoint + a.bounds.origin, start)
        XCTAssertEqual(a.endPoint + a.bounds.origin, end)
    }

    func testEditableClassification() {
        let widget = PDFAnnotation(bounds: .zero, forType: .widget, withProperties: nil)
        XCTAssertFalse(Annotations.isUserEditable(widget))
        XCTAssertTrue(Annotations.isUserEditable(Annotations.note("hi", at: .zero, color: .yellow)))
        XCTAssertEqual(Annotations.displayName(Annotations.redaction(bounds: .zero)), "Redaction")
    }

    func testSignatureNormalisesAndPlaces() throws {
        let sig = try XCTUnwrap(Signature(viewStrokes: [[CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 60)]], viewHeight: 100))
        XCTAssertEqual(sig.aspectRatio, 2, accuracy: 0.001)
        let a = try XCTUnwrap(sig.annotation(center: CGPoint(x: 300, y: 300), width: 160, color: .black))
        XCTAssertEqual(a.bounds.midX, 300, accuracy: 1)
        XCTAssertEqual(a.bounds.midY, 300, accuracy: 1)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "pagecraft-tests"))
        SignatureStore.save(sig, defaults)
        XCTAssertEqual(SignatureStore.load(defaults), sig)
        SignatureStore.save(nil, defaults)
        XCTAssertNil(SignatureStore.load(defaults))
    }
}
