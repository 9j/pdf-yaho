import AppKit
import PDFKit
import Quartz

/// Document-level operations. Everything here is UI-free so it can be unit tested.
public enum PDFOps {
    public static let letter = CGSize(width: 612, height: 792)
    public static let a4 = CGSize(width: 595, height: 842)

    /// Documents whose pages were handed out. A PDFPage can lose its content once the document
    /// it was parsed from is freed, so documents built in memory are kept alive for the session.
    nonisolated(unsafe) private static var sources: [PDFDocument] = []
    private static let sourcesLock = NSLock()

    /// The first page of freshly generated PDF data, safe to insert into another document.
    static func page(fromPDFData data: Data) -> PDFPage? {
        guard let doc = PDFDocument(data: data), let page = doc.page(at: 0)?.copy() as? PDFPage else { return nil }
        sourcesLock.lock()
        sources.append(doc)
        sourcesLock.unlock()
        return page
    }

    /// A one-page PDF of `page` with its annotations, for engines that work on whole files.
    public static func singlePageData(_ page: PDFPage) -> Data? {
        guard let copy = page.copy() as? PDFPage else { return nil }
        let doc = PDFDocument()
        doc.insert(copy, at: 0)
        return doc.dataRepresentation()
    }

    /// The first page of `data`, ready to put in another document, with Pagecraft's own annotations restored.
    public static func editablePage(fromPDFData data: Data) -> PDFPage? {
        guard let page = page(fromPDFData: data) else { return nil }
        _ = Annotations.restoreCustomAnnotations(on: page)
        return page
    }

    /// Copies of every page of `doc`, keeping `doc` alive so the copies stay valid.
    public static func adopt(_ doc: PDFDocument) -> [PDFPage] {
        sourcesLock.lock()
        sources.append(doc)
        sourcesLock.unlock()
        return copies(of: pages(of: doc))
    }

    public static func blankPage(size: CGSize = letter) -> PDFPage {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return PDFPage() }
        ctx.beginPDFPage(nil)
        ctx.endPDFPage()
        ctx.closePDF()
        return page(fromPDFData: data as Data) ?? PDFPage()
    }

    public static func pages(of doc: PDFDocument) -> [PDFPage] {
        (0..<doc.pageCount).compactMap { doc.page(at: $0) }
    }

    /// Replaces the page list of `doc`. Pages keep their annotations, so this doubles as an undo primitive.
    public static func setPages(_ pages: [PDFPage], in doc: PDFDocument) {
        while doc.pageCount > 0 { doc.removePage(at: doc.pageCount - 1) }
        for (i, page) in pages.enumerated() { doc.insert(page, at: i) }
    }

    public static func moved(_ pages: [PDFPage], from source: IndexSet, to destination: Int) -> [PDFPage] {
        var result = pages
        let moving = source.map { pages[$0] }
        for i in source.sorted(by: >) { result.remove(at: i) }
        let insertAt = destination - source.filter { $0 < destination }.count
        result.insert(contentsOf: moving, at: max(0, min(insertAt, result.count)))
        return result
    }

    public static func copies(of pages: [PDFPage]) -> [PDFPage] {
        pages.compactMap { $0.copy() as? PDFPage }
    }

    public static func merge(_ docs: [PDFDocument]) -> PDFDocument {
        let out = PDFDocument()
        for doc in docs {
            for page in copies(of: pages(of: doc)) { out.insert(page, at: out.pageCount) }
        }
        return out
    }

    public static func extract(_ indices: [Int], from doc: PDFDocument) -> PDFDocument {
        let out = PDFDocument()
        let selected = indices.sorted().compactMap { doc.page(at: $0) }
        for page in copies(of: selected) { out.insert(page, at: out.pageCount) }
        return out
    }

    public static func document(fromImages images: [NSImage]) -> PDFDocument {
        let out = PDFDocument()
        for image in images {
            if let page = PDFPage(image: image) { out.insert(page, at: out.pageCount) }
        }
        return out
    }

    /// Renders a page (including annotations, honouring rotation) to a bitmap.
    public static func renderImage(_ page: PDFPage, scale: CGFloat = 2) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let size = page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        page.draw(with: .mediaBox, to: ctx)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// Replaces a page by a flat image of itself. Used to make redactions irreversible:
    /// the text and vector content under a redaction box no longer exists afterwards.
    public static func rasterized(_ page: PDFPage, scale: CGFloat = 2) -> PDFPage? {
        guard let cg = renderImage(page, scale: scale) else { return nil }
        let size = CGSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale)
        return PDFPage(image: NSImage(cgImage: cg, size: size))
    }

    public static func pngData(_ page: PDFPage, scale: CGFloat = 2) -> Data? {
        guard let cg = renderImage(page, scale: scale) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    // MARK: Text export

    public static func plainText(_ doc: PDFDocument) -> String {
        pages(of: doc).map { $0.string ?? "" }.joined(separator: "\n\u{0C}\n")
    }

    public static func markdown(_ doc: PDFDocument, title: String) -> String {
        var out = "# \(title)\n"
        for (i, page) in pages(of: doc).enumerated() {
            out += "\n## Page \(i + 1)\n\n"
            out += (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        }
        return out
    }

    public static func annotationSummary(_ doc: PDFDocument, title: String) -> String {
        var out = "# Annotations — \(title)\n"
        for (i, page) in pages(of: doc).enumerated() {
            let items = page.annotations.filter(Annotations.isUserEditable)
            guard !items.isEmpty else { continue }
            out += "\n## Page \(i + 1)\n\n"
            for a in items {
                var line = "- **\(Annotations.displayName(a))**"
                if let quoted = Annotations.markedText(a, on: page), !quoted.isEmpty { line += " “\(quoted)”" }
                if let contents = a.contents, !contents.isEmpty, contents != Annotations.markedText(a, on: page) {
                    line += " — \(contents)"
                }
                out += line + "\n"
            }
        }
        return out
    }

    // MARK: Page numbers

    public static let pageNumberTag = "org.pagecraft.page-number"

    @discardableResult
    public static func addPageNumbers(to doc: PDFDocument, format: String = "%d / %d", fontSize: CGFloat = 10)
        -> [(page: PDFPage, annotation: PDFAnnotation)]
    {
        let all = pages(of: doc)
        return all.enumerated().map { i, page in
            let box = page.bounds(for: .cropBox)
            let text = String(format: format, i + 1, all.count)
            let rect = CGRect(x: box.midX - 60, y: box.minY + 16, width: 120, height: fontSize + 8)
            let a = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
            a.contents = text
            a.font = NSFont.systemFont(ofSize: fontSize)
            a.fontColor = .black
            a.color = .clear
            a.alignment = .center
            a.userName = pageNumberTag
            let border = PDFBorder()
            border.lineWidth = 0
            a.border = border
            page.addAnnotation(a)
            return (page, a)
        }
    }

    @discardableResult
    public static func removePageNumbers(from doc: PDFDocument) -> [(page: PDFPage, annotation: PDFAnnotation)] {
        var removed: [(PDFPage, PDFAnnotation)] = []
        for page in pages(of: doc) {
            for a in page.annotations where a.userName == pageNumberTag {
                page.removeAnnotation(a)
                removed.append((page, a))
            }
        }
        return removed
    }

    // MARK: Writing

    /// Image quality presets for Reduce File Size. `lossless` only re-optimises the file structure.
    public enum Compression: String, CaseIterable, Identifiable, Sendable {
        case lossless = "Lossless", high = "High", medium = "Medium", low = "Low"
        public var id: String { rawValue }
        var jpegQuality: Double { self == .high ? 0.8 : self == .medium ? 0.6 : 0.35 }
        var resolution: Int { self == .high ? 200 : self == .medium ? 144 : 96 }
        public var detail: String {
            switch self {
            case .lossless: "Restructures the file without touching images"
            case .high: "Images at 200 dpi, light JPEG compression"
            case .medium: "Images at 144 dpi, balanced for screens"
            case .low: "Images at 96 dpi, smallest file"
            }
        }
    }

    public struct WriteOptions {
        public var flatten = false
        public var compression: Compression?
        public var performOCR = false
        public var userPassword: String?
        public var ownerPassword: String?
        /// Page labels to write; nil keeps whatever PDFKit writes.
        public var pageLabels: [PageLabelRange]?
        public init(flatten: Bool = false, compression: Compression? = nil, performOCR: Bool = false,
                    userPassword: String? = nil, ownerPassword: String? = nil, pageLabels: [PageLabelRange]? = nil) {
            self.pageLabels = pageLabels
            self.flatten = flatten
            self.compression = compression
            self.performOCR = performOCR
            self.userPassword = userPassword
            self.ownerPassword = ownerPassword
        }

        var dictionary: [PDFDocumentWriteOption: Any] {
            var o: [PDFDocumentWriteOption: Any] = [:]
            if flatten { o[.burnInAnnotationsOption] = true }
            if performOCR { o[.saveTextFromOCROption] = true }
            if let compression {
                o[.optimizeImagesForScreenOption] = true
                if compression != .lossless {
                    o[.saveImagesAsJPEGOption] = true
                    if let filter = PDFOps.compressionFilter(compression) { o[PDFDocumentWriteOption(rawValue: "QuartzFilter")] = filter }
                }
            }
            if let user = userPassword, !user.isEmpty {
                o[.userPasswordOption] = user
                o[.ownerPasswordOption] = ownerPassword ?? user
            } else if let owner = ownerPassword, !owner.isEmpty {
                o[.ownerPasswordOption] = owner
            }
            return o
        }
    }

    @discardableResult
    public static func write(_ doc: PDFDocument, to url: URL, options: WriteOptions = WriteOptions()) -> Bool {
        guard options.pageLabels != nil else { return doc.write(to: url, withOptions: options.dictionary) }
        guard let data = data(doc, options: options) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    public static func data(_ doc: PDFDocument, options: WriteOptions = WriteOptions()) -> Data? {
        guard let labels = options.pageLabels else { return doc.dataRepresentation(options: options.dictionary) }
        // PDFKit drops page labels when it writes, so they go in as an incremental update afterwards.
        var base = options
        base.pageLabels = nil
        guard let data = data(doc, options: base) else { return nil }
        return PageLabels.apply(labels, to: data, password: options.userPassword ?? "")
    }

    /// A Quartz filter like the system "Reduce File Size", with the preset's quality and resolution.
    static func compressionFilter(_ compression: Compression) -> QuartzFilter? {
        let plist: [String: Any] = [
            "Domains": ["Applications": true, "Printing": true],
            "FilterType": 1,
            "Name": "Pagecraft \(compression.rawValue)",
            "FilterData": ["ColorSettings": ["ImageSettings": [
                "Compression Quality": compression.jpegQuality,
                "ImageCompression": "ImageJPEGCompress",
                "ImageScaleSettings": ["ImageResolution": compression.resolution, "ImageScaleInterpolate": true,
                                       "ImageSizeMax": 4000, "ImageSizeMin": 0],
            ]]],
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pagecraft-\(compression.rawValue).qfilter")
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
              (try? data.write(to: url)) != nil
        else { return nil }
        return QuartzFilter(url: url)
    }

    // MARK: Rich export

    public enum TextFormat: String, CaseIterable, Sendable {
        case word = "docx", rtf, html
        var documentType: NSAttributedString.DocumentType {
            switch self {
            case .word: .officeOpenXML
            case .rtf: .rtf
            case .html: .html
            }
        }
    }

    /// The document's text with fonts and styles, one page after another.
    public static func attributedText(_ doc: PDFDocument) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (i, page) in pages(of: doc).enumerated() {
            if i > 0 { out.append(NSAttributedString(string: "\n\u{0C}")) }
            if let text = page.attributedString { out.append(text) }
        }
        return out
    }

    public static func exportData(_ doc: PDFDocument, as format: TextFormat) -> Data? {
        let text = attributedText(doc)
        return try? text.data(from: NSRange(location: 0, length: text.length),
                              documentAttributes: [.documentType: format.documentType])
    }

    public enum ImageFormat: String, CaseIterable, Identifiable, Sendable {
        case png = "PNG", jpeg = "JPEG", tiff = "TIFF"
        public var id: String { rawValue }
        public var fileExtension: String { self == .jpeg ? "jpg" : rawValue.lowercased() }
        var fileType: NSBitmapImageRep.FileType { self == .png ? .png : self == .jpeg ? .jpeg : .tiff }
    }

    public static func imageData(_ page: PDFPage, format: ImageFormat, dpi: CGFloat) -> Data? {
        guard let cg = renderImage(page, scale: dpi / 72) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: CGFloat(cg.width) * 72 / dpi, height: CGFloat(cg.height) * 72 / dpi)
        return rep.representation(using: format.fileType, properties: format == .jpeg ? [.compressionFactor: 0.88] : [:])
    }

    /// Annotations as XFDF, the XML exchange format other PDF apps import.
    public static func xfdf(_ doc: PDFDocument, fileName: String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        func hex(_ c: NSColor) -> String {
            let c = c.usingColorSpace(.sRGB) ?? c
            return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        }
        let tags = ["Highlight": "highlight", "Underline": "underline", "StrikeOut": "strikeout", "Squiggly": "squiggly",
                    "Ink": "ink", "FreeText": "freetext", "Text": "text", "Square": "square", "Circle": "circle",
                    "Line": "line", "Stamp": "stamp", "Link": "link"]
        var lines = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                     "<xfdf xmlns=\"http://ns.adobe.com/xfdf/\" xml:space=\"preserve\">",
                     "<f href=\"\(esc(fileName))\"/>", "<annots>"]
        for (index, page) in pages(of: doc).enumerated() {
            for a in page.annotations where Annotations.isUserEditable(a) {
                guard let tag = tags[a.type ?? ""] else { continue }
                let r = a.bounds
                var attrs = "page=\"\(index)\" rect=\"\(r.minX),\(r.minY),\(r.maxX),\(r.maxY)\" color=\"\(hex(Annotations.color(of: a)))\""
                if let author = a.userName, !author.hasPrefix("org.pagecraft") { attrs += " title=\"\(esc(author))\"" }
                if let date = a.modificationDate { attrs += " date=\"\(ISO8601DateFormatter().string(from: date))\"" }
                if tag == "line" {
                    let s = a.startPoint + r.origin, e = a.endPoint + r.origin
                    attrs += " start=\"\(s.x),\(s.y)\" end=\"\(e.x),\(e.y)\""
                }
                if ["highlight", "underline", "strikeout", "squiggly"].contains(tag) {
                    attrs += " coords=\"\(r.minX),\(r.maxY),\(r.maxX),\(r.maxY),\(r.minX),\(r.minY),\(r.maxX),\(r.minY)\""
                }
                var body = ""
                if let contents = a.contents, !contents.isEmpty { body += "<contents>\(esc(contents))</contents>" }
                if tag == "ink", let paths = a.paths {
                    body += "<inklist>" + paths.map { path in
                        var points: [String] = []
                        var pts = [NSPoint](repeating: .zero, count: 3)
                        for i in 0..<path.elementCount {
                            path.element(at: i, associatedPoints: &pts)
                            points.append("\(pts[0].x + r.minX),\(pts[0].y + r.minY)")
                        }
                        return "<gesture>\(points.joined(separator: ";"))</gesture>"
                    }.joined() + "</inklist>"
                }
                lines.append("<\(tag) \(attrs)>\(body)</\(tag)>")
            }
        }
        lines += ["</annots>", "</xfdf>"]
        return lines.joined(separator: "\n")
    }
}
