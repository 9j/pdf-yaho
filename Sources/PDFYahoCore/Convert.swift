import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Turning other files into PDF.
public enum Convert {
    public static let supportedTypes: [UTType] = [
        .image, .plainText, .rtf, .rtfd, .html, UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "docx") ?? .data, UTType(filenameExtension: "doc") ?? .data,
        UTType(filenameExtension: "odt") ?? .data, .pdf,
    ]

    public enum Failure: Error { case unreadable }

    /// A PDF made from an image, PDF, Word/ODT/RTF/HTML document, Markdown or plain text file.
    public static func document(from url: URL, pageSize: CGSize = PDFOps.a4) throws -> PDFDocument {
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        if type?.conforms(to: .pdf) == true, let doc = PDFDocument(url: url) { return doc }
        if type?.conforms(to: .image) == true, let image = NSImage(contentsOf: url) {
            return PDFOps.document(fromImages: [image])
        }
        return paginate(try attributedText(from: url), pageSize: pageSize)
    }

    static func attributedText(from url: URL) throws -> NSAttributedString {
        let ext = url.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            let source = try String(contentsOf: url, encoding: .utf8)
            let parsed = try AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            let text = NSMutableAttributedString(parsed)
            text.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: NSRange(location: 0, length: text.length))
            return text
        }
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        switch ext {
        case "docx": options[.documentType] = NSAttributedString.DocumentType.officeOpenXML
        case "doc": options[.documentType] = NSAttributedString.DocumentType.docFormat
        case "odt": options[.documentType] = NSAttributedString.DocumentType.openDocument
        case "html", "htm": options[.documentType] = NSAttributedString.DocumentType.html
        case "rtf": options[.documentType] = NSAttributedString.DocumentType.rtf
        case "rtfd": options[.documentType] = NSAttributedString.DocumentType.rtfd
        case "txt", "text", "csv", "log":
            let text = try String(contentsOf: url, encoding: .utf8)
            return NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)])
        default: break
        }
        guard let text = try? NSAttributedString(url: url, options: options, documentAttributes: nil) else { throw Failure.unreadable }
        return text
    }

    /// Lays text out across as many pages as it needs, keeping fonts, colours and paragraph styles.
    public static func paginate(_ text: NSAttributedString, pageSize: CGSize = PDFOps.a4, margin: CGFloat = 54) -> PDFDocument {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let area = CGSize(width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
        var containers: [NSTextContainer] = []
        repeat {
            let container = NSTextContainer(size: area)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            containers.append(container)
            layout.ensureLayout(for: container)
        } while NSMaxRange(layout.glyphRange(for: containers.last!)) < layout.numberOfGlyphs && containers.count < 2000

        let data = NSMutableData()
        var media = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData), let ctx = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            return PDFDocument()
        }
        for container in containers {
            ctx.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            // Text system draws top-down, so flip the page.
            ctx.translateBy(x: 0, y: pageSize.height)
            ctx.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            let range = layout.glyphRange(for: container)
            layout.drawBackground(forGlyphRange: range, at: CGPoint(x: margin, y: margin))
            layout.drawGlyphs(forGlyphRange: range, at: CGPoint(x: margin, y: margin))
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return PDFDocument(data: data as Data) ?? PDFDocument()
    }
}

/// Distance and area measurement at a drawing scale.
public enum Measure {
    public enum Unit: String, CaseIterable, Identifiable, Sendable {
        case mm, cm, m, inch = "in", ft, pt
        public var id: String { rawValue }
        /// Length of one unit in PDF points at 1:1.
        public var points: Double {
            switch self {
            case .mm: 72 / 25.4
            case .cm: 72 / 2.54
            case .m: 72 / 0.0254
            case .inch: 72
            case .ft: 72 * 12
            case .pt: 1
            }
        }
    }

    /// `ratio` real-world units per unit on paper, e.g. 100 for a 1:100 drawing.
    public struct Scale: Equatable, Sendable {
        public var unit: Unit
        public var ratio: Double
        public init(unit: Unit = .mm, ratio: Double = 1) { self.unit = unit; self.ratio = ratio }

        public func length(_ points: Double) -> Double { points / unit.points * ratio }
        public func area(_ squarePoints: Double) -> Double { squarePoints / (unit.points * unit.points) * ratio * ratio }

        public func format(length points: Double) -> String { "\(formatted(length(points))) \(unit.rawValue)" }
        public func format(area squarePoints: Double) -> String { "\(formatted(area(squarePoints))) \(unit.rawValue)²" }

        private func formatted(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(value < 10 ? 2 : value < 1000 ? 1 : 0)))
        }
    }

    public static func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(Double(b.x - a.x), Double(b.y - a.y)) }

    public static func perimeter(_ points: [CGPoint], closed: Bool) -> Double {
        guard points.count > 1 else { return 0 }
        let pairs = zip(points, points.dropFirst()).map { distance($0, $1) }.reduce(0, +)
        return closed ? pairs + distance(points.last!, points[0]) : pairs
    }

    /// Shoelace formula.
    public static func area(_ points: [CGPoint]) -> Double {
        guard points.count > 2 else { return 0 }
        var sum = 0.0
        for i in points.indices {
            let p = points[i], q = points[(i + 1) % points.count]
            sum += Double(p.x * q.y - q.x * p.y)
        }
        return abs(sum) / 2
    }
}
