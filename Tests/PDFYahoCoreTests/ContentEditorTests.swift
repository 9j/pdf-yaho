#if PDFIUM
import CoreText
import PDFKit
import XCTest
@testable import PDFYahoCore

final class ContentEditorTests: XCTestCase {
    static let paragraph = ["The quick brown fox jumps over", "the lazy dog while the editor", "keeps every line in one block."]

    /// A page with a heading, a three-line paragraph and a red square image.
    private func samplePage() -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        func draw(_ text: String, _ x: CGFloat, _ y: CGFloat, _ font: NSFont) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
            ctx.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, ctx)
        }
        draw("Quarterly Report", 72, 700, .boldSystemFont(ofSize: 24))
        for (i, line) in Self.paragraph.enumerated() { draw(line, 72, 640 - CGFloat(i) * 15, NSFont(name: "Helvetica", size: 12)!) }
        ctx.draw(Self.square(.red), in: CGRect(x: 72, y: 400, width: 100, height: 100))
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    static func square(_ color: NSColor) -> CGImage {
        let ctx = CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        return ctx.makeImage()!
    }

    private func text(of data: Data) -> String { PDFDocument(data: data)?.page(at: 0)?.string ?? "" }

    func testFindsParagraphsAndImages() throws {
        let blocks = ContentEditor.blocks(of: samplePage())
        let texts = blocks.filter { $0.kind == .text }
        XCTAssertEqual(texts.count, 2, "\(texts.map(\.text))")
        let heading = try XCTUnwrap(texts.first { $0.text == "Quarterly Report" })
        XCTAssertEqual(heading.style.fontSize, 24, accuracy: 1)
        XCTAssertTrue(heading.style.font.fontDescriptor.symbolicTraits.contains(.bold), heading.style.fontName)
        let body = try XCTUnwrap(texts.first { $0.text.hasPrefix("The quick") })
        XCTAssertEqual(body.text, Self.paragraph.joined(separator: " "))
        XCTAssertEqual(body.style.fontSize, 12, accuracy: 0.5)
        XCTAssertEqual(body.style.lineHeight ?? 0, 15, accuracy: 1)
        let image = try XCTUnwrap(blocks.first { $0.kind == .image })
        XCTAssertEqual(image.bounds.minX, 72, accuracy: 1)
        XCTAssertEqual(image.bounds.width, 100, accuracy: 1)
    }

    /// Browsers and word processors write words as separate pieces, out of order, with fallback fonts
    /// for other scripts; they still read as one paragraph in reading order.
    func testScatteredPiecesBecomeOneParagraph() throws {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        let latin = NSFont.systemFont(ofSize: 13), hangul = NSFont(name: "AppleSDGothicNeo-Regular", size: 13)!
        // (text, x, line) drawn deliberately out of order.
        let pieces: [(String, CGFloat, Int, NSFont)] = [
            ("PDF입니다.", 172, 0, hangul), ("이 문서는", 72, 0, hangul), ("일반", 140, 0, hangul),
            ("English", 150, 1, latin), ("두 번째 줄과", 72, 1, hangul), ("text.", 205, 1, latin),
        ]
        for (text, x, line, font) in pieces {
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
            ctx.textPosition = CGPoint(x: x, y: 700 - CGFloat(line) * 17)
            CTLineDraw(ctLine, ctx)
        }
        ctx.endPDFPage()
        ctx.closePDF()
        let blocks = ContentEditor.blocks(of: data as Data).filter { $0.kind == .text }
        XCTAssertEqual(blocks.count, 1, "\(blocks.map(\.text))")
        XCTAssertEqual(blocks.first?.text.replacingOccurrences(of: "\n", with: " "), "이 문서는 일반 PDF입니다. 두 번째 줄과 English text.")
    }

    func testReplaceTextWithAnyScriptAndEditAgain() throws {
        let page = samplePage()
        let body = try XCTUnwrap(ContentEditor.blocks(of: page).first { $0.text.hasPrefix("The quick") })
        let replaced = try XCTUnwrap(ContentEditor.replaceText(of: body, with: "분기 보고서 — edited", style: body.style, of: page))
        let string = text(of: replaced)
        XCTAssertTrue(string.contains("분기 보고서"), string)
        XCTAssertFalse(string.contains("lazy dog"), string)
        XCTAssertTrue(string.contains("Quarterly Report"))
        XCTAssertLessThan(replaced.count, page.count + 100_000, "fonts are embedded as subsets")

        // The new text is ordinary page text: after PDFKit rewrites the page (every save and edit in the app)
        // it is found again as one paragraph in the same place and can be edited again.
        let rewrittenDoc = try XCTUnwrap(PDFDocument(data: replaced))
        let rewritten = try XCTUnwrap(PDFOps.singlePageData(try XCTUnwrap(rewrittenDoc.page(at: 0))))
        let again = try XCTUnwrap(ContentEditor.blocks(of: rewritten).first { $0.text.contains("보고서") })
        XCTAssertEqual(again.text.replacingOccurrences(of: " ", with: ""), "분기보고서—edited")
        XCTAssertEqual(again.style.fontSize, body.style.fontSize, accuracy: 0.5)
        XCTAssertEqual(again.bounds.minX, body.bounds.minX, accuracy: 3)
        XCTAssertEqual(again.bounds.maxY, body.bounds.maxY, accuracy: 4)
        let twice = try XCTUnwrap(ContentEditor.replaceText(of: again, with: "Final", style: again.style, of: rewritten))
        XCTAssertTrue(text(of: twice).contains("Final"))
        XCTAssertFalse(text(of: twice).contains("분기"))
    }

    func testRemoveMoveAndAdd() throws {
        let page = samplePage()
        let blocks = ContentEditor.blocks(of: page)
        let heading = try XCTUnwrap(blocks.first { $0.text == "Quarterly Report" })
        let removed = try XCTUnwrap(ContentEditor.remove([heading], of: page))
        XCTAssertFalse(text(of: removed).contains("Quarterly"))

        let target = heading.bounds.offsetBy(dx: 100, dy: -300)
        let moved = try XCTUnwrap(ContentEditor.move(heading, to: target, of: page))
        let movedHeading = try XCTUnwrap(ContentEditor.blocks(of: moved).first { $0.text == "Quarterly Report" })
        XCTAssertEqual(movedHeading.bounds.minX, target.minX, accuracy: 1)
        // Moved text is set again, so its top edge (not its exact glyph box) lands on the target.
        XCTAssertEqual(movedHeading.bounds.maxY, target.maxY, accuracy: 4)

        let added = try XCTUnwrap(ContentEditor.addText("Approved", style: TextStyle(fontSize: 18, color: .systemGreen), at: CGPoint(x: 400, y: 750), of: page))
        let stamp = try XCTUnwrap(ContentEditor.blocks(of: added).first { $0.text.contains("Approved") })
        XCTAssertEqual(stamp.bounds.minX, 400, accuracy: 3)
    }

    func testImages() throws {
        let page = samplePage()
        let image = try XCTUnwrap(ContentEditor.blocks(of: page).first { $0.kind == .image })
        let extracted = try XCTUnwrap(ContentEditor.image(of: image, of: page))
        XCTAssertGreaterThan(extracted.width, 0)

        let wide = CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let replaced = try XCTUnwrap(ContentEditor.replaceImage(of: image, with: wide, of: page))
        let newImage = try XCTUnwrap(ContentEditor.blocks(of: replaced).first { $0.kind == .image })
        XCTAssertEqual(newImage.bounds.width, 100, accuracy: 1)
        XCTAssertEqual(newImage.bounds.height, 50, accuracy: 1)

        let added = try XCTUnwrap(ContentEditor.addImage(Self.square(.blue), in: CGRect(x: 300, y: 300, width: 50, height: 50), of: page))
        XCTAssertEqual(ContentEditor.blocks(of: added).filter { $0.kind == .image }.count, 2)
        XCTAssertEqual(PDFDocument(data: added)?.pageCount, 1)
    }

    func testEditsInsideFormXObjects() throws {
        // Pages redrawn by CoreGraphics (crop, page size…) wrap their content in a form XObject.
        let source = try XCTUnwrap(PDFDocument(data: samplePage())?.page(at: 0))
        let redrawn = try XCTUnwrap(PageOps.redrawn(source, size: CGSize(width: 700, height: 900), scaleToFit: false))
        let wrapped = PDFDocument()
        wrapped.insert(redrawn, at: 0)
        let data = try XCTUnwrap(wrapped.dataRepresentation())
        let reloaded = try XCTUnwrap(PDFDocument(data: data))
        let expected = try XCTUnwrap(reloaded.findString("Quarterly Report", withOptions: []).first?.bounds(for: reloaded.page(at: 0)!))
        let heading = try XCTUnwrap(ContentEditor.blocks(of: data).first { $0.text == "Quarterly Report" })
        XCTAssertEqual(heading.bounds.minX, expected.minX, accuracy: 3)
        XCTAssertEqual(heading.bounds.midY, expected.midY, accuracy: 4)
        let removed = try XCTUnwrap(ContentEditor.remove([heading], of: data))
        let string = text(of: removed)
        XCTAssertFalse(string.contains("Quarterly"), string)
        XCTAssertTrue(string.contains("lazy dog"), string)
    }

    func testAnnotationsRotationAndBoxesSurviveEdits() throws {
        let doc = try XCTUnwrap(PDFDocument(data: samplePage()))
        let page = try XCTUnwrap(doc.page(at: 0))
        page.rotation = 90
        page.setBounds(CGRect(x: 36, y: 36, width: 540, height: 720), for: .cropBox)
        page.addAnnotation(Annotations.note("Check this", at: CGPoint(x: 300, y: 300), color: .systemYellow))
        page.addAnnotation(CalloutAnnotation.make(text: "Look", box: CGRect(x: 150, y: 150, width: 80, height: 30),
                                                  anchor: CGPoint(x: 100, y: 100), color: .systemRed))
        let data = try XCTUnwrap(PDFOps.singlePageData(page))
        let heading = try XCTUnwrap(ContentEditor.blocks(of: data).first { $0.text == "Quarterly Report" })
        let edited = try XCTUnwrap(ContentEditor.replaceText(of: heading, with: "Annual Report", style: heading.style, of: data))
        let result = try XCTUnwrap(PDFOps.editablePage(fromPDFData: edited))
        XCTAssertEqual(result.rotation, 90)
        XCTAssertEqual(result.bounds(for: .cropBox), CGRect(x: 36, y: 36, width: 540, height: 720))
        XCTAssertTrue(result.annotations.contains { $0.type == "Text" && $0.contents == "Check this" })
        XCTAssertTrue(result.annotations.contains { $0 is CalloutAnnotation })
        XCTAssertTrue((result.string ?? "").contains("Annual Report"))
    }

    /// Regenerating the page must not change anything outside the edited paragraph: colours in ICC-based
    /// spaces (as browsers and CoreGraphics write sRGB), strokes, gradients and images.
    func testEditLeavesTheRestOfThePageUnchanged() throws {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 300, height: 300)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        ctx.setFillColor(CGColor(colorSpace: srgb, components: [1, 1, 0.9, 1])!)
        ctx.fill(box)
        ctx.setFillColor(CGColor(colorSpace: srgb, components: [0.1, 0.5, 0.9, 1])!)
        ctx.fill(CGRect(x: 20, y: 20, width: 80, height: 60))
        ctx.setStrokeColor(CGColor(colorSpace: srgb, components: [0.9, 0.2, 0.2, 1])!)
        ctx.setLineWidth(3)
        ctx.stroke(CGRect(x: 120, y: 20, width: 80, height: 60))
        let gradient = CGGradient(colorsSpace: srgb, colors: [CGColor(colorSpace: srgb, components: [0, 0.8, 0.3, 1])!,
                                                             CGColor(colorSpace: srgb, components: [0.6, 0, 0.8, 1])!] as CFArray, locations: nil)!
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 220, y: 20, width: 60, height: 60))
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 220, y: 20), end: CGPoint(x: 280, y: 80), options: [])
        ctx.restoreGState()
        ctx.draw(Self.square(.orange), in: CGRect(x: 20, y: 100, width: 50, height: 50))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Edit me", attributes: [.font: NSFont.systemFont(ofSize: 18),
                                                                                                    .foregroundColor: NSColor.systemPurple]))
        ctx.textPosition = CGPoint(x: 120, y: 220)
        CTLineDraw(line, ctx)
        ctx.endPDFPage()
        ctx.closePDF()

        // Only the edited paragraph's operators change, so the gradient, colours and image are untouched.
        let block = try XCTUnwrap(ContentEditor.blocks(of: data as Data).first { $0.text == "Edit me" })
        let edited = try XCTUnwrap(ContentEditor.replaceText(of: block, with: "Done", style: block.style, of: data as Data))
        XCTAssertTrue(PDFDocument(data: edited)?.page(at: 0)?.string?.contains("Done") == true)
        let before = try XCTUnwrap(Self.render(data as Data)), after = try XCTUnwrap(Self.render(edited))
        let changed = block.bounds.insetBy(dx: -6, dy: -10)
        var differing = 0
        for y in 0..<300 {
            for x in 0..<300 where !changed.contains(CGPoint(x: x, y: y)) {
                let i = ((299 - y) * 300 + x) * 4
                if (0..<3).contains(where: { abs(Int(before[i + $0]) - Int(after[i + $0])) > 24 }) { differing += 1 }
            }
        }
        XCTAssertEqual(differing, 0, "pixels outside the edited paragraph changed")
    }

    /// Kerning and character spacing (as word processors and browsers write) survive edits elsewhere on the page.
    func testUntouchedTextKeepsItsSpacing() throws {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 400, height: 200)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        // The system font's tracking makes CoreGraphics write character spacing (Tc) and TJ kerning.
        for (text, y) in [("Quarterly Report", 150.0), ("delete me", 50.0)] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.boldSystemFont(ofSize: 24)]))
            ctx.textPosition = CGPoint(x: 20, y: y)
            CTLineDraw(line, ctx)
        }
        ctx.endPDFPage()
        ctx.closePDF()
        let target = try XCTUnwrap(ContentEditor.blocks(of: data as Data).first { $0.text == "delete me" })
        let removed = try XCTUnwrap(ContentEditor.remove([target], of: data as Data))
        XCTAssertTrue(ContentEditor.looksUnchanged(data as Data, removed, page: 0, except: [target.bounds]))
        XCTAssertFalse(PDFDocument(data: removed)?.page(at: 0)?.string?.contains("delete") ?? true)
    }

    /// RGBA pixels of page 0 at 1 pt per pixel, bottom row first.
    static func render(_ data: Data) -> [UInt8]? {
        guard let doc = PDFDocument(data: data), let page = doc.page(at: 0) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 300 * 300 * 4)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: 300, height: 300, bitsPerComponent: 8, bytesPerRow: 1200,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.setFillColor(.white)
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
            page.draw(with: .mediaBox, to: ctx)
            return true
        }
        return ok ? pixels : nil
    }

    func testTextFreeRendering() throws {
        let render = try XCTUnwrap(ContentEditor.textFreeRenderer(for: samplePage(), scale: 1))
        let image = try XCTUnwrap(render(0))
        XCTAssertEqual(image.width, 612)
        XCTAssertEqual(image.height, 792)
    }
}
#endif
