import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Excel and PowerPoint export. The OOXML parts are written by hand and zipped with `ZipWriter`.
public enum OfficeExport {
    /// A run of text on one line, in page space.
    struct Fragment {
        var text: String
        var rect: CGRect
    }

    /// One line of PDFKit text, split into fragments at wide horizontal gaps.
    struct TextLine {
        var fragments: [Fragment]
        var rect: CGRect
    }

    // MARK: Excel

    /// A workbook with one sheet per page, or per table when a page holds several. `pages` are zero-based.
    public static func xlsx(_ doc: PDFDocument, pages: [Int]? = nil) async -> Data? {
        await xlsx(doc, pages: pages, useVision: true)
    }

    static func xlsx(_ doc: PDFDocument, pages: [Int]?, useVision: Bool) async -> Data? {
        let indices = pageIndices(doc, pages)
        guard !indices.isEmpty else { return nil }
        var sheets: [(name: String, rows: [[String]])] = []
        for index in indices {
            guard let page = doc.page(at: index) else { continue }
            var tables: [[[String]]] = []
            if useVision, #available(macOS 26, *) { tables = await visionTables(page) }
            if tables.isEmpty { tables = [grid(textLines(page))] }
            for (k, rows) in tables.enumerated() {
                sheets.append((tables.count > 1 ? "Page \(index + 1) – Table \(k + 1)" : "Page \(index + 1)", rows))
            }
        }
        return workbook(sheets)
    }

    /// Tables Vision finds on the page, top to bottom, as rows of cell text.
    @available(macOS 26, *)
    private static func visionTables(_ page: PDFPage) async -> [[[String]]] {
        guard let image = render(page, scale: 2),
              let observations = try? await RecognizeDocumentsRequest().perform(on: image) else { return [] }
        let tables = observations.flatMap { $0.document.tables }
        let tops = tables.map { $0.boundingRegion.points.map { Double($0.y) }.max() ?? 0 }
        return zip(tables, tops).sorted { $0.1 > $1.1 }.map { table, _ in
            var rows: [[String]] = []
            for (r, cells) in table.rows.enumerated() {
                for cell in cells {
                    let row = max(r, cell.rowRange.lowerBound), col = cell.columnRange.lowerBound
                    while rows.count <= row { rows.append([]) }
                    while rows[row].count <= col { rows[row].append("") }
                    if rows[row][col].isEmpty { rows[row][col] = cell.content.text.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
            }
            return rows.filter { $0.contains { !$0.isEmpty } }
        }.filter { !$0.isEmpty }
    }

    /// Rows of cells from the text layout: lines on one baseline share a row, cell edges are clustered into columns.
    static func grid(_ lines: [TextLine]) -> [[String]] {
        var rows: [[Fragment]] = []
        var mids: [CGFloat] = [], heights: [CGFloat] = []
        for line in lines.sorted(by: { $0.rect.midY > $1.rect.midY }) {
            if let i = rows.indices.last, abs(mids[i] - line.rect.midY) < 0.5 * min(heights[i], line.rect.height) {
                rows[i] += line.fragments
            } else {
                rows.append(line.fragments)
                mids.append(line.rect.midY)
                heights.append(line.rect.height)
            }
        }
        rows = rows.map { $0.sorted { $0.rect.minX < $1.rect.minX } }

        // Columns come from rows with several cells; single lines (titles, prose) must not merge them.
        var spans: [ClosedRange<CGFloat>] = []
        for f in rows.filter({ $0.count > 1 }).flatMap({ $0 }).sorted(by: { $0.rect.minX < $1.rect.minX }) {
            if let last = spans.last, f.rect.minX <= last.upperBound {
                spans[spans.count - 1] = last.lowerBound...max(last.upperBound, f.rect.maxX)
            } else {
                spans.append(f.rect.minX...f.rect.maxX)
            }
        }
        func column(_ f: Fragment) -> Int {
            if let i = spans.firstIndex(where: { $0.lowerBound <= f.rect.maxX && f.rect.minX <= $0.upperBound }) { return i }
            return spans.lastIndex { $0.lowerBound <= f.rect.minX } ?? 0
        }
        return rows.map { row in
            var cells: [String] = []
            var previous = -1
            for f in row {
                let c = max(column(f), previous + 1)
                while cells.count <= c { cells.append("") }
                cells[c] = f.text
                previous = c
            }
            return cells
        }
    }

    /// Lines of the page text, each split into fragments wherever the gap between words exceeds 1.5 average character widths.
    /// Words are measured through selections: per-character bounds drift from the string for many generated PDFs.
    static func textLines(_ page: PDFPage) -> [TextLine] {
        guard let selection = page.selection(for: page.bounds(for: .mediaBox)), let full = page.string else { return [] }
        let string = full as NSString
        struct Word { var text: String; var rect: CGRect; var length: Int }
        var lines: [(words: [Word], rect: CGRect)] = []
        for line in selection.selectionsByLine() {
            let rect = line.bounds(for: page)
            guard rect.width > 0, rect.height > 0 else { continue }
            var words: [Word] = []
            for r in 0..<line.numberOfTextRanges(on: page) {
                let range = line.range(at: r, on: page)
                let end = min(NSMaxRange(range), string.length)
                var start = range.location
                for i in range.location...max(end, range.location) {
                    let isBreak = i >= end || Unicode.Scalar(string.character(at: i)).map {
                        CharacterSet.whitespacesAndNewlines.contains($0) || $0.value < 0x20
                    } ?? false
                    guard isBreak else { continue }
                    if i > start {
                        let word = NSRange(location: start, length: i - start)
                        if let box = page.selection(for: word)?.bounds(for: page), box.width > 0 {
                            words.append(Word(text: string.substring(with: word), rect: box, length: word.length))
                        }
                    }
                    start = i + 1
                }
            }
            if !words.isEmpty { lines.append((words, rect)) }
        }
        let characters = lines.flatMap(\.words).reduce(0) { $0 + $1.length }
        let width = lines.flatMap(\.words).reduce(CGFloat(0)) { $0 + $1.rect.width }
        let threshold = 1.5 * (characters > 0 ? width / CGFloat(characters) : 6)

        return lines.map { line in
            var fragments: [Fragment] = []
            var group: [Word] = []
            func flush() {
                guard let first = group.first, let last = group.last else { return }
                let x0 = first.rect.minX, x1 = max(last.rect.maxX, x0 + 1)
                fragments.append(Fragment(text: group.map(\.text).joined(separator: " "),
                                          rect: CGRect(x: x0, y: line.rect.minY, width: x1 - x0, height: line.rect.height)))
                group = []
            }
            for word in line.words.sorted(by: { $0.rect.minX < $1.rect.minX }) {
                if let last = group.last, word.rect.minX - last.rect.maxX > threshold { flush() }
                group.append(word)
            }
            flush()
            return TextLine(fragments: fragments, rect: line.rect)
        }
    }

    /// The numeric value of a cell (`1,234.50`, `-3`, `12%`) and its style index, or nil for text.
    static func number(_ text: String) -> (value: String, style: Int)? {
        var s = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{2212}", with: "-")
        let percent = s.hasSuffix("%")
        if percent { s = String(s.dropLast()).trimmingCharacters(in: .whitespaces) }
        guard s.range(of: #"^[+-]?(\d{1,3}(,\d{3})+|\d+)(\.\d+)?$"#, options: .regularExpression) != nil else { return nil }
        let grouped = s.contains(",")
        var plain = s.replacingOccurrences(of: ",", with: "")
        if plain.hasPrefix("+") { plain.removeFirst() }
        let integer = plain.drop { $0 == "-" }.prefix { $0 != "." }
        // Zip codes, ids and long digit strings are text, not quantities.
        if integer.count > 15 || (integer.count > 1 && integer.hasPrefix("0")) { return nil }
        let decimals = plain.contains(".")
        if percent {
            guard let value = Decimal(string: plain, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            return ("\(value / 100)", decimals ? 2 : 1)
        }
        return (plain, grouped ? (decimals ? 4 : 3) : 0)
    }

    private static func workbook(_ sheets: [(name: String, rows: [[String]])]) -> Data? {
        guard !sheets.isEmpty else { return nil }
        let t = OfficeTemplates.self
        var zip = ZipWriter()
        var names: [String] = []
        func uniqueName(_ raw: String) -> String {
            let cleaned = String(raw.map { "[]:*?/\\".contains($0) ? "-" : $0 }.prefix(31))
            var name = cleaned, n = 2
            while names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                let suffix = " (\(n))"
                name = String(cleaned.prefix(31 - suffix.count)) + suffix
                n += 1
            }
            names.append(name)
            return name
        }
        let sheetNames = sheets.map { uniqueName($0.name) }

        var types = [("/xl/workbook.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"),
                     ("/xl/styles.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml")]
        types += sheets.indices.map { ("/xl/worksheets/sheet\($0 + 1).xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml") }
        zip.add(path: "[Content_Types].xml", data: utf8(t.contentTypes(overrides: types)))
        zip.add(path: "_rels/.rels", data: utf8(t.rootRels(target: "xl/workbook.xml")))

        var book = t.header + "<workbook xmlns=\"\(t.nsSheet)\" xmlns:r=\"\(t.nsR)\"><sheets>"
        for (i, name) in sheetNames.enumerated() { book += "<sheet name=\"\(escape(name))\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>" }
        zip.add(path: "xl/workbook.xml", data: utf8(book + "</sheets></workbook>"))
        var relations = sheets.indices.map { (id: "rId\($0 + 1)", type: "worksheet", target: "worksheets/sheet\($0 + 1).xml") }
        relations.append((id: "rId\(sheets.count + 1)", type: "styles", target: "styles.xml"))
        zip.add(path: "xl/_rels/workbook.xml.rels", data: utf8(t.rels(relations)))
        zip.add(path: "xl/styles.xml", data: utf8(t.styles))
        for (i, sheet) in sheets.enumerated() { zip.add(path: "xl/worksheets/sheet\(i + 1).xml", data: utf8(worksheet(sheet.rows))) }
        return zip.data
    }

    private static func worksheet(_ rows: [[String]]) -> String {
        let t = OfficeTemplates.self
        let rows = rows.prefix(1_048_576).map { Array($0.prefix(16384)) }
        let columns = rows.map(\.count).max() ?? 0
        var xml = t.header + "<worksheet xmlns=\"\(t.nsSheet)\" xmlns:r=\"\(t.nsR)\">"
        xml += "<dimension ref=\"A1\(columns > 0 && !rows.isEmpty ? ":\(columnName(columns - 1))\(rows.count)" : "")\"/>"
        if columns > 0 {
            xml += "<cols>"
            for c in 0..<columns {
                let longest = rows.map { c < $0.count ? displayWidth($0[c]) : 0 }.max() ?? 0
                let width = min(60, max(8, Double(longest) * 1.1 + 2))
                xml += "<col min=\"\(c + 1)\" max=\"\(c + 1)\" width=\"\(String(format: "%.2f", width))\" customWidth=\"1\"/>"
            }
            xml += "</cols>"
        }
        xml += "<sheetData>"
        for (r, row) in rows.enumerated() {
            let cells = row.enumerated().filter { !$0.element.isEmpty }
            guard !cells.isEmpty else { continue }
            xml += "<row r=\"\(r + 1)\">"
            for (c, text) in cells {
                let ref = "\(columnName(c))\(r + 1)"
                if let n = number(text) {
                    xml += "<c r=\"\(ref)\"\(n.style > 0 ? " s=\"\(n.style)\"" : "")><v>\(n.value)</v></c>"
                } else {
                    xml += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(text))</t></is></c>"
                }
            }
            xml += "</row>"
        }
        return xml + "</sheetData></worksheet>"
    }

    /// `A`, `B`, ... `Z`, `AA`.
    private static func columnName(_ index: Int) -> String {
        var n = index + 1, name = ""
        while n > 0 {
            name = String(UnicodeScalar(UInt8(65 + (n - 1) % 26))) + name
            n = (n - 1) / 26
        }
        return name
    }

    /// Character count where East Asian characters take two columns.
    private static func displayWidth(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + ($1.value >= 0x2E80 ? 2 : 1) }
    }

    // MARK: PowerPoint

    /// A deck with one slide per page. With `background`, the returned text-free page images sit under visible,
    /// editable text boxes; without it the page is rendered whole and the text boxes are fully transparent.
    public static func pptx(_ doc: PDFDocument, pages: [Int]? = nil, background: ((Int) -> CGImage?)? = nil) -> Data? {
        let indices = pageIndices(doc, pages)
        guard !indices.isEmpty else { return nil }
        let t = OfficeTemplates.self
        var slideParts: [(path: String, data: Data)] = []
        var size = CGSize(width: 1, height: 1)

        for (n, index) in indices.enumerated() {
            guard let page = doc.page(at: index) else { return nil }
            let geometry = PageGeometry(page)
            if n == 0 { size = geometry.slideSize }
            let supplied = background?(index)
            guard let image = supplied ?? render(page, scale: 2), let png = pngData(image) else { return nil }
            let slide = n + 1
            slideParts.append(("ppt/media/image\(slide).png", png))
            slideParts.append(("ppt/slides/slide\(slide).xml", utf8(slideXML(page, geometry, visibleText: supplied != nil, index: index))))
            slideParts.append(("ppt/slides/_rels/slide\(slide).xml.rels", utf8(t.rels([
                (id: "rId1", type: "slideLayout", target: "../slideLayouts/slideLayout1.xml"),
                (id: "rId2", type: "image", target: "../media/image\(slide).png"),
            ]))))
        }

        let slideCount = indices.count
        var types = [("/ppt/presentation.xml", "application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"),
                     ("/ppt/slideMasters/slideMaster1.xml", "application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"),
                     ("/ppt/slideLayouts/slideLayout1.xml", "application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"),
                     ("/ppt/theme/theme1.xml", "application/vnd.openxmlformats-officedocument.theme+xml")]
        types += (1...slideCount).map { ("/ppt/slides/slide\($0).xml", "application/vnd.openxmlformats-officedocument.presentationml.slide+xml") }
        // The content types part goes first, as most readers expect.
        var out = ZipWriter()
        out.add(path: "[Content_Types].xml", data: utf8(t.contentTypes(overrides: types, png: true)))
        out.add(path: "_rels/.rels", data: utf8(t.rootRels(target: "ppt/presentation.xml")))

        let emu = { (points: CGFloat) in Int((points * 12700).rounded()) }
        var presentation = t.header + "<p:presentation xmlns:a=\"\(t.nsA)\" xmlns:r=\"\(t.nsR)\" xmlns:p=\"\(t.nsP)\" saveSubsetFonts=\"1\">"
        presentation += "<p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rId1\"/></p:sldMasterIdLst><p:sldIdLst>"
        for s in 1...slideCount { presentation += "<p:sldId id=\"\(255 + s)\" r:id=\"rId\(s + 2)\"/>" }
        presentation += "</p:sldIdLst><p:sldSz cx=\"\(emu(size.width))\" cy=\"\(emu(size.height))\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/></p:presentation>"
        out.add(path: "ppt/presentation.xml", data: utf8(presentation))
        var relations = [(id: "rId1", type: "slideMaster", target: "slideMasters/slideMaster1.xml"),
                         (id: "rId2", type: "theme", target: "theme/theme1.xml")]
        relations += (1...slideCount).map { (id: "rId\($0 + 2)", type: "slide", target: "slides/slide\($0).xml") }
        out.add(path: "ppt/_rels/presentation.xml.rels", data: utf8(t.rels(relations)))
        out.add(path: "ppt/slideMasters/slideMaster1.xml", data: utf8(t.slideMaster))
        out.add(path: "ppt/slideMasters/_rels/slideMaster1.xml.rels", data: utf8(t.rels([
            (id: "rId1", type: "slideLayout", target: "../slideLayouts/slideLayout1.xml"),
            (id: "rId2", type: "theme", target: "../theme/theme1.xml"),
        ])))
        out.add(path: "ppt/slideLayouts/slideLayout1.xml", data: utf8(t.slideLayout))
        out.add(path: "ppt/slideLayouts/_rels/slideLayout1.xml.rels", data: utf8(t.rels([
            (id: "rId1", type: "slideMaster", target: "../slideMasters/slideMaster1.xml"),
        ])))
        out.add(path: "ppt/theme/theme1.xml", data: utf8(t.theme))
        for part in slideParts { out.add(path: part.path, data: part.data) }
        return out.data
    }

    /// Page size and the mapping from page space (bottom-left origin, unrotated) to the slide (top-left origin).
    private struct PageGeometry {
        let box: CGRect
        let rotation: Int
        /// Points to slide points; keeps the deck within PowerPoint's size limits.
        let scale: CGFloat

        init(_ page: PDFPage) {
            box = page.bounds(for: .cropBox)
            rotation = ((page.rotation % 360) + 360) % 360
            let longest = max(box.width, box.height), shortest = min(box.width, box.height)
            scale = longest > 4000 ? 4000 / longest : shortest > 0 && shortest < 72 ? 72 / shortest : 1
        }

        var displayed: CGSize { rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width) }
        var slideSize: CGSize { CGSize(width: displayed.width * scale, height: displayed.height * scale) }

        /// Frame of a page-space rect on the slide, in slide points. The frame stays unrotated; `rotation` turns it.
        func frame(_ rect: CGRect) -> CGRect {
            let cx = rect.midX - box.minX, cy = rect.midY - box.minY
            let centre: CGPoint
            switch rotation {
            case 90: centre = CGPoint(x: cy, y: cx)
            case 180: centre = CGPoint(x: box.width - cx, y: cy)
            case 270: centre = CGPoint(x: box.height - cy, y: box.width - cx)
            default: centre = CGPoint(x: cx, y: box.height - cy)
            }
            return CGRect(x: (centre.x - rect.width / 2) * scale, y: (centre.y - rect.height / 2) * scale,
                          width: rect.width * scale, height: rect.height * scale)
        }
    }

    private static func slideXML(_ page: PDFPage, _ geometry: PageGeometry, visibleText: Bool, index: Int) -> String {
        let t = OfficeTemplates.self
        let emu = { (points: CGFloat) in Int((points * 12700).rounded()) }
        let slide = geometry.slideSize
        var xml = t.header + "<p:sld xmlns:a=\"\(t.nsA)\" xmlns:r=\"\(t.nsR)\" xmlns:p=\"\(t.nsP)\"><p:cSld><p:spTree>\(t.emptyGroup)"
        xml += "<p:pic><p:nvPicPr><p:cNvPr id=\"2\" name=\"Page \(index + 1)\" descr=\"Page \(index + 1)\"/>"
        xml += "<p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>"
        xml += "<p:blipFill><a:blip r:embed=\"rId2\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>"
        xml += "<p:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(emu(slide.width))\" cy=\"\(emu(slide.height))\"/></a:xfrm>"
        xml += "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"

        let color = visibleText ? "<a:srgbClr val=\"000000\"/>" : "<a:srgbClr val=\"000000\"><a:alpha val=\"0\"/></a:srgbClr>"
        for (k, group) in textGroups(textLines(page)).enumerated() {
            let union = group.reduce(CGRect.null) { $0.union($1.rect) }
            // Helvetica may be wider than the original face; spare room keeps lines from wrapping in viewers that ignore wrap="none".
            let frame = geometry.frame(union)
            let height = group[0].rect.height
            let size = Int((max(4, min(400, height * 0.85 * geometry.scale)) * 100).rounded())
            let pitch = group.count > 1 ? (group[0].rect.midY - group[group.count - 1].rect.midY) / CGFloat(group.count - 1) : 0
            xml += "<p:sp><p:nvSpPr><p:cNvPr id=\"\(k + 3)\" name=\"Text \(k + 1)\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr>"
            xml += "<p:spPr><a:xfrm\(geometry.rotation == 0 ? "" : " rot=\"\(geometry.rotation * 60000)\"")>"
            xml += "<a:off x=\"\(emu(frame.minX))\" y=\"\(emu(frame.minY))\"/><a:ext cx=\"\(emu(frame.width * 1.15 + 4 * geometry.scale))\" cy=\"\(emu(frame.height))\"/></a:xfrm>"
            xml += "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>"
            xml += "<p:txBody><a:bodyPr wrap=\"none\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\" rtlCol=\"0\" anchor=\"t\"><a:noAutofit/></a:bodyPr><a:lstStyle/>"
            for fragment in group {
                xml += "<a:p>"
                if pitch > 0 { xml += "<a:pPr><a:lnSpc><a:spcPts val=\"\(Int((pitch * geometry.scale * 100).rounded()))\"/></a:lnSpc></a:pPr>" }
                xml += "<a:r><a:rPr lang=\"en-US\" sz=\"\(size)\" dirty=\"0\"><a:solidFill>\(color)</a:solidFill>"
                xml += "<a:latin typeface=\"Helvetica\"/><a:cs typeface=\"Helvetica\"/></a:rPr><a:t>\(escape(fragment.text))</a:t></a:r></a:p>"
            }
            xml += "</p:txBody></p:sp>"
        }
        return xml + "</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>"
    }

    /// Text boxes: consecutive lines stacked at the same left edge and size become paragraphs of one box.
    private static func textGroups(_ lines: [TextLine]) -> [[Fragment]] {
        var groups: [[Fragment]] = []
        var open = false
        for line in lines {
            guard line.fragments.count == 1, let f = line.fragments.first else {
                groups += line.fragments.map { [$0] }
                open = false
                continue
            }
            if open, let last = groups[groups.count - 1].last,
               abs(f.rect.minX - last.rect.minX) < 2,
               f.rect.height / last.rect.height > 0.85, f.rect.height / last.rect.height < 1.18,
               last.rect.minY - f.rect.maxY < 0.3 * f.rect.height, f.rect.midY < last.rect.midY {
                groups[groups.count - 1].append(f)
            } else {
                groups.append([f])
            }
            open = true
        }
        return groups
    }

    // MARK: Shared

    private static func pageIndices(_ doc: PDFDocument, _ pages: [Int]?) -> [Int] {
        (pages ?? Array(0..<doc.pageCount)).filter { $0 >= 0 && $0 < doc.pageCount }
    }

    /// The page as shown, with rotation and annotations, `scale` times its size in points.
    static func render(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let box = page.bounds(for: .cropBox)
        let rotated = ((page.rotation % 360) + 360) % 360 % 180 != 0
        let size = CGSize(width: (rotated ? box.height : box.width) * scale, height: (rotated ? box.width : box.height) * scale)
        guard size.width >= 1, size.height >= 1 else { return nil }
        let image = page.thumbnail(of: size, for: .cropBox)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func utf8(_ string: String) -> Data { Data(string.utf8) }

    /// Escapes the five XML characters and drops characters XML 1.0 forbids.
    static func escape(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for s in text.unicodeScalars {
            switch s.value {
            case 0x9, 0xA, 0xD, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF:
                switch s {
                case "&": out.append(contentsOf: "&amp;".unicodeScalars)
                case "<": out.append(contentsOf: "&lt;".unicodeScalars)
                case ">": out.append(contentsOf: "&gt;".unicodeScalars)
                case "\"": out.append(contentsOf: "&quot;".unicodeScalars)
                case "'": out.append(contentsOf: "&apos;".unicodeScalars)
                default: out.append(s)
                }
            default: break
            }
        }
        return String(out)
    }
}
