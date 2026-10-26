import AppKit
import PDFKit
import XCTest
@testable import PagecraftCore

/// Scan enhancement, spread splitting, page clipboard and drawing constraints.
final class PageToolsTests: XCTestCase {
    private func roundTrip(_ doc: PDFDocument) throws -> PDFDocument {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(doc.write(to: url))
        return try XCTUnwrap(PDFDocument(url: url))
    }

    /// A US Letter "scan": tinted paper with mid-gray ink, plus an optional shadow gradient.
    private func scan(paper: NSColor, ink: NSColor) -> PDFPage {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: PDFOps.letter)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        ctx.setFillColor(paper.cgColor)
        ctx.fill(box)
        ctx.setFillColor(ink.cgColor)
        ctx.fill(CGRect(x: 100, y: 500, width: 200, height: 30))
        ctx.endPDFPage()
        ctx.closePDF()
        return PDFOps.page(fromPDFData: data as Data)!
    }

    private func pixel(_ page: PDFPage, x: Int, topDownY: Int) -> NSColor {
        let rep = NSBitmapImageRep(cgImage: PDFOps.renderImage(page, scale: 1)!)
        return rep.colorAt(x: x, y: topDownY)!.usingColorSpace(.sRGB)!
    }

    // MARK: Enhance

    func testEnhanceColorWhitensPaperAndDarkensInk() throws {
        let page = scan(paper: NSColor(srgbRed: 0.86, green: 0.82, blue: 0.68, alpha: 1), ink: NSColor(srgbRed: 0.45, green: 0.45, blue: 0.5, alpha: 1))
        let out = try XCTUnwrap(PageOps.enhanced(page, mode: .color))
        XCTAssertEqual(out.bounds(for: .mediaBox).size.width, 612, accuracy: 0.6)
        XCTAssertEqual(out.bounds(for: .mediaBox).size.height, 792, accuracy: 0.6)
        let paper = pixel(out, x: 20, topDownY: 20)
        XCTAssertGreaterThan(paper.redComponent, 0.97)
        XCTAssertGreaterThan(paper.greenComponent, 0.97)
        XCTAssertGreaterThan(paper.blueComponent, 0.97, "tint removed")
        let ink = pixel(out, x: 150, topDownY: 792 - 515)
        XCTAssertLessThan(ink.redComponent, 0.4)
        XCTAssertGreaterThan(paper.brightnessComponent - ink.brightnessComponent, 0.5)
    }

    func testEnhanceGrayscaleIsGray() throws {
        let page = scan(paper: NSColor(srgbRed: 0.8, green: 0.75, blue: 0.6, alpha: 1), ink: NSColor(srgbRed: 0.6, green: 0.2, blue: 0.2, alpha: 1))
        let out = try XCTUnwrap(PageOps.enhanced(page, mode: .grayscale))
        for (x, y) in [(20, 20), (150, 792 - 515)] {
            let c = pixel(out, x: x, topDownY: y)
            XCTAssertEqual(c.redComponent, c.greenComponent, accuracy: 0.02)
            XCTAssertEqual(c.greenComponent, c.blueComponent, accuracy: 0.02)
        }
        XCTAssertGreaterThan(pixel(out, x: 20, topDownY: 20).redComponent, 0.97)
    }

    func testEnhanceBlackAndWhiteIsBilevel() throws {
        let page = scan(paper: NSColor(white: 0.78, alpha: 1), ink: NSColor(white: 0.4, alpha: 1))
        let out = try XCTUnwrap(PageOps.enhanced(page, mode: .blackAndWhite))
        let rep = NSBitmapImageRep(cgImage: PDFOps.renderImage(out, scale: 1)!)
        var middle = 0, dark = 0, white = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
                let v = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!.brightnessComponent
                if v < 0.1 { dark += 1 } else if v > 0.9 { white += 1 } else { middle += 1 }
            }
        }
        XCTAssertGreaterThan(dark, 100, "the ink block turns black")
        XCTAssertGreaterThan(white, dark * 20)
        XCTAssertLessThan(middle, (dark + white) / 50, "almost no gray left; only anti-aliased edges")
    }

    func testEnhanceBlackAndWhiteSurvivesUnevenLighting() throws {
        // Left half in shadow: a global threshold would blacken it.
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: PDFOps.letter)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor(white: 0.88, alpha: 1).cgColor); ctx.fill(box)
        ctx.setFillColor(NSColor(white: 0.58, alpha: 1).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 306, height: 792))
        ctx.setFillColor(NSColor(white: 0.2, alpha: 1).cgColor); ctx.fill(CGRect(x: 100, y: 500, width: 100, height: 20))
        ctx.endPDFPage(); ctx.closePDF()
        let out = try XCTUnwrap(PageOps.enhanced(try XCTUnwrap(PDFOps.page(fromPDFData: data as Data)), mode: .blackAndWhite))
        XCTAssertGreaterThan(pixel(out, x: 50, topDownY: 100).brightnessComponent, 0.9, "shadowed paper stays white")
        XCTAssertGreaterThan(pixel(out, x: 500, topDownY: 100).brightnessComponent, 0.9)
        XCTAssertLessThan(pixel(out, x: 150, topDownY: 792 - 510).brightnessComponent, 0.1, "ink in shadow still black")
    }

    func testEnhanceKeepsSizeForRotatedAndDropsText() throws {
        let doc = PDFOpsTests().makeTextDocument(["findable"])
        let page = try XCTUnwrap(doc.page(at: 0))
        page.rotation = 90
        let out = try XCTUnwrap(PageOps.enhanced(page, mode: .color))
        XCTAssertEqual(out.bounds(for: .mediaBox).width, 792, accuracy: 0.6)
        XCTAssertEqual(out.bounds(for: .mediaBox).height, 612, accuracy: 0.6)
        XCTAssertFalse(out.string?.contains("findable") ?? false, "page is an image now")
        // Survives a save and reopen as an image page.
        let holder = PDFDocument()
        holder.insert(out, at: 0)
        let back = try XCTUnwrap(roundTrip(holder).page(at: 0))
        XCTAssertEqual(back.bounds(for: .mediaBox).width, 792, accuracy: 0.6)
    }

    func testEnhanceFollowsCropBox() throws {
        let page = scan(paper: .white, ink: .black)  // ink block at x 100...300, y 500...530
        page.setBounds(CGRect(x: 50, y: 400, width: 300, height: 300), for: .cropBox)
        let out = try XCTUnwrap(PageOps.enhanced(page, mode: .grayscale))
        XCTAssertEqual(out.bounds(for: .mediaBox).size.width, 300, accuracy: 0.6)
        XCTAssertEqual(out.bounds(for: .mediaBox).size.height, 300, accuracy: 0.6)
        // Crop-box coordinates: ink spans x 50...250, y 100...130 from the bottom.
        XCTAssertLessThan(pixel(out, x: 150, topDownY: 300 - 115).brightnessComponent, 0.2)
        XCTAssertGreaterThan(pixel(out, x: 150, topDownY: 300 - 200).brightnessComponent, 0.9)
    }

    func testEnhanceRendersAtAbout200DPI() throws {
        let out = try XCTUnwrap(PageOps.enhanced(scan(paper: .white, ink: .black), mode: .grayscale))
        let image = try XCTUnwrap(PDFOps.renderImage(out, scale: 200.0 / 72))
        XCTAssertEqual(image.width, 1700, accuracy: 4)
        XCTAssertEqual(PageOps.enhanceDPI, 200)
    }

    // MARK: Split spread

    /// A landscape spread, 800x400, with distinct words on each half.
    private func spread(rotation: Int = 0) -> (PDFDocument, PDFPage) {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 800, height: 400)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for (text, x) in [("LEFTWORD", 100.0), ("RIGHTWORD", 500.0)] {
            (text as NSString).draw(at: CGPoint(x: x, y: 200), withAttributes: [.font: NSFont.systemFont(ofSize: 24)])
        }
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage(); ctx.closePDF()
        let doc = PDFDocument(data: data as Data)!
        let page = doc.page(at: 0)!
        page.rotation = rotation
        return (doc, page)
    }

    /// Characters whose glyph box centre lies inside the page's crop box (what a reader shows).
    private func text(in page: PDFPage) -> String {
        let crop = page.bounds(for: .cropBox)
        let full = (page.string ?? "") as NSString
        return (0..<page.numberOfCharacters).compactMap { i -> String? in
            let b = page.characterBounds(at: i)
            return crop.contains(CGPoint(x: b.midX, y: b.midY)) ? full.substring(with: NSRange(location: i, length: 1)) : nil
        }.joined()
    }

    func testSplitSpreadHalvesKeepVectorText() throws {
        let (doc, page) = spread()
        let halves = PageOps.splitSpread(page)
        withExtendedLifetime(doc) {}
        XCTAssertEqual(halves.count, 2)
        XCTAssertEqual(halves[0].bounds(for: .cropBox), CGRect(x: 0, y: 0, width: 400, height: 400))
        XCTAssertEqual(halves[1].bounds(for: .cropBox), CGRect(x: 400, y: 0, width: 400, height: 400))
        XCTAssertTrue(text(in: halves[0]).contains("LEFTWORD"))
        XCTAssertFalse(text(in: halves[0]).contains("RIGHTWORD"))
        XCTAssertTrue(text(in: halves[1]).contains("RIGHTWORD"))
        XCTAssertFalse(text(in: halves[1]).contains("LEFTWORD"))
        XCTAssertEqual(page.bounds(for: .cropBox).width, 800, "original untouched")
    }

    func testSplitSpreadHalvesOutliveTheSourceDocument() throws {
        func makeHalves() -> [PDFPage] {
            let (doc, page) = spread()
            defer { withExtendedLifetime(doc) {} }
            return PageOps.splitSpread(page)
        }
        let halves = makeHalves()
        XCTAssertTrue(text(in: halves[0]).contains("LEFTWORD"))
        XCTAssertTrue(text(in: halves[1]).contains("RIGHTWORD"))
        let out = PDFDocument()
        for (i, h) in halves.enumerated() { out.insert(h, at: i) }
        XCTAssertTrue(text(in: try XCTUnwrap(try roundTrip(out).page(at: 1))).contains("RIGHTWORD"))
    }

    func testSplitSpreadHalvesAreIndependentPagesThatSurviveSaving() throws {
        let (doc, page) = spread()
        let halves = PageOps.splitSpread(page)
        let out = PDFDocument()
        for (i, h) in halves.enumerated() { out.insert(h, at: i) }
        _ = doc  // source may be freed in the app; the halves must not depend on it for saving
        let back = try roundTrip(out)
        XCTAssertEqual(back.pageCount, 2)
        XCTAssertEqual(back.page(at: 0)?.bounds(for: .cropBox).width ?? 0, 400, accuracy: 0.5)
        XCTAssertEqual(back.page(at: 1)?.bounds(for: .cropBox).minX ?? 0, 400, accuracy: 0.5)
        XCTAssertTrue(text(in: try XCTUnwrap(back.page(at: 1))).contains("RIGHTWORD"))
        XCTAssertFalse(text(in: try XCTUnwrap(back.page(at: 1))).contains("LEFTWORD"))
        // Rendered pixels agree: ink only where the crop box shows it.
        func ink(_ p: PDFPage) -> Int {
            let image = p.thumbnail(of: CGSize(width: 400, height: 400), for: .cropBox)
            let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
            var n = 0
            for x in 0..<rep.pixelsWide { for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.brightnessComponent ?? 1) < 0.5 { n += 1 } }
            return n
        }
        XCTAssertGreaterThan(ink(try XCTUnwrap(back.page(at: 0))), 50)
        XCTAssertGreaterThan(ink(try XCTUnwrap(back.page(at: 1))), 50)
    }

    func testSplitSpreadAccountsForRotation() throws {
        // Rotated 90 degrees clockwise the bottom of the stored page is on the left.
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 400, height: 800)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        ctx.endPDFPage(); ctx.closePDF()
        let doc = PDFDocument(data: data as Data)!
        let page = doc.page(at: 0)!
        let bottom = CGRect(x: 0, y: 0, width: 400, height: 400), top = CGRect(x: 0, y: 400, width: 400, height: 400)
        let left = CGRect(x: 0, y: 0, width: 200, height: 800), right = CGRect(x: 200, y: 0, width: 200, height: 800)
        for (rotation, expected) in [(0, [left, right]), (90, [bottom, top]), (180, [right, left]), (270, [top, bottom])] {
            page.rotation = rotation
            let halves = PageOps.splitSpread(page)
            XCTAssertEqual(halves.map { $0.bounds(for: .cropBox) }, expected, "rotation \(rotation)")
            XCTAssertEqual(halves.map(\.rotation), [rotation, rotation])
        }
    }

    func testSplitSpreadRespectsCropBoxOffsetAndAnnotations() throws {
        let (_, page) = spread()
        page.setBounds(CGRect(x: 100, y: 50, width: 600, height: 300), for: .cropBox)
        let left = Annotations.shape(.rectangle, from: CGPoint(x: 120, y: 100), to: CGPoint(x: 180, y: 150), color: .red, lineWidth: 1)
        let right = Annotations.shape(.rectangle, from: CGPoint(x: 600, y: 100), to: CGPoint(x: 650, y: 150), color: .red, lineWidth: 1)
        page.addAnnotation(left); page.addAnnotation(right)
        let halves = PageOps.splitSpread(page)
        XCTAssertEqual(halves[0].bounds(for: .cropBox), CGRect(x: 100, y: 50, width: 300, height: 300))
        XCTAssertEqual(halves[1].bounds(for: .cropBox), CGRect(x: 400, y: 50, width: 300, height: 300))
        XCTAssertEqual(halves[0].annotations.count, 1)
        XCTAssertEqual(halves[1].annotations.count, 1)
        XCTAssertEqual(page.annotations.count, 2, "source page keeps its annotations")
    }

    // MARK: Page clipboard

    func testWritePagesRoundTripsThroughPasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("org.pagecraft.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let doc = PDFOpsTests().makeTextDocument(["alpha", "beta", "gamma"])
        let chosen = [try XCTUnwrap(doc.page(at: 2)), try XCTUnwrap(doc.page(at: 0))]
        XCTAssertTrue(PDFOps.writePages(chosen, to: pasteboard))
        XCTAssertNotNil(pasteboard.data(forType: .pdf))
        let pasted = PageOps.pages(from: pasteboard)
        XCTAssertEqual(pasted.count, 2)
        XCTAssertTrue(pasted[0].string?.contains("gamma") ?? false)
        XCTAssertTrue(pasted[1].string?.contains("alpha") ?? false)
        XCTAssertEqual(doc.pageCount, 3, "source untouched")
        XCTAssertFalse(PDFOps.writePages([], to: pasteboard))
    }

    func testWritePagesKeepsAnnotations() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("org.pagecraft.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let doc = PDFOpsTests().makeTextDocument(["note"])
        let page = try XCTUnwrap(doc.page(at: 0))
        page.addAnnotation(Annotations.shape(.rectangle, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 100, y: 100), color: .red, lineWidth: 2))
        XCTAssertTrue(PDFOps.writePages([page], to: pasteboard))
        XCTAssertEqual(PageOps.pages(from: pasteboard).first?.annotations.count, 1)
    }

    // MARK: Geometry

    private func angle(_ a: CGPoint, _ b: CGPoint) -> Double { Double(atan2(b.y - a.y, b.x - a.x)) * 180 / .pi }

    func testConstrainedLineSnapsTo45Degrees() {
        let start = CGPoint(x: 10, y: 20)
        func snap(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { Geometry.constrained(from: start, to: CGPoint(x: start.x + dx, y: start.y + dy), kind: .line) }
        let h = snap(100, 8)
        XCTAssertEqual(h.y, start.y, accuracy: 1e-9)
        XCTAssertEqual(h.x - start.x, hypot(100, 8), accuracy: 1e-9, "length kept")
        let v = snap(-3, 50)
        XCTAssertEqual(v.x, start.x, accuracy: 1e-9)
        XCTAssertEqual(v.y - start.y, hypot(3, 50), accuracy: 1e-9)
        let d = snap(60, 45)
        XCTAssertEqual(angle(start, d), 45, accuracy: 1e-9)
        XCTAssertEqual(hypot(d.x - start.x, d.y - start.y), 75, accuracy: 1e-9)
        XCTAssertEqual(angle(start, snap(-60, -70)), -135, accuracy: 1e-9)
        XCTAssertEqual(angle(start, snap(-60, 70)), 135, accuracy: 1e-9)
        XCTAssertEqual(angle(start, snap(40, -50)), -45, accuracy: 1e-9)
        XCTAssertEqual(snap(0, 0), start)
        XCTAssertEqual(abs(angle(start, snap(-100, 1))), 180, accuracy: 1e-9)
    }

    func testConstrainedBoxMakesSquares() {
        let s = CGPoint(x: 100, y: 100)
        XCTAssertEqual(Geometry.constrained(from: s, to: CGPoint(x: 160, y: 130), kind: .box), CGPoint(x: 160, y: 160))
        XCTAssertEqual(Geometry.constrained(from: s, to: CGPoint(x: 130, y: 40), kind: .box), CGPoint(x: 160, y: 40))
        XCTAssertEqual(Geometry.constrained(from: s, to: CGPoint(x: 40, y: 130), kind: .box), CGPoint(x: 40, y: 160))
        XCTAssertEqual(Geometry.constrained(from: s, to: CGPoint(x: 70, y: 20), kind: .box), CGPoint(x: 20, y: 20))
        XCTAssertEqual(Geometry.constrained(from: s, to: s, kind: .box), s)
    }
}
