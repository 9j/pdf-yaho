import AppKit
import PDFKit
import XCTest
@testable import PagecraftCore

final class ExportTests: XCTestCase {
    private func textDocument(_ text: String) -> PDFDocument {
        PDFOpsTests().makeTextDocument([text])
    }

    private func photoDocument() -> PDFDocument {
        let image = NSImage(size: NSSize(width: 1600, height: 1200), flipped: false) { rect in
            for i in 0..<400 {
                NSColor(hue: CGFloat(i % 37) / 37, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                NSRect(x: CGFloat(i * 13 % 1600), y: CGFloat(i * 29 % 1200), width: 90, height: 70).fill()
            }
            return true
        }
        return PDFOps.document(fromImages: [image])
    }

    func testWordExportKeepsText() throws {
        let data = try XCTUnwrap(PDFOps.exportData(textDocument("Export me to Word"), as: .word))
        let back = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                                          documentAttributes: nil)
        XCTAssertTrue(back.string.contains("Export me to Word"))
        XCTAssertNotNil(PDFOps.exportData(textDocument("x"), as: .rtf))
        XCTAssertTrue(String(data: try XCTUnwrap(PDFOps.exportData(textDocument("Hello HTML"), as: .html)), encoding: .utf8)?
            .contains("Hello HTML") ?? false)
    }

    func testImageExportUsesResolution() throws {
        let page = try XCTUnwrap(textDocument("dpi").page(at: 0))
        let data = try XCTUnwrap(PDFOps.imageData(page, format: .jpeg, dpi: 144))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(rep.pixelsWide, 1224)
        XCTAssertNotNil(PDFOps.imageData(page, format: .tiff, dpi: 72))
    }

    func testCompressionShrinksImages() throws {
        let doc = photoDocument()
        let dir = FileManager.default.temporaryDirectory
        let original = dir.appendingPathComponent(UUID().uuidString + ".pdf")
        let small = dir.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { [original, small].forEach { try? FileManager.default.removeItem(at: $0) } }
        XCTAssertTrue(PDFOps.write(doc, to: original))
        XCTAssertTrue(PDFOps.write(doc, to: small, options: .init(compression: .low)))
        let a = try XCTUnwrap(original.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let b = try XCTUnwrap(small.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertLessThan(b, a)
    }

    func testPasswordProtectedSnapshot() throws {
        let data = try XCTUnwrap(PDFOps.data(textDocument("secret"), options: .init(userPassword: "pw")))
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertTrue(doc.isLocked)
        XCTAssertTrue(doc.unlock(withPassword: "pw"))
    }

    func testOCRMakesScansSearchable() throws {
        let image = NSImage(size: NSSize(width: 612, height: 792), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("Searchable after recognition" as NSString).draw(at: CGPoint(x: 60, y: 600), withAttributes: [.font: NSFont.systemFont(ofSize: 34)])
            return true
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(PDFOps.write(PDFOps.document(fromImages: [image]), to: url, options: .init(performOCR: true)))
        XCTAssertTrue(PDFDocument(url: url)?.page(at: 0)?.string?.contains("Searchable") ?? false)
    }

    func testXFDFListsAnnotations() throws {
        let doc = textDocument("note")
        let page = try XCTUnwrap(doc.page(at: 0))
        page.addAnnotation(Annotations.markup(.highlight, bounds: CGRect(x: 10, y: 10, width: 50, height: 12), color: .yellow))
        page.addAnnotation(Annotations.note("A & B", at: CGPoint(x: 100, y: 100), color: .yellow))
        let xml = PDFOps.xfdf(doc, fileName: "x.pdf")
        XCTAssertTrue(xml.contains("<highlight page=\"0\""))
        XCTAssertTrue(xml.contains("<contents>A &amp; B</contents>"))
        XCTAssertNotNil(try? XMLDocument(xmlString: xml))
    }
}
