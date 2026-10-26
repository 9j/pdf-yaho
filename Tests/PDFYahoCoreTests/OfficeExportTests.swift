import AppKit
import PDFKit
import XCTest
@testable import PDFYahoCore

final class OfficeExportTests: XCTestCase {
    private let table = [["Name", "Qty", "Price"], ["Apples", "12", "3.50"], ["Pears", "7", "1,234.50"]]
    private let prose = "The quick brown fox jumps over the lazy dog while the afternoon sun sinks slowly behind the hills, "
        + "and nobody on the quiet road notices how long the shadows have grown."

    /// Page 1 is a 3x3 table drawn at fixed positions, page 2 is a wrapped paragraph.
    private func makeDocument() -> PDFDocument {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: PDFOps.letter)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14)]
        ctx.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for (r, row) in table.enumerated() {
            for (c, text) in row.enumerated() {
                (text as NSString).draw(at: CGPoint(x: 72 + CGFloat(c) * 160, y: 700 - CGFloat(r) * 28), withAttributes: attributes)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        (prose as NSString).draw(in: CGRect(x: 72, y: 500, width: 300, height: 220), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
        return PDFDocument(data: data as Data)!
    }

    // MARK: Helpers

    /// Runs `/usr/bin/unzip` on `data` written to a temporary file.
    private func unzip(_ data: Data, _ arguments: [String]) throws -> (status: Int32, output: Data) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments + [file.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }

    private func entries(_ data: Data) throws -> [String] {
        let listing = try unzip(data, ["-Z1"]).output
        return String(decoding: listing, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    /// A part's bytes. Patterns with `[` need escaping because unzip treats them as globs.
    private func partData(_ data: Data, _ pattern: String) throws -> Data {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", file.path, pattern]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "extracting \(pattern)")
        return output
    }

    private func assertValidPackage(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try unzip(data, ["-tq"]).status, 0, "unzip -t", file: file, line: line)
        let names = try entries(data)
        XCTAssertEqual(names.first, "[Content_Types].xml", file: file, line: line)
        for name in names where name.hasSuffix(".xml") || name.hasSuffix(".rels") {
            let xml = try partData(data, name.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]"))
            XCTAssertNoThrow(try XMLDocument(data: xml), "\(name) is well-formed", file: file, line: line)
        }
    }

    private func xml(_ data: Data, _ path: String) throws -> XMLDocument {
        try XMLDocument(data: try partData(data, path))
    }

    /// Cells of a worksheet by reference: (type attribute, style attribute, text).
    private func cells(of sheet: XMLDocument) -> [String: (type: String?, style: String?, text: String)] {
        var result: [String: (type: String?, style: String?, text: String)] = [:]
        let rows = sheet.rootElement()?.elements(forName: "sheetData").first?.elements(forName: "row") ?? []
        for row in rows {
            for c in row.elements(forName: "c") {
                guard let ref = c.attribute(forName: "r")?.stringValue else { continue }
                result[ref] = (c.attribute(forName: "t")?.stringValue, c.attribute(forName: "s")?.stringValue, c.stringValue ?? "")
            }
        }
        return result
    }

    /// On macOS 26 Vision reads the ruled table; earlier systems use the text layout. Both give the same sheet.
    func testRuledTableBecomesSheet() async throws {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: PDFOps.letter)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
        for r in 0...3 { ctx.move(to: CGPoint(x: 60, y: 700 - CGFloat(r) * 30)); ctx.addLine(to: CGPoint(x: 460, y: 700 - CGFloat(r) * 30)) }
        for c in 0...3 { ctx.move(to: CGPoint(x: 60 + CGFloat(c) * 133, y: 700)); ctx.addLine(to: CGPoint(x: 60 + CGFloat(c) * 133, y: 610)) }
        ctx.strokePath()
        for (r, row) in table.enumerated() {
            for (c, text) in row.enumerated() {
                (text as NSString).draw(at: CGPoint(x: 70 + CGFloat(c) * 133, y: 680 - CGFloat(r) * 30),
                                        withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
        let result = await OfficeExport.xlsx(try XCTUnwrap(PDFDocument(data: data as Data)))
        let xlsx = try XCTUnwrap(result)
        try assertValidPackage(xlsx)
        let cells = cells(of: try xml(xlsx, "xl/worksheets/sheet1.xml"))
        XCTAssertEqual(cells["A1"]?.text, "Name")
        XCTAssertEqual(cells["A2"]?.text, "Apples")
        XCTAssertEqual(cells["C3"]?.text, "1234.50")
    }

    // MARK: Zip

    func testZipRoundTrip() throws {
        var zip = ZipWriter()
        let small = Data("hello".utf8)
        let big = Data(String(repeating: "pagecraft <> & ", count: 5000).utf8)
        let binary = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ ($0 >> 3)) })
        zip.add(path: "a.txt", data: small)
        zip.add(path: "dir/big.txt", data: big)
        zip.add(path: "dir/uni.bin", data: binary)
        zip.add(path: "empty", data: Data())
        let archive = zip.data
        XCTAssertLessThan(archive.count, big.count / 2, "repetitive data is deflated")
        XCTAssertEqual(try unzip(archive, ["-tq"]).status, 0)
        XCTAssertEqual(try partData(archive, "a.txt"), small)
        XCTAssertEqual(try partData(archive, "dir/big.txt"), big)
        XCTAssertEqual(try partData(archive, "dir/uni.bin"), binary)
        XCTAssertEqual(try partData(archive, "empty"), Data())
        XCTAssertEqual(try entries(archive), ["a.txt", "dir/big.txt", "dir/uni.bin", "empty"])
    }

    func testCRC32MatchesKnownValue() {
        XCTAssertEqual(ZipWriter.crc32(Data("123456789".utf8)), 0xCBF43926)
    }

    // MARK: XML

    func testEscapeStripsInvalidCharacters() {
        XCTAssertEqual(OfficeExport.escape("a<b>&\"c'\u{0}\u{8}\u{B}\u{FFFE}\t\n"), "a&lt;b&gt;&amp;&quot;c&apos;\t\n")
        XCTAssertEqual(OfficeExport.escape("emoji 😀"), "emoji 😀")
    }

    func testNumberDetection() {
        XCTAssertEqual(OfficeExport.number("1,234.50")?.value, "1234.50")
        XCTAssertEqual(OfficeExport.number("-3")?.value, "-3")
        XCTAssertEqual(OfficeExport.number("12%")?.value, "0.12")
        XCTAssertEqual(OfficeExport.number(" 3.14 ")?.value, "3.14")
        XCTAssertNil(OfficeExport.number("007"))
        XCTAssertNil(OfficeExport.number("12,34"))
        XCTAssertNil(OfficeExport.number("1 2"))
        XCTAssertNil(OfficeExport.number("Q3"))
        XCTAssertNil(OfficeExport.number(""))
    }

    // MARK: Excel

    func testSpreadsheetFromTextLayout() async throws {
        let result = await OfficeExport.xlsx(makeDocument(), pages: [0], useVision: false)
        let data = try XCTUnwrap(result)
        try assertValidPackage(data)
        let sheet = try xml(data, "xl/worksheets/sheet1.xml")
        let cells = cells(of: sheet)
        for (r, row) in table.enumerated() {
            for (c, expected) in row.enumerated() where OfficeExport.number(expected) == nil {
                let cell = try XCTUnwrap(cells["\(["A", "B", "C"][c])\(r + 1)"], "\(expected) is in the right cell")
                XCTAssertEqual(cell.type, "inlineStr")
                XCTAssertEqual(cell.text, expected)
            }
        }
        // Numbers are numeric cells, not strings.
        let qty = try XCTUnwrap(cells["B2"])
        XCTAssertNil(qty.type)
        XCTAssertEqual(qty.text, "12")
        XCTAssertEqual(try XCTUnwrap(cells["C3"]).text, "1234.50")
        XCTAssertNotNil(try XCTUnwrap(cells["C3"]).style, "thousands separators keep their number format")
        XCTAssertEqual(try xml(data, "xl/workbook.xml").rootElement()?.elements(forName: "sheets").first?.children?.count, 1)
    }

    func testProseBecomesSingleColumn() async throws {
        let result = await OfficeExport.xlsx(makeDocument(), pages: [1], useVision: false)
        let data = try XCTUnwrap(result)
        try assertValidPackage(data)
        let cells = cells(of: try xml(data, "xl/worksheets/sheet1.xml"))
        XCTAssertGreaterThan(cells.count, 2, "one line per row")
        XCTAssertTrue(cells.keys.allSatisfy { $0.hasPrefix("A") }, "only column A: \(cells.keys.sorted())")
        XCTAssertTrue(cells["A1"]?.text.hasPrefix("The quick") ?? false)
    }

    func testWorkbookHasOneSheetPerPage() async throws {
        let result = await OfficeExport.xlsx(makeDocument())
        let data = try XCTUnwrap(result)
        try assertValidPackage(data)
        let workbook = try xml(data, "xl/workbook.xml")
        let sheets = workbook.rootElement()?.elements(forName: "sheets").first?.elements(forName: "sheet") ?? []
        XCTAssertEqual(sheets.map { $0.attribute(forName: "name")?.stringValue }.prefix(1), ["Page 1"])
        XCTAssertTrue(sheets.count >= 2)
        // The Vision path (macOS 26) and the layout path agree on the table values.
        let sheet = cells(of: try xml(data, "xl/worksheets/sheet1.xml"))
        XCTAssertEqual(sheet["A1"]?.text, "Name")
        XCTAssertEqual(sheet["B3"]?.text, "7")
        let empty = await OfficeExport.xlsx(makeDocument(), pages: [9])
        XCTAssertNil(empty)
    }

    // MARK: PowerPoint

    func testPresentationHasSlidePerPageWithText() throws {
        let doc = makeDocument()
        let data = try XCTUnwrap(OfficeExport.pptx(doc))
        try assertValidPackage(data)
        let names = try entries(data)
        XCTAssertEqual(names.filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }.count, doc.pageCount)
        XCTAssertEqual(names.filter { $0.hasPrefix("ppt/media/") }.count, doc.pageCount)
        let presentation = try xml(data, "ppt/presentation.xml")
        let ids = presentation.rootElement()?.elements(forName: "p:sldIdLst").first?.elements(forName: "p:sldId") ?? []
        XCTAssertEqual(ids.count, doc.pageCount)
        XCTAssertEqual(ids.first?.attribute(forName: "id")?.stringValue, "256")
        let size = try XCTUnwrap(presentation.rootElement()?.elements(forName: "p:sldSz").first)
        XCTAssertEqual(size.attribute(forName: "cx")?.stringValue, "\(612 * 12700)")
        XCTAssertEqual(size.attribute(forName: "cy")?.stringValue, "\(792 * 12700)")

        let slide = try xml(data, "ppt/slides/slide1.xml")
        let runs = try slide.nodes(forXPath: "//a:t").map { $0.stringValue ?? "" }
        XCTAssertTrue(runs.contains("Name"), "runs: \(runs)")
        XCTAssertTrue(runs.contains("1,234.50"))
        XCTAssertEqual(try slide.nodes(forXPath: "//p:pic").count, 1)
        XCTAssertFalse(try slide.nodes(forXPath: "//a:alpha[@val='0']").isEmpty, "rendered page: text is transparent")
        let png = try partData(data, "ppt/media/image1.png")
        XCTAssertNotNil(NSBitmapImageRep(data: png))
    }

    func testSuppliedBackgroundKeepsTextVisible() throws {
        let image = try XCTUnwrap(PDFOps.renderImage(try XCTUnwrap(makeDocument().page(at: 0)), scale: 1))
        var asked: [Int] = []
        let data = try XCTUnwrap(OfficeExport.pptx(makeDocument(), pages: [1]) { index in asked.append(index); return image })
        try assertValidPackage(data)
        XCTAssertEqual(asked, [1])
        let slide = try xml(data, "ppt/slides/slide1.xml")
        XCTAssertTrue(try slide.nodes(forXPath: "//a:alpha").isEmpty)
        let text = try slide.nodes(forXPath: "//a:t").map { $0.stringValue ?? "" }.joined(separator: " ")
        XCTAssertTrue(text.contains("The quick brown fox"), text)
        XCTAssertNil(OfficeExport.pptx(makeDocument(), pages: []))
    }

    func testRotatedPageSwapsSlideSize() throws {
        let doc = makeDocument()
        doc.page(at: 0)?.rotation = 90
        let data = try XCTUnwrap(OfficeExport.pptx(doc, pages: [0]))
        try assertValidPackage(data)
        let size = try XCTUnwrap(try xml(data, "ppt/presentation.xml").rootElement()?.elements(forName: "p:sldSz").first)
        XCTAssertEqual(size.attribute(forName: "cx")?.stringValue, "\(792 * 12700)")
        XCTAssertEqual(size.attribute(forName: "cy")?.stringValue, "\(612 * 12700)")
        let slide = try xml(data, "ppt/slides/slide1.xml")
        XCTAssertFalse(try slide.nodes(forXPath: "//a:xfrm[@rot='5400000']").isEmpty)
    }
}
