import AppKit
import PDFKit

/// Document-level operations. Everything here is UI-free so it can be unit tested.
public enum PDFOps {
    public static let letter = CGSize(width: 612, height: 792)
    public static let a4 = CGSize(width: 595, height: 842)

    public static func blankPage(size: CGSize = letter) -> PDFPage {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return PDFPage() }
        ctx.beginPDFPage(nil)
        ctx.endPDFPage()
        ctx.closePDF()
        guard let page = PDFDocument(data: data as Data)?.page(at: 0)?.copy() as? PDFPage else { return PDFPage() }
        return page
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

    public struct WriteOptions {
        public var flatten = false
        public var compressImages = false
        public var userPassword: String?
        public var ownerPassword: String?
        public init(flatten: Bool = false, compressImages: Bool = false, userPassword: String? = nil, ownerPassword: String? = nil) {
            self.flatten = flatten
            self.compressImages = compressImages
            self.userPassword = userPassword
            self.ownerPassword = ownerPassword
        }
    }

    @discardableResult
    public static func write(_ doc: PDFDocument, to url: URL, options: WriteOptions = WriteOptions()) -> Bool {
        var o: [PDFDocumentWriteOption: Any] = [:]
        if options.flatten { o[.burnInAnnotationsOption] = true }
        if options.compressImages {
            o[.saveImagesAsJPEGOption] = true
            o[.optimizeImagesForScreenOption] = true
        }
        if let user = options.userPassword, !user.isEmpty {
            o[.userPasswordOption] = user
            o[.ownerPasswordOption] = options.ownerPassword ?? user
        } else if let owner = options.ownerPassword, !owner.isEmpty {
            o[.ownerPasswordOption] = owner
        }
        return doc.write(to: url, withOptions: o)
    }
}
