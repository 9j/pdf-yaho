import AppKit
import PDFKit

/// Page-level transformations: resizing, cropping, splitting, headers and footers.
public enum PageOps {
    // MARK: Page size

    public struct PaperSize: Hashable, Identifiable, Sendable {
        public let name: String
        public let size: CGSize
        public var id: String { name }
        public static let a3 = PaperSize(name: "A3", size: CGSize(width: 842, height: 1191))
        public static let a4 = PaperSize(name: "A4", size: CGSize(width: 595, height: 842))
        public static let a5 = PaperSize(name: "A5", size: CGSize(width: 420, height: 595))
        public static let letter = PaperSize(name: "US Letter", size: CGSize(width: 612, height: 792))
        public static let legal = PaperSize(name: "US Legal", size: CGSize(width: 612, height: 1008))
        public static let tabloid = PaperSize(name: "Tabloid", size: CGSize(width: 792, height: 1224))
        public static let all: [PaperSize] = [.a4, .letter, .a3, .a5, .legal, .tabloid]
    }

    /// The page as displayed: crop box with rotation applied.
    public static func displaySize(_ page: PDFPage) -> CGSize {
        let box = page.bounds(for: .cropBox).size
        return page.rotation % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
    }

    /// Redraws a page onto a new page of `size`, keeping text and vector content.
    /// Rotation and crop are baked in. Annotations are carried over and moved with the content.
    public static func redrawn(_ page: PDFPage, size: CGSize, scaleToFit: Bool = true) -> PDFPage? {
        guard let cgPage = page.pageRef else { return nil }
        let crop = page.bounds(for: .cropBox)
        let shown = displaySize(page)
        let scale = scaleToFit ? min(size.width / shown.width, size.height / shown.height) : 1
        var transform = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
            .scaledBy(x: scale, y: scale)
            .rotated(by: -CGFloat(page.rotation) * .pi / 180)
            .translatedBy(x: -crop.midX, y: -crop.midY)

        let data = NSMutableData()
        var media = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &media, nil) else { return nil }
        ctx.beginPDFPage(nil)
        ctx.concatenate(transform)
        ctx.clip(to: crop)
        ctx.drawPDFPage(cgPage)
        ctx.endPDFPage()
        ctx.closePDF()
        guard let result = PDFOps.page(fromPDFData: data as Data) else { return nil }

        for annotation in page.annotations {
            guard let copy = annotation.copy() as? PDFAnnotation else { continue }
            if let paths = annotation.paths, copy.paths?.isEmpty ?? true { paths.forEach { copy.add($0.copy() as! NSBezierPath) } }
            let mapped = annotation.bounds.applying(transform)
            if page.rotation == 0 {
                Annotations.resize(copy, to: mapped)
            } else {
                copy.bounds = mapped
            }
            result.addAnnotation(copy)
        }
        transform = .identity
        return result
    }

    // MARK: Crop

    /// Bounding box of everything that is not near-white, in page space, or nil for a blank page.
    public static func contentBounds(_ page: PDFPage) -> CGRect? {
        let box = page.bounds(for: .mediaBox)
        let scale: CGFloat = 0.5
        let width = Int(box.width * scale), height = Int(box.height * scale)
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cgPage = page.pageRef
        else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(cgPage)
        guard let pixels = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if pixels[i] < 235 || pixels[i + 1] < 235 || pixels[i + 2] < 235 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        // Bitmap rows run top to bottom.
        return CGRect(x: box.minX + CGFloat(minX) / scale, y: box.minY + CGFloat(height - 1 - maxY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }

    // MARK: Split

    public enum SplitMode: Equatable, Sendable {
        case everyPages(Int)
        case oddEven
        case ranges([ClosedRange<Int>])
    }

    /// Parses "1-3, 5, 8-10" (1-based) into zero-based ranges, or nil if any part is invalid.
    public static func parseRanges(_ text: String, pageCount: Int) -> [ClosedRange<Int>]? {
        var result: [ClosedRange<Int>] = []
        for part in text.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !part.isEmpty {
            let bounds = part.split(separator: "-").map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard bounds.count <= 2, let first = bounds.first ?? nil, let last = bounds.last ?? nil,
                  first >= 1, last >= first, last <= pageCount else { return nil }
            result.append((first - 1)...(last - 1))
        }
        return result.isEmpty ? nil : result
    }

    /// Splits into named parts; names are suffixes such as "pages 1-3".
    public static func split(_ doc: PDFDocument, mode: SplitMode) -> [(name: String, document: PDFDocument)] {
        let count = doc.pageCount
        func part(_ indices: [Int], _ name: String) -> (String, PDFDocument) { (name, PDFOps.extract(indices, from: doc)) }
        func label(_ r: ClosedRange<Int>) -> String { r.count == 1 ? "page \(r.lowerBound + 1)" : "pages \(r.lowerBound + 1)-\(r.upperBound + 1)" }
        switch mode {
        case let .everyPages(n):
            guard n > 0 else { return [] }
            return stride(from: 0, to: count, by: n).map { start in
                let r = start...min(start + n - 1, count - 1)
                return part(Array(r), label(r))
            }
        case .oddEven:
            return [part(Array(stride(from: 0, to: count, by: 2)), "odd pages"),
                    part(Array(stride(from: 1, to: count, by: 2)), "even pages")].filter { $0.1.pageCount > 0 }
        case let .ranges(ranges):
            return ranges.map { part(Array($0), label($0)) }
        }
    }

    // MARK: Header, footer and Bates numbering

    public enum Position: String, CaseIterable, Identifiable, Sendable {
        case topLeft = "Top Left", topCenter = "Top Center", topRight = "Top Right"
        case bottomLeft = "Bottom Left", bottomCenter = "Bottom Center", bottomRight = "Bottom Right"
        public var id: String { rawValue }
        var isTop: Bool { [.topLeft, .topCenter, .topRight].contains(self) }
        var alignment: NSTextAlignment {
            switch self {
            case .topLeft, .bottomLeft: .left
            case .topCenter, .bottomCenter: .center
            case .topRight, .bottomRight: .right
            }
        }
    }

    public struct Stamp: Equatable, Sendable {
        /// Text with tokens: {page}, {total}, {bates}, {date}, {file}.
        public var template: String
        public var position: Position
        public var fontSize: CGFloat
        public var margin: CGFloat
        public var firstNumber: Int
        public var batesPrefix: String
        public var batesDigits: Int
        public var batesSuffix: String

        public init(template: String = "{page} of {total}", position: Position = .bottomCenter, fontSize: CGFloat = 10,
                    margin: CGFloat = 24, firstNumber: Int = 1, batesPrefix: String = "", batesDigits: Int = 6, batesSuffix: String = "") {
            self.template = template
            self.position = position
            self.fontSize = fontSize
            self.margin = margin
            self.firstNumber = firstNumber
            self.batesPrefix = batesPrefix
            self.batesDigits = batesDigits
            self.batesSuffix = batesSuffix
        }

        public func text(pageIndex: Int, total: Int, fileName: String, date: Date = Date()) -> String {
            let number = firstNumber + pageIndex
            let bates = batesPrefix + String(format: "%0\(max(batesDigits, 1))d", number) + batesSuffix
            return template
                .replacingOccurrences(of: "{page}", with: "\(number)")
                .replacingOccurrences(of: "{total}", with: "\(total + firstNumber - 1)")
                .replacingOccurrences(of: "{bates}", with: bates)
                .replacingOccurrences(of: "{date}", with: date.formatted(date: .abbreviated, time: .omitted))
                .replacingOccurrences(of: "{file}", with: fileName)
        }
    }

    public static let stampTag = "org.pagecraft.header-footer"

    /// Adds the stamp to each listed page as a removable text annotation.
    @discardableResult
    public static func addStamp(_ stamp: Stamp, to doc: PDFDocument, pages indices: [Int], fileName: String)
        -> [(page: PDFPage, annotation: PDFAnnotation)]
    {
        indices.compactMap { index in
            guard let page = doc.page(at: index) else { return nil }
            let box = page.bounds(for: .cropBox)
            let text = stamp.text(pageIndex: index, total: doc.pageCount, fileName: fileName)
            let font = NSFont.systemFont(ofSize: stamp.fontSize)
            let width = min(box.width - stamp.margin * 2, max(80, (text as NSString).size(withAttributes: [.font: font]).width + 16))
            let height = stamp.fontSize + 8
            let x: CGFloat
            switch stamp.position.alignment {
            case .left: x = box.minX + stamp.margin
            case .right: x = box.maxX - stamp.margin - width
            default: x = box.midX - width / 2
            }
            let y = stamp.position.isTop ? box.maxY - stamp.margin - height : box.minY + stamp.margin
            let a = PDFAnnotation(bounds: CGRect(x: x, y: y, width: width, height: height), forType: .freeText, withProperties: nil)
            a.contents = text
            a.font = font
            a.fontColor = .black
            a.color = .clear
            a.alignment = stamp.position.alignment
            a.userName = stampTag
            let border = PDFBorder()
            border.lineWidth = 0
            a.border = border
            page.addAnnotation(a)
            return (page, a)
        }
    }

    @discardableResult
    public static func removeStamps(from doc: PDFDocument) -> [(page: PDFPage, annotation: PDFAnnotation)] {
        var removed: [(PDFPage, PDFAnnotation)] = []
        for page in PDFOps.pages(of: doc) {
            for a in page.annotations where a.userName == stampTag || a.userName == PDFOps.pageNumberTag {
                page.removeAnnotation(a)
                removed.append((page, a))
            }
        }
        return removed
    }

    // MARK: Pages from the clipboard

    public static func pages(from pasteboard: NSPasteboard) -> [PDFPage] {
        if let data = pasteboard.data(forType: .pdf), let doc = PDFDocument(data: data) {
            return PDFOps.adopt(doc)
        }
        if let image = NSImage(pasteboard: pasteboard), let page = PDFPage(image: image) {
            return [page]
        }
        return []
    }
}
