import AppKit
import PDFKit
import XCTest
@testable import PagecraftCore

/// Squiggly, callout, cloud, line styles and line endings.
final class MarkupShapeTests: XCTestCase {
    private func roundTrip(_ doc: PDFDocument) throws -> PDFDocument {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(doc.write(to: url))
        return try XCTUnwrap(PDFDocument(url: url))
    }

    /// Counts red pixels on a grid, page coordinates (origin bottom-left).
    private func count(_ page: PDFPage, in rect: CGRect, step: Int = 1, where match: (NSColor) -> Bool = { $0.redComponent > 0.7 && $0.greenComponent < 0.4 && $0.blueComponent < 0.4 }) -> Int {
        guard let cg = PDFOps.renderImage(page, scale: 1) else { return 0 }
        let rep = NSBitmapImageRep(cgImage: cg)
        var n = 0
        for x in stride(from: max(0, Int(rect.minX)), to: min(rep.pixelsWide, Int(rect.maxX)), by: step) {
            for y in stride(from: max(0, Int(rect.minY)), to: min(rep.pixelsHigh, Int(rect.maxY)), by: step) {
                if let c = rep.colorAt(x: x, y: rep.pixelsHigh - 1 - y)?.usingColorSpace(.sRGB), match(c) { n += 1 }
            }
        }
        return n
    }

    private func page(_ text: String = "Hello squiggly world") -> (PDFDocument, PDFPage) {
        let doc = PDFOpsTests().makeTextDocument([text])
        return (doc, doc.page(at: 0)!)
    }

    // MARK: Squiggly

    func testPlainPDFKitSquigglyDoesNotRender() {
        let (_, p) = page()
        let plain = PDFAnnotation(bounds: CGRect(x: 72, y: 690, width: 150, height: 24), forType: PDFAnnotationSubtype(rawValue: "Squiggly"), withProperties: nil)
        plain.color = .red
        p.addAnnotation(plain)
        XCTAssertEqual(count(p, in: CGRect(x: 60, y: 680, width: 200, height: 50)), 0, "documents why SquigglyAnnotation exists")
    }

    func testSquigglyDrawsAndPersists() throws {
        let (doc, p) = page()
        let area = CGRect(x: 72, y: 690, width: 150, height: 24)
        let a = Annotations.squiggly(bounds: area, color: .red)
        XCTAssertEqual(a.type, "Squiggly")
        p.addAnnotation(a)
        XCTAssertGreaterThan(count(p, in: area), 80)
        // The wave hugs the bottom of the bounds.
        XCTAssertEqual(count(p, in: CGRect(x: 72, y: 705, width: 150, height: 9)), 0)

        let back = try XCTUnwrap(roundTrip(doc).page(at: 0))
        XCTAssertEqual(back.annotations.first?.type, "Squiggly")
        XCTAssertGreaterThan(count(back, in: area), 80)
    }

    func testSquigglyIsTreatedAsMarkup() throws {
        let (doc, p) = page("Hello squiggly world")
        let a = Annotations.squiggly(bounds: CGRect(x: 70, y: 695, width: 200, height: 24), color: .systemRed)
        p.addAnnotation(a)
        XCTAssertEqual(Annotations.displayName(a), "Squiggly")
        XCTAssertTrue(Annotations.isMarkup(a))
        XCTAssertTrue(Annotations.isUserEditable(a))
        XCTAssertTrue(Annotations.markedText(a, on: p)?.contains("Hello") ?? false)
        let xfdf = PDFOps.xfdf(doc, fileName: "x.pdf")
        XCTAssertTrue(xfdf.contains("<squiggly "), xfdf)
        XCTAssertTrue(xfdf.contains("coords="))
        let copy = try XCTUnwrap(Annotations.duplicate(a))
        XCTAssertTrue(copy is SquigglyAnnotation)
        XCTAssertEqual(copy.bounds, a.bounds.offsetBy(dx: 12, dy: -12))
    }

    // MARK: Callout

    private func makeCallout() -> CalloutAnnotation {
        CalloutAnnotation.make(text: "Check this", box: CGRect(x: 300, y: 500, width: 140, height: 40),
                               anchor: CGPoint(x: 150, y: 300), color: .red, fontSize: 14)
    }

    func testCalloutProperties() {
        let c = makeCallout()
        XCTAssertEqual(c.type, "Stamp")
        XCTAssertEqual(c.box, CGRect(x: 300, y: 500, width: 140, height: 40))
        XCTAssertEqual(c.anchor, CGPoint(x: 150, y: 300))
        XCTAssertTrue(c.bounds.contains(c.box) && c.bounds.contains(c.anchor))
        XCTAssertEqual(c.text, "Check this")
        XCTAssertEqual(c.fontSize, 14)
        XCTAssertEqual(Annotations.displayName(c), "Callout")
        XCTAssertTrue(Annotations.isResizable(c) && Annotations.isMovable(c))

        c.text = "Changed"
        c.fontSize = 18
        c.anchor = CGPoint(x: 500, y: 700)
        Annotations.setColor(.blue, of: c)
        XCTAssertEqual(c.contents, "Changed")
        XCTAssertEqual(c.fontSize, 18)
        XCTAssertEqual(c.anchor, CGPoint(x: 500, y: 700))
        XCTAssertEqual(c.box, CGRect(x: 300, y: 500, width: 140, height: 40), "moving the anchor leaves the box")
        XCTAssertTrue(c.bounds.contains(CGPoint(x: 500, y: 700)))
        XCTAssertEqual(Annotations.color(of: c).usingColorSpace(.sRGB)?.blueComponent ?? 0, 1, accuracy: 0.01)
    }

    func testCalloutCopyAndDuplicate() throws {
        let c = makeCallout()
        let copy = try XCTUnwrap(c.copy() as? CalloutAnnotation)
        XCTAssertEqual(copy.box, c.box)
        XCTAssertEqual(copy.anchor, c.anchor)
        XCTAssertEqual(copy.text, c.text)
        XCTAssertEqual(copy.fontSize, c.fontSize)
        XCTAssertEqual(copy.color.usingColorSpace(.sRGB)?.redComponent ?? 0, 1, accuracy: 0.01)
        copy.text = "other"
        XCTAssertEqual(c.text, "Check this", "copies are independent")

        let dup = try XCTUnwrap(Annotations.duplicate(c) as? CalloutAnnotation)
        XCTAssertEqual(dup.box, c.box.offsetBy(dx: 12, dy: -12))
        XCTAssertEqual(dup.anchor, c.anchor + CGPoint(x: 12, y: -12), "box and anchor move together")
    }

    func testCalloutMoveKeepsShape() {
        let c = makeCallout()
        let box = c.box, anchor = c.anchor
        c.bounds = c.bounds.offsetBy(dx: 20, dy: -10)
        XCTAssertEqual(c.box, box.offsetBy(dx: 20, dy: -10))
        XCTAssertEqual(c.anchor, anchor + CGPoint(x: 20, y: -10))
    }

    func testCalloutResizeScalesBoxAndPinsAnchor() {
        let c = makeCallout()
        let anchor = c.anchor, old = c.bounds, oldBox = c.box
        let target = CGRect(x: old.minX + 40, y: old.minY, width: old.width * 1.5, height: old.height * 0.5)
        Annotations.resize(c, to: target)
        XCTAssertEqual(c.anchor.x, anchor.x, accuracy: 0.001)
        XCTAssertEqual(c.anchor.y, anchor.y, accuracy: 0.001)
        XCTAssertEqual(c.box.width, oldBox.width * 1.5, accuracy: 0.001)
        XCTAssertEqual(c.box.height, oldBox.height * 0.5, accuracy: 0.001)
        XCTAssertEqual(c.box.minX, target.minX + (oldBox.minX - old.minX) * 1.5, accuracy: 0.001)
        XCTAssertEqual(c.box.minY, target.minY + (oldBox.minY - old.minY) * 0.5, accuracy: 0.001)
        XCTAssertTrue(c.bounds.contains(c.box) && c.bounds.contains(c.anchor))
    }

    func testCalloutPersistsVisuallyAndRestores() throws {
        let (doc, p) = page("x")
        let c = makeCallout()
        p.addAnnotation(c)
        XCTAssertGreaterThan(count(p, in: c.bounds), 100, "box border, leader and arrow are drawn")
        // Pixels along the leader midway between the box and the anchor.
        let probe = CGRect(x: 235, y: 385, width: 30, height: 30)
        XCTAssertGreaterThan(count(p, in: probe), 3)

        let back = try roundTrip(doc)
        let reopened = try XCTUnwrap(back.page(at: 0))
        XCTAssertEqual(reopened.annotations.count, 1)
        XCTAssertGreaterThan(count(reopened, in: c.bounds), 100)
        XCTAssertGreaterThan(count(reopened, in: probe), 3)
        XCTAssertEqual(reopened.annotations[0].contents, "Check this")

        // Reopened, it is a plain stamp until restored into an editable callout.
        XCTAssertFalse(reopened.annotations[0] is CalloutAnnotation)
        XCTAssertEqual(Annotations.restoreCustomAnnotations(on: reopened), 1)
        let restored = try XCTUnwrap(reopened.annotations.first as? CalloutAnnotation)
        XCTAssertEqual(restored.box, c.box)
        XCTAssertEqual(restored.anchor, c.anchor)
        XCTAssertEqual(restored.fontSize, 14)
        XCTAssertEqual(restored.text, "Check this")
        restored.text = "Edited"
        XCTAssertEqual(Annotations.restoreCustomAnnotations(on: reopened), 0)
        XCTAssertEqual(reopened.annotations.count, 1)
    }

    // MARK: Cloud

    func testCloudDrawsScallopedBorder() throws {
        let (_, p) = page("x")
        let rect = CGRect(x: 100, y: 400, width: 200, height: 120)
        let cloud = Annotations.cloud(rect: rect, color: .red, lineWidth: 2)
        p.addAnnotation(cloud)
        XCTAssertEqual(Annotations.displayName(cloud), "Cloud")
        XCTAssertTrue(cloud.bounds.contains(rect))
        XCTAssertGreaterThan(count(p, in: cloud.bounds), 300)
        XCTAssertEqual(count(p, in: rect.insetBy(dx: 25, dy: 25)), 0, "no fill unless asked")
        // Scallops bulge outward past the rectangle's edge.
        XCTAssertGreaterThan(count(p, in: CGRect(x: rect.minX, y: rect.maxY + 1, width: rect.width, height: 8)), 20)
    }

    func testCloudPersistsWithFillAndRestores() throws {
        let (doc, p) = page("x")
        let cloud = try XCTUnwrap(Annotations.cloudPolygon(
            points: [CGPoint(x: 100, y: 400), CGPoint(x: 300, y: 400), CGPoint(x: 250, y: 540), CGPoint(x: 120, y: 520)],
            color: .red, lineWidth: 2, fill: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)))
        p.addAnnotation(cloud)
        let isBlue: (NSColor) -> Bool = { $0.blueComponent > 0.7 && $0.redComponent < 0.3 }
        let inside = CGRect(x: 170, y: 440, width: 50, height: 40)
        XCTAssertGreaterThan(count(p, in: inside, where: isBlue), 1000)

        let reopened = try XCTUnwrap(roundTrip(doc).page(at: 0))
        XCTAssertGreaterThan(count(reopened, in: cloud.bounds), 300)
        XCTAssertGreaterThan(count(reopened, in: inside, where: isBlue), 1000, "fill persists")

        XCTAssertEqual(Annotations.restoreCustomAnnotations(on: reopened), 1)
        let restored = try XCTUnwrap(reopened.annotations.first as? CloudAnnotation)
        XCTAssertEqual(restored.vertices.count, 4)
        XCTAssertEqual(restored.vertices[0].x, 100, accuracy: 0.01)
        XCTAssertEqual(restored.vertices[2].y, 540, accuracy: 0.01)
    }

    func testCloudPolygonNeedsThreePoints() {
        XCTAssertNil(Annotations.cloudPolygon(points: [.zero, CGPoint(x: 5, y: 5)], color: .red, lineWidth: 1))
    }

    func testCloudResizeAndDuplicate() throws {
        let cloud = try XCTUnwrap(Annotations.cloud(rect: CGRect(x: 100, y: 100, width: 100, height: 60), color: .red, lineWidth: 2) as? CloudAnnotation)
        let padding = cloud.bounds.width - 100
        let target = CGRect(x: 50, y: 60, width: 300 + padding, height: 180 + padding)
        Annotations.resize(cloud, to: target)
        XCTAssertEqual(cloud.bounds, target)
        let xs = cloud.vertices.map(\.x), ys = cloud.vertices.map(\.y)
        XCTAssertEqual(xs.max()! - xs.min()!, 300, accuracy: 0.01, "polygon scales, scallop padding does not")
        XCTAssertEqual(ys.max()! - ys.min()!, 180, accuracy: 0.01)
        XCTAssertEqual(xs.min()!, target.minX + padding / 2, accuracy: 0.01)
        let dup = try XCTUnwrap(Annotations.duplicate(cloud) as? CloudAnnotation)
        XCTAssertEqual(dup.vertices.first!.x, cloud.vertices.first!.x + 12, accuracy: 0.01)
    }

    func testCloudHonoursDashedBorder() throws {
        let (_, p) = page("x")
        let solid = Annotations.cloud(rect: CGRect(x: 100, y: 400, width: 200, height: 120), color: .red, lineWidth: 2)
        p.addAnnotation(solid)
        let solidCount = count(p, in: solid.bounds)
        Annotations.setLineStyle(.shortDashed, of: solid)
        XCTAssertLessThan(count(p, in: solid.bounds), solidCount)
    }

    // MARK: Line styles and endings

    func testAllLineStylesRoundTripInMemory() {
        for style in Annotations.LineStyle.allCases {
            let a = Annotations.shape(.rectangle, from: .zero, to: CGPoint(x: 10, y: 10), color: .red, lineWidth: 3)
            Annotations.setLineStyle(style, of: a)
            XCTAssertEqual(Annotations.lineStyle(of: a), style, "\(style)")
            XCTAssertEqual(a.border?.lineWidth, 3)
        }
        XCTAssertEqual(Set(Annotations.LineStyle.allCases.map(\.dashPattern)).count, Annotations.LineStyle.allCases.count)
        for legacy in [Annotations.LineStyle.solid, .dashed, .dotted] { XCTAssertTrue(Annotations.LineStyle.allCases.contains(legacy)) }
    }

    func testLineStylesSurviveSaveAndReopen() throws {
        let doc = PDFOpsTests().makeTextDocument(["x"])
        let p = try XCTUnwrap(doc.page(at: 0))
        let styles = Annotations.LineStyle.allCases
        for (i, style) in styles.enumerated() {
            let y = CGFloat(100 + i * 40)
            let a = Annotations.shape(.rectangle, from: CGPoint(x: 100, y: y), to: CGPoint(x: 200, y: y + 20), color: .red, lineWidth: 2)
            Annotations.setLineStyle(style, of: a)
            p.addAnnotation(a)
        }
        let back = try XCTUnwrap(roundTrip(doc).page(at: 0))
        XCTAssertEqual(back.annotations.map(Annotations.lineStyle(of:)), styles)
    }

    func testLineEndings() throws {
        XCTAssertEqual(Annotations.supportedLineEndings.map(\.style), [.none, .openArrow, .closedArrow, .circle, .square, .diamond])
        XCTAssertEqual(Set(Annotations.supportedLineEndings.map(\.displayName)).count, 6)
        XCTAssertTrue(Annotations.supportedLineEndings.allSatisfy { !$0.symbolName.isEmpty && NSImage(systemSymbolName: $0.symbolName, accessibilityDescription: nil) != nil })
        XCTAssertEqual(Annotations.LineEnding.of(.diamond).displayName, "Diamond")

        let doc = PDFOpsTests().makeTextDocument(["x"])
        let p = try XCTUnwrap(doc.page(at: 0))
        let line = Annotations.shape(.line, from: CGPoint(x: 100, y: 300), to: CGPoint(x: 300, y: 320), color: .red, lineWidth: 2)
        Annotations.setLineEndings(start: .circle, end: .closedArrow, of: line)
        XCTAssertEqual(line.startLineStyle, .circle)
        XCTAssertEqual(line.endLineStyle, .closedArrow)
        p.addAnnotation(line)
        let reopened = try XCTUnwrap(roundTrip(doc).page(at: 0)).annotations[0]
        XCTAssertEqual(reopened.startLineStyle, .circle)
        XCTAssertEqual(reopened.endLineStyle, .closedArrow)

        let rect = Annotations.shape(.rectangle, from: .zero, to: CGPoint(x: 10, y: 10), color: .red, lineWidth: 1)
        Annotations.setLineEndings(start: .circle, end: .circle, of: rect)
        XCTAssertEqual(rect.startLineStyle, .none, "only lines have endings")
    }
}
