import AppKit
import CoreText
#if PDFIUM
import CPDFium
#endif

/// An editable piece of page content: a paragraph of text or an image, in page space.
public struct ContentBlock: Identifiable, Equatable {
    public enum Kind: Equatable, Sendable { case text, image }

    public let id: Int
    public let kind: Kind
    public let bounds: CGRect
    public let text: String
    public let style: TextStyle
    /// Object paths (page object index, then indices inside form objects) of everything the block is made of.
    let members: [[Int]]
}

public struct TextStyle: Equatable, Sendable {
    public var fontName: String
    public var fontSize: CGFloat
    public var color: NSColor
    public var alignment: NSTextAlignment
    /// Baseline-to-baseline distance, or nil for the font's own.
    public var lineHeight: CGFloat?

    public init(fontName: String = "Helvetica", fontSize: CGFloat = 12, color: NSColor = .black,
                alignment: NSTextAlignment = .left, lineHeight: CGFloat? = nil) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.color = color
        self.alignment = alignment
        self.lineHeight = lineHeight
    }

    public var font: NSFont {
        if fontName.hasPrefix(ContentEditor.systemFontPrefix) {
            let font = NSFont.systemFont(ofSize: fontSize, weight: fontName.contains("Bold") ? .bold : .regular)
            return fontName.hasSuffix("Italic") ? NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) : font
        }
        return NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
    }

    /// A readable name for menus: the family and face.
    public var displayName: String {
        fontName.hasPrefix(ContentEditor.systemFontPrefix) ? "System " + fontName.dropFirst(ContentEditor.systemFontPrefix.count)
            : font.displayName ?? fontName
    }
}

/// Edits the text and images that make up a page (not annotations), using PDFium.
/// Every call takes PDF data and returns new PDF data, so the caller owns undo and page swapping.
public enum ContentEditor {
    /// Whether this build includes PDFium (see scripts/fetch-pdfium.sh).
    public static var isAvailable: Bool {
        #if PDFIUM
        true
        #else
        false
        #endif
    }

    /// Font names for the system UI font, which has no public PostScript name: "System-Bold" and so on.
    public static let systemFontPrefix = "System-"

    /// Lays out `text` with CoreText into a one-page PDF whose page is exactly the text frame (plus `padding`).
    /// CoreGraphics embeds font subsets, so any script and font works. The result is ordinary page text,
    /// so later edits find it the same way as the original text.
    static func textPDF(_ text: String, style: TextStyle, width: CGFloat?, padding: CGFloat = 2) -> (data: Data, size: CGSize)? {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = style.alignment
        if let lineHeight = style.lineHeight, lineHeight > 0 {
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
        }
        let attributed = NSAttributedString(string: text, attributes: [
            .font: style.font, .foregroundColor: style.color, .paragraphStyle: paragraph,
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let limit = CGSize(width: width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil, limit, nil)
        let frameSize = CGSize(width: ceil(width ?? fit.width) + 1, height: ceil(fit.height) + 1)
        var box = CGRect(origin: .zero, size: CGSize(width: frameSize.width + padding * 2, height: frameSize.height + padding * 2))
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return nil }
        ctx.beginPDFPage(nil)
        ctx.textMatrix = .identity
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: CGRect(origin: CGPoint(x: padding, y: padding), size: frameSize), transform: nil), nil)
        CTFrameDraw(frame, ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        return (data as Data, box.size)
    }

    /// The installed font closest to a PDF font: its own name without the subset tag, then its family and traits.
    static func matchingFontName(baseName: String, family: String, bold: Bool, italic: Bool, serif: Bool, fixedPitch: Bool) -> String {
        var name = baseName
        if let plus = name.firstIndex(of: "+"), name.distance(from: name.startIndex, to: plus) == 6 { name = String(name[name.index(after: plus)...]) }
        if let variation = name.range(of: "_") { name = String(name[..<variation.lowerBound]) }
        // The system UI font has private names; keep it as the system font in the right weight.
        if name.hasPrefix(".SF") { return systemFontPrefix + (bold ? "Bold" : "Regular") + (italic ? "Italic" : "") }
        for candidate in [name, name.replacingOccurrences(of: ",", with: "-"), name.replacingOccurrences(of: " ", with: "")] {
            if let font = NSFont(name: candidate, size: 12) { return font.fontName }
        }
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        let manager = NSFontManager.shared
        let familyGuess = family.isEmpty ? String(name.split(separator: "-").first ?? "") : family
        if !familyGuess.isEmpty, let font = manager.font(withFamily: familyGuess, traits: traits, weight: bold ? 9 : 5, size: 12) {
            return font.fontName
        }
        let fallback = fixedPitch ? "Menlo" : serif ? "Times New Roman" : "Helvetica"
        let base = NSFont(name: fallback, size: 12) ?? .systemFont(ofSize: 12)
        return manager.convert(base, toHaveTrait: traits).fontName
    }
}

#if PDFIUM
extension ContentEditor {
    private struct Leaf {
        let path: [Int]
        let object: FPDF_PAGEOBJECT
        let parent: FPDF_PAGEOBJECT?
        /// Maps the object's container space to page space.
        let toPage: CGAffineTransform
        let type: Int32
        var bounds: CGRect {
            var l: Float = 0, b: Float = 0, r: Float = 0, t: Float = 0
            guard FPDFPageObj_GetBounds(object, &l, &b, &r, &t) != 0 else { return .null }
            return CGRect(x: CGFloat(l), y: CGFloat(b), width: CGFloat(r - l), height: CGFloat(t - b)).applying(toPage)
        }
    }

    private struct Run {
        let leaf: Leaf
        let text: String
        let bounds: CGRect
        let size: CGFloat
        let color: NSColor
        let font: FPDF_FONT?
    }

    // MARK: Reading

    /// The text paragraphs and images on page `index` of `data`.
    public static func blocks(inPage index: Int = 0, of data: Data) -> [ContentBlock] {
        guard let doc = PDFiumDocument(data: data) else { return [] }
        return doc.withPage(index) { page in blocks(of: page) } ?? []
    }

    private static func blocks(of page: FPDF_PAGE) -> [ContentBlock] {
        let all = leaves(of: page)
        var blocks: [ContentBlock] = []
        if let textPage = FPDFText_LoadPage(page) {
            let runs = all.filter { $0.type == FPDF_PAGEOBJ_TEXT }.compactMap { run(for: $0, textPage: textPage) }
            FPDFText_ClosePage(textPage)
            blocks += paragraphs(from: runs)
        }
        for leaf in all where leaf.type == FPDF_PAGEOBJ_IMAGE {
            let bounds = leaf.bounds
            guard bounds.width > 2, bounds.height > 2 else { continue }
            blocks.append(ContentBlock(id: 0, kind: .image, bounds: bounds, text: "", style: TextStyle(), members: [leaf.path]))
        }
        return blocks.enumerated().map { i, b in
            ContentBlock(id: i, kind: b.kind, bounds: b.bounds, text: b.text, style: b.style, members: b.members)
        }
    }

    private static func leaves(of page: FPDF_PAGE) -> [Leaf] {
        var out: [Leaf] = []
        func visit(_ object: FPDF_PAGEOBJECT, path: [Int], parent: FPDF_PAGEOBJECT?, toPage: CGAffineTransform, depth: Int) {
            let type = FPDFPageObj_GetType(object)
            if type == FPDF_PAGEOBJ_FORM, depth < 8 {
                let inner = matrix(of: object).concatenating(toPage)
                for i in 0..<max(0, Int(FPDFFormObj_CountObjects(object))) {
                    if let child = FPDFFormObj_GetObject(object, UInt(i)) {
                        visit(child, path: path + [i], parent: object, toPage: inner, depth: depth + 1)
                    }
                }
            } else {
                out.append(Leaf(path: path, object: object, parent: parent, toPage: toPage, type: type))
            }
        }
        for i in 0..<Int(FPDFPage_CountObjects(page)) {
            if let object = FPDFPage_GetObject(page, Int32(i)) { visit(object, path: [i], parent: nil, toPage: .identity, depth: 0) }
        }
        return out
    }

    private static func matrix(of object: FPDF_PAGEOBJECT) -> CGAffineTransform {
        var m = FS_MATRIX()
        guard FPDFPageObj_GetMatrix(object, &m) != 0 else { return .identity }
        return CGAffineTransform(a: CGFloat(m.a), b: CGFloat(m.b), c: CGFloat(m.c), d: CGFloat(m.d), tx: CGFloat(m.e), ty: CGFloat(m.f))
    }

    private static func run(for leaf: Leaf, textPage: FPDF_TEXTPAGE) -> Run? {
        // Invisible text is an OCR layer over a scan; editing it would change nothing visible.
        guard FPDFTextObj_GetTextRenderMode(leaf.object) != FPDF_TEXTRENDERMODE_INVISIBLE else { return nil }
        let length = FPDFTextObj_GetText(leaf.object, textPage, nil, 0)
        guard length > 2 else { return nil }
        var buffer = [UInt16](repeating: 0, count: Int(length) / 2 + 1)
        _ = FPDFTextObj_GetText(leaf.object, textPage, &buffer, length)
        let text = String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)
        let bounds = leaf.bounds
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !bounds.isNull, bounds.width > 0 else { return nil }
        var size: Float = 0
        _ = FPDFTextObj_GetFontSize(leaf.object, &size)
        let m = matrix(of: leaf.object).concatenating(leaf.toPage)
        let effective = CGFloat(size) * hypot(m.c, m.d)
        var r: UInt32 = 0, g: UInt32 = 0, b: UInt32 = 0, a: UInt32 = 255
        _ = FPDFPageObj_GetFillColor(leaf.object, &r, &g, &b, &a)
        let color = NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        return Run(leaf: leaf, text: text, bounds: bounds, size: effective > 0.5 ? effective : bounds.height, color: color,
                   font: FPDFTextObj_GetFont(leaf.object))
    }

    /// Groups runs into lines (same baseline, small gaps) and lines into paragraphs (stacked, similar size).
    private static func paragraphs(from runs: [Run]) -> [ContentBlock] {
        struct Line { var runs: [Run]; var bounds: CGRect; var size: CGFloat; var text: String }
        var lines: [Line] = []
        for run in runs.sorted(by: { ($0.bounds.midY, -$0.bounds.minX) > ($1.bounds.midY, -$1.bounds.minX) }) {
            if let i = lines.lastIndex(where: { line in
                let overlap = min(line.bounds.maxY, run.bounds.maxY) - max(line.bounds.minY, run.bounds.minY)
                let gap = run.bounds.minX - line.bounds.maxX
                return overlap > 0.5 * min(line.bounds.height, run.bounds.height)
                    && gap > -0.5 * line.size && gap < 1.5 * max(line.size, run.size)
                    && run.size / line.size > 0.6 && run.size / line.size < 1.6
            }) {
                let gap = run.bounds.minX - lines[i].bounds.maxX
                let needsSpace = gap > 0.2 * run.size && !lines[i].text.hasSuffix(" ") && !run.text.hasPrefix(" ")
                lines[i].text += (needsSpace ? " " : "") + run.text
                lines[i].runs.append(run)
                lines[i].bounds = lines[i].bounds.union(run.bounds)
            } else {
                lines.append(Line(runs: [run], bounds: run.bounds, size: run.size, text: run.text))
            }
        }

        var groups: [[Line]] = []
        for line in lines.sorted(by: { $0.bounds.maxY > $1.bounds.maxY }) {
            if let i = groups.lastIndex(where: { group in
                guard let last = group.last else { return false }
                let gap = last.bounds.minY - line.bounds.maxY
                let width = group.map(\.bounds).reduce(CGRect.null) { $0.union($1) }
                return gap > -0.3 * line.size && gap < 0.9 * line.size
                    && line.bounds.minX < width.maxX && line.bounds.maxX > width.minX
                    && line.size / last.size > 0.8 && line.size / last.size < 1.25
            }) {
                groups[i].append(line)
            } else {
                groups.append([line])
            }
        }

        return groups.map { group in
            let bounds = group.map(\.bounds).reduce(CGRect.null) { $0.union($1) }
            var text = ""
            for (i, line) in group.enumerated() {
                let body = line.text.trimmingCharacters(in: .whitespaces)
                if i > 0 {
                    // A line that stops well short of the paragraph's right edge ended with a real line break.
                    let previous = group[i - 1]
                    let hardBreak = previous.bounds.maxX < bounds.maxX - 3 * previous.size
                    if text.hasSuffix("-"), !hardBreak { text.removeLast() } else { text += hardBreak ? "\n" : " " }
                }
                text += body
            }
            let sizes = group.flatMap { $0.runs.map(\.size) }
            let size = (sizes.sorted()[sizes.count / 2] * 2).rounded() / 2
            // The paragraph's style is that of most of its characters, not of whichever run came first.
            let runs = group.flatMap(\.runs)
            var weights: [String: Int] = [:]
            for run in runs { weights[fontName(of: run.font), default: 0] += run.text.count }
            let font = weights.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? "Helvetica"
            let first = runs.max { $0.text.count < $1.text.count } ?? group[0].runs[0]
            let pitch = group.count > 1 ? (group[0].bounds.minY - group[group.count - 1].bounds.minY) / CGFloat(group.count - 1) : nil
            let style = TextStyle(fontName: font, fontSize: size, color: first.color,
                                  alignment: .left, lineHeight: pitch.map { max($0, size) })
            return ContentBlock(id: 0, kind: .text, bounds: bounds, text: text, style: style,
                                members: group.flatMap { $0.runs.map(\.leaf.path) })
        }
    }

    private static func fontName(of font: FPDF_FONT?) -> String {
        guard let font else { return "Helvetica" }
        func string(_ get: (UnsafeMutablePointer<CChar>?, Int) -> Int) -> String {
            let length = get(nil, 0)
            guard length > 1 else { return "" }
            var buffer = [CChar](repeating: 0, count: length)
            _ = get(&buffer, length)
            return String(cString: buffer)
        }
        let base = string { FPDFFont_GetBaseFontName(font, $0, $1) }
        let family = string { FPDFFont_GetFamilyName(font, $0, $1) }
        let flags = FPDFFont_GetFlags(font)
        var angle: Int32 = 0
        let italic = FPDFFont_GetItalicAngle(font, &angle) != 0 && angle != 0 || (flags & (1 << 6)) != 0
            || base.localizedCaseInsensitiveContains("italic") || base.localizedCaseInsensitiveContains("oblique")
        // Variable-font instances carry their weight in the name, e.g. "…_wght2BC0000" (700 in 16.16 fixed point).
        let namedWeight = base.range(of: #"_wght([0-9A-Fa-f]+)"#, options: .regularExpression)
            .flatMap { Int(base[$0].dropFirst(5), radix: 16) }.map { $0 >> 16 }
        let bold = (namedWeight ?? Int(FPDFFont_GetWeight(font))) >= 600 || (flags & (1 << 18)) != 0 || base.localizedCaseInsensitiveContains("bold")
        return matchingFontName(baseName: base, family: family, bold: bold, italic: italic,
                                serif: flags & (1 << 1) != 0, fixedPitch: flags & 1 != 0)
    }

    // MARK: Editing

    /// Opens `data`, runs `edit` on page `index`, regenerates the content stream and saves.
    private static func editing(_ data: Data, page index: Int, _ edit: (PDFiumDocument, FPDF_PAGE) -> Bool) -> Data? {
        guard let doc = PDFiumDocument(data: data) else { return nil }
        let ok = doc.withPage(index) { page -> Bool in
            guard edit(doc, page) else { return false }
            return FPDFPage_GenerateContent(page) != 0
        } ?? false
        return ok ? doc.save() : nil
    }

    private static func resolve(_ blocks: [ContentBlock], on page: FPDF_PAGE) -> [Leaf] {
        let paths = Set(blocks.flatMap(\.members))
        return leaves(of: page).filter { paths.contains($0.path) }
    }

    private static func detach(_ leaf: Leaf, from page: FPDF_PAGE) -> Bool {
        let removed = leaf.parent.map { FPDFFormObj_RemoveObject($0, leaf.object) } ?? FPDFPage_RemoveObject(page, leaf.object)
        guard removed != 0 else { return false }
        FPDFPageObj_Destroy(leaf.object)
        return true
    }

    /// Deletes blocks from the page.
    public static func remove(_ blocks: [ContentBlock], inPage index: Int = 0, of data: Data) -> Data? {
        editing(data, page: index) { _, page in
            let targets = resolve(blocks, on: page)
            return !targets.isEmpty && targets.allSatisfy { detach($0, from: page) }
        }
    }

    /// Moves and scales a block so its bounds become `newBounds`.
    public static func move(_ block: ContentBlock, to newBounds: CGRect, inPage index: Int = 0, of data: Data) -> Data? {
        let old = block.bounds
        guard old.width > 0, old.height > 0 else { return nil }
        let sx = newBounds.width / old.width, sy = newBounds.height / old.height
        // Page-space transform: scale about the old origin, then move to the new one.
        let t = CGAffineTransform(translationX: -old.minX, y: -old.minY)
            .concatenating(CGAffineTransform(scaleX: sx, y: sy))
            .concatenating(CGAffineTransform(translationX: newBounds.minX, y: newBounds.minY))
        return editing(data, page: index) { _, page in
            let targets = resolve([block], on: page)
            for leaf in targets {
                // Objects inside a form live in its space: conjugate the page transform into it.
                let local = leaf.toPage.concatenating(t).concatenating(leaf.toPage.inverted())
                var m = FS_MATRIX(a: Float(local.a), b: Float(local.b), c: Float(local.c), d: Float(local.d), e: Float(local.tx), f: Float(local.ty))
                FPDFPageObj_TransformF(leaf.object, &m)
                if let parent = leaf.parent { markDirty(parent) }
            }
            return !targets.isEmpty
        }
    }

    /// PDFium regenerates a form's stream only when the form itself changed; an identity transform marks it so.
    private static func markDirty(_ form: FPDF_PAGEOBJECT) {
        var identity = FS_MATRIX(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0)
        FPDFPageObj_TransformF(form, &identity)
    }

    /// Replaces a text block with `text` laid out in `style`, keeping its top-left corner and width.
    public static func replaceText(of block: ContentBlock, with text: String, style: TextStyle, width: CGFloat? = nil,
                                   inPage index: Int = 0, of data: Data) -> Data? {
        let topLeft = CGPoint(x: block.bounds.minX, y: block.bounds.maxY)
        return editing(data, page: index) { doc, page in
            let targets = resolve([block], on: page)
            guard !targets.isEmpty, targets.allSatisfy({ detach($0, from: page) }) else { return false }
            if text.isEmpty { return true }
            return insertText(text, style: style, topLeft: topLeft, width: width ?? block.bounds.width + 2, doc: doc, page: page)
        }
    }

    /// Adds new text with its top-left corner at `topLeft`. With no width, lines only break at newlines.
    public static func addText(_ text: String, style: TextStyle, at topLeft: CGPoint, width: CGFloat? = nil,
                               inPage index: Int = 0, of data: Data) -> Data? {
        editing(data, page: index) { doc, page in
            insertText(text, style: style, topLeft: topLeft, width: width, doc: doc, page: page)
        }
    }

    private static func insertText(_ text: String, style: TextStyle, topLeft: CGPoint, width: CGFloat?,
                                   doc: PDFiumDocument, page: FPDF_PAGE) -> Bool {
        let padding: CGFloat = 2
        guard let laid = textPDF(text, style: style, width: width, padding: padding),
              let source = PDFiumDocument(data: laid.data),
              let xobject = FPDF_NewXObjectFromPage(doc.handle, source.handle, 0)
        else { return false }
        defer { FPDF_CloseXObject(xobject) }
        guard let form = FPDF_NewFormObjectFromXObject(xobject) else { return false }
        var m = FS_MATRIX(a: 1, b: 0, c: 0, d: 1, e: Float(topLeft.x - padding), f: Float(topLeft.y - laid.size.height + padding))
        FPDFPageObj_TransformF(form, &m)
        FPDFPage_InsertObject(page, form)
        return true
    }

    /// Replaces an image, fitting the new one inside the old bounds without distorting it.
    public static func replaceImage(of block: ContentBlock, with image: CGImage, inPage index: Int = 0, of data: Data) -> Data? {
        editing(data, page: index) { doc, page in
            guard let leaf = resolve([block], on: page).first else { return false }
            guard detach(leaf, from: page) else { return false }
            return insertImage(image, in: aspectFit(image, in: block.bounds), doc: doc, page: page)
        }
    }

    /// Adds an image as page content (not an annotation) filling `rect`.
    public static func addImage(_ image: CGImage, in rect: CGRect, inPage index: Int = 0, of data: Data) -> Data? {
        editing(data, page: index) { doc, page in insertImage(image, in: rect, doc: doc, page: page) }
    }

    private static func insertImage(_ image: CGImage, in rect: CGRect, doc: PDFiumDocument, page: FPDF_PAGE) -> Bool {
        guard let object = FPDFPageObj_NewImageObj(doc.handle), let bitmap = bitmap(from: image) else { return false }
        defer { FPDFBitmap_Destroy(bitmap) }
        guard FPDFImageObj_SetBitmap(nil, 0, object, bitmap) != 0 else { FPDFPageObj_Destroy(object); return false }
        var m = FS_MATRIX(a: Float(rect.width), b: 0, c: 0, d: Float(rect.height), e: Float(rect.minX), f: Float(rect.minY))
        guard FPDFPageObj_SetMatrix(object, &m) != 0 else { FPDFPageObj_Destroy(object); return false }
        FPDFPage_InsertObject(page, object)
        return true
    }

    static func aspectFit(_ image: CGImage, in rect: CGRect) -> CGRect {
        let scale = min(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// An image block as it appears on the page (masks and filters applied).
    public static func image(of block: ContentBlock, inPage index: Int = 0, of data: Data) -> CGImage? {
        guard let doc = PDFiumDocument(data: data) else { return nil }
        return doc.withPage(index) { page -> CGImage? in
            guard let leaf = resolve([block], on: page).first,
                  let bitmap = FPDFImageObj_GetRenderedBitmap(doc.handle, page, leaf.object)
            else { return nil }
            defer { FPDFBitmap_Destroy(bitmap) }
            return cgImage(from: bitmap)
        } ?? nil
    }

    // MARK: Rendering

    /// Renders each page with its text removed, for exports that rebuild the text as editable boxes.
    /// The returned closure keeps the document open; call it from one thread.
    public static func textFreeRenderer(for data: Data, scale: CGFloat = 2) -> ((Int) -> CGImage?)? {
        guard let doc = PDFiumDocument(data: data) else { return nil }
        return { index in
            doc.withPage(index) { page -> CGImage? in
                for leaf in leaves(of: page).reversed() where leaf.type == FPDF_PAGEOBJ_TEXT {
                    if let parent = leaf.parent { markDirty(parent) }
                    _ = detach(leaf, from: page)
                }
                let width = Int((CGFloat(FPDF_GetPageWidthF(page)) * scale).rounded())
                let height = Int((CGFloat(FPDF_GetPageHeightF(page)) * scale).rounded())
                guard width > 0, height > 0, let bitmap = FPDFBitmap_Create(Int32(width), Int32(height), 1) else { return nil }
                defer { FPDFBitmap_Destroy(bitmap) }
                FPDFBitmap_FillRect(bitmap, 0, 0, Int32(width), Int32(height), 0xFFFF_FFFF)
                FPDF_RenderPageBitmap(bitmap, page, 0, 0, Int32(width), Int32(height), 0, FPDF_ANNOT)
                return cgImage(from: bitmap)
            } ?? nil
        }
    }
}
#else
extension ContentEditor {
    public static func blocks(inPage index: Int = 0, of data: Data) -> [ContentBlock] { [] }
    public static func remove(_ blocks: [ContentBlock], inPage index: Int = 0, of data: Data) -> Data? { nil }
    public static func move(_ block: ContentBlock, to newBounds: CGRect, inPage index: Int = 0, of data: Data) -> Data? { nil }
    public static func replaceText(of block: ContentBlock, with text: String, style: TextStyle, width: CGFloat? = nil,
                                   inPage index: Int = 0, of data: Data) -> Data? { nil }
    public static func addText(_ text: String, style: TextStyle, at topLeft: CGPoint, width: CGFloat? = nil,
                               inPage index: Int = 0, of data: Data) -> Data? { nil }
    public static func replaceImage(of block: ContentBlock, with image: CGImage, inPage index: Int = 0, of data: Data) -> Data? { nil }
    public static func addImage(_ image: CGImage, in rect: CGRect, inPage index: Int = 0, of data: Data) -> Data? { nil }
    public static func image(of block: ContentBlock, inPage index: Int = 0, of data: Data) -> CGImage? { nil }
    public static func textFreeRenderer(for data: Data, scale: CGFloat = 2) -> ((Int) -> CGImage?)? { nil }
}
#endif
