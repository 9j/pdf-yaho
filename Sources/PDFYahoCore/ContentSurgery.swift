import AppKit
import CoreGraphics

/// Removes or moves individual text and image drawing operators in a page's content stream, leaving every
/// other byte as it was. PDFium can only rewrite a whole stream, and in doing so drops kerning, character
/// spacing and shadings, so it is only trusted to add new content in a separate stream.
///
/// Works on the first page of a one-page file with a classic xref table, as PDFKit writes, and writes the
/// result as an incremental update with a new content stream.
enum ContentSurgery {
    enum Edit {
        case remove
        /// Draw the image with this extra page-space transform (images only).
        case transform(CGAffineTransform, imageMatrix: CGAffineTransform)
    }

    /// Text and image operators counted the way PDFium counts its text and image objects, to map one to the other.
    struct Census: Equatable {
        var text = 0
        var images = 0
    }

    static func census(of data: Data) -> Census? {
        guard let page = Page(data: data) else { return nil }
        var census = Census()
        page.walk { op, _ in
            switch op.kind {
            case .show: census.text += 1
            case .image: census.images += 1
            default: break
            }
        }
        return census
    }

    /// Applies edits keyed by the ordinal of the text operator (`text`) or image (`images`) among the page's own
    /// (top-level) objects. Returns nil when an edit cannot be made exactly.
    static func apply(text: [Int: Edit], images: [Int: Edit], to data: Data) -> Data? {
        guard let page = Page(data: data) else { return nil }
        var replacements: [(Range<Int>, String)] = []
        var failed = false
        page.walk { op, state in
            switch op.kind {
            case .show(let ordinal):
                guard text[ordinal] != nil else { return }
                guard let replacement = page.removal(of: op, state: state) else { failed = true; return }
                replacements.append((op.range, replacement))
            case .image(let ordinal):
                guard let edit = images[ordinal] else { return }
                let source = String(decoding: page.content[op.range], as: UTF8.self)
                switch edit {
                case .remove:
                    replacements.append((op.range, " "))
                case .transform(let t, let imageMatrix):
                    // `cm` premultiplies the CTM, so conjugate the page-space move by the image's own matrix.
                    let m = imageMatrix.concatenating(t).concatenating(imageMatrix.inverted())
                    let cm = [m.a, m.b, m.c, m.d, m.tx, m.ty].map { format($0) }.joined(separator: " ")
                    replacements.append((op.range, " q \(cm) cm \(source) Q "))
                }
            default:
                break
            }
        }
        guard !failed, replacements.count == text.count + images.count else { return nil }

        var content = page.content
        for (range, replacement) in replacements.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            content.replaceSubrange(range, with: Array(" \(replacement) ".utf8))
        }
        return page.writing(content: content)
    }

    static func format(_ value: CGFloat) -> String {
        let s = String(format: "%.5f", Double(value))
        var trimmed = s
        while trimmed.contains("."), trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed == "-0" ? "0" : trimmed
    }

    // MARK: - Page

    struct TextState {
        var font: String?
        var size: CGFloat = 0
        var charSpacing: CGFloat = 0
        var wordSpacing: CGFloat = 0
        var scale: CGFloat = 100
    }

    struct Op {
        enum Kind { case show(Int), image(Int), other }
        let name: String
        let operands: [Operand]
        let range: Range<Int>
        var kind: Kind
    }

    indirect enum Operand {
        case number(CGFloat), name(String), string([UInt8]), array([Operand]), other
    }

    struct FontInfo {
        var twoByte = false
        var widths: [Int: CGFloat] = [:]
        var defaultWidth: CGFloat?
        /// Glyph-space to text-space factor for widths (0.001, or a Type 3 font's matrix).
        var unit: CGFloat = 0.001
        var fallback: NSFont?

        func width(of code: Int) -> CGFloat? {
            if let w = widths[code] { return w }
            if let defaultWidth { return defaultWidth }
            guard let fallback, let scalar = UnicodeScalar(code) else { return nil }
            var glyph = CGGlyph()
            var char = UniChar(scalar.value & 0xFFFF)
            guard CTFontGetGlyphsForCharacters(fallback, &char, &glyph, 1) else { return nil }
            return fallback.advancement(forGlyph: NSGlyph(glyph)).width / fallback.pointSize * 1000
        }
    }

    final class Page {
        let bytes: [UInt8]
        let content: [UInt8]
        let fonts: [String: FontInfo]
        let imageXObjects: Set<String>
        private(set) var ops: [Op] = []

        init?(data: Data) {
            bytes = [UInt8](data)
            guard let provider = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(provider),
                  let page = doc.page(at: 1), let dict = page.dictionary
            else { return nil }
            var streams: [CGPDFStreamRef] = []
            var single: CGPDFStreamRef?
            var array: CGPDFArrayRef?
            if CGPDFDictionaryGetStream(dict, "Contents", &single), let single {
                streams = [single]
            } else if CGPDFDictionaryGetArray(dict, "Contents", &array), let array {
                for i in 0..<CGPDFArrayGetCount(array) {
                    var s: CGPDFStreamRef?
                    if CGPDFArrayGetStream(array, i, &s), let s { streams.append(s) }
                }
            }
            var content: [UInt8] = []
            for stream in streams {
                var format = CGPDFDataFormat.raw
                guard let data = CGPDFStreamCopyData(stream, &format), format == .raw else { return nil }
                content += [UInt8](data as Data) + [0x0A]
            }
            self.content = content
            var resources: CGPDFDictionaryRef?
            _ = CGPDFDictionaryGetDictionary(dict, "Resources", &resources)
            fonts = resources.map(Self.fonts(in:)) ?? [:]
            imageXObjects = resources.map(Self.images(in:)) ?? []
            var tokenizer = ContentTokenizer(content)
            ops = tokenizer.ops()
            var text = 0, images = 0
            for i in ops.indices {
                switch ops[i].name {
                case "Tj", "TJ", "'", "\"":
                    if ops[i].operands.contains(where: Self.hasGlyphs) { ops[i].kind = .show(text); text += 1 }
                case "Do":
                    if case .name(let n)? = ops[i].operands.last, imageXObjects.contains(n) { ops[i].kind = .image(images); images += 1 }
                case "BI":
                    ops[i].kind = .image(images); images += 1
                default: break
                }
            }
        }

        private static func hasGlyphs(_ operand: Operand) -> Bool {
            switch operand {
            case .string(let s): !s.isEmpty
            case .array(let items): items.contains(where: hasGlyphs)
            default: false
            }
        }

        /// Calls `body` with each operator and the text state in force when it runs.
        func walk(_ body: (Op, TextState) -> Void) {
            var state = TextState()
            var stack: [TextState] = []
            for op in ops {
                switch op.name {
                case "q": stack.append(state)
                case "Q": if let saved = stack.popLast() { state = saved }
                case "Tf":
                    if case .name(let n)? = op.operands.first { state.font = n }
                    if case .number(let s)? = op.operands.last { state.size = s }
                case "Tc": if case .number(let v)? = op.operands.last { state.charSpacing = v }
                case "Tw": if case .number(let v)? = op.operands.last { state.wordSpacing = v }
                case "Tz": if case .number(let v)? = op.operands.last { state.scale = v }
                case "\"":
                    if op.operands.count >= 3, case .number(let aw) = op.operands[0], case .number(let ac) = op.operands[1] {
                        state.wordSpacing = aw
                        state.charSpacing = ac
                    }
                default: break
                }
                body(op, state)
            }
        }

        /// What replaces a removed text operator so later text on the same line stays where it was.
        func removal(of op: Op, state: TextState) -> String? {
            var prefix = ""
            switch op.name {
            case "'": prefix = "T*"
            case "\"":
                if op.operands.count >= 3, case .number(let aw) = op.operands[0], case .number(let ac) = op.operands[1] {
                    prefix = "\(format(aw)) Tw \(format(ac)) Tc T*"
                }
            default: break
            }
            guard needsAdvance(after: op) else { return prefix }
            guard let advance = advance(of: op, state: state) else { return nil }
            let h = state.size * state.scale / 100
            guard h != 0 else { return prefix }
            return prefix + " [\(format(-advance / h * 1000))] TJ"
        }

        /// Whether a later operator on the same line relies on the text position this one leaves behind.
        private func needsAdvance(after op: Op) -> Bool {
            guard let index = ops.firstIndex(where: { $0.range == op.range }) else { return true }
            for next in ops[(index + 1)...] {
                switch next.name {
                case "Tj", "TJ": return true
                case "ET", "Td", "TD", "Tm", "T*", "'", "\"": return false
                default: continue
                }
            }
            return false
        }

        /// Horizontal advance of a text operator, in unscaled text space (PDF 32000 §9.4.4).
        private func advance(of op: Op, state: TextState) -> CGFloat? {
            guard let name = state.font, let font = fonts[name] else { return nil }
            var total: CGFloat = 0
            func add(_ string: [UInt8]) -> Bool {
                var i = 0
                while i < string.count {
                    let code: Int
                    if font.twoByte {
                        guard i + 1 < string.count else { return false }
                        code = Int(string[i]) << 8 | Int(string[i + 1]); i += 2
                    } else {
                        code = Int(string[i]); i += 1
                    }
                    guard let w = font.width(of: code) else { return false }
                    total += w * font.unit * state.size + state.charSpacing
                    if !font.twoByte, code == 32 { total += state.wordSpacing }
                }
                return true
            }
            for operand in op.operands {
                switch operand {
                case .string(let s): if !add(s) { return nil }
                case .array(let items):
                    for item in items {
                        switch item {
                        case .string(let s): if !add(s) { return nil }
                        case .number(let n): total -= n / 1000 * state.size
                        default: break
                        }
                    }
                default: break
                }
            }
            return total * state.scale / 100
        }

        // MARK: Resources

        private static func fonts(in resources: CGPDFDictionaryRef) -> [String: FontInfo] {
            var fontDict: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(resources, "Font", &fontDict), let fontDict else { return [:] }
            var result: [String: FontInfo] = [:]
            CGPDFDictionaryApplyBlock(fontDict, { key, object, _ in
                var font: CGPDFDictionaryRef?
                if CGPDFObjectGetValue(object, .dictionary, &font), let font {
                    result[String(cString: key)] = fontInfo(font)
                }
                return true
            }, nil)
            return result
        }

        private static func name(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
            var value: UnsafePointer<CChar>?
            return CGPDFDictionaryGetName(dict, key, &value) ? value.map { String(cString: $0) } : nil
        }

        private static func number(_ object: CGPDFObjectRef) -> CGFloat? {
            var real: CGPDFReal = 0
            if CGPDFObjectGetValue(object, .real, &real) { return real }
            var int: CGPDFInteger = 0
            if CGPDFObjectGetValue(object, .integer, &int) { return CGFloat(int) }
            return nil
        }

        private static func numbers(_ array: CGPDFArrayRef) -> [CGFloat?] {
            (0..<CGPDFArrayGetCount(array)).map { i in
                var object: CGPDFObjectRef?
                return CGPDFArrayGetObject(array, i, &object) ? object.flatMap(number) : nil
            }
        }

        private static func fontInfo(_ font: CGPDFDictionaryRef) -> FontInfo {
            var info = FontInfo()
            let subtype = name(font, "Subtype")
            if subtype == "Type0" {
                info.twoByte = true
                // Only Identity encodings map codes straight to CIDs; others need a CMap we do not parse.
                guard let encoding = name(font, "Encoding"), encoding.hasPrefix("Identity") else {
                    info.twoByte = true
                    return FontInfo(twoByte: true, widths: [:], defaultWidth: nil)
                }
                var descendants: CGPDFArrayRef?
                var cid: CGPDFDictionaryRef?
                guard CGPDFDictionaryGetArray(font, "DescendantFonts", &descendants), let descendants,
                      CGPDFArrayGetDictionary(descendants, 0, &cid), let cid
                else { return info }
                var dw: CGPDFInteger = 1000
                _ = CGPDFDictionaryGetInteger(cid, "DW", &dw)
                info.defaultWidth = CGFloat(dw)
                var w: CGPDFArrayRef?
                if CGPDFDictionaryGetArray(cid, "W", &w), let w {
                    var i = 0
                    let count = CGPDFArrayGetCount(w)
                    while i < count {
                        var first: CGPDFInteger = 0
                        guard CGPDFArrayGetInteger(w, i, &first) else { break }
                        var list: CGPDFArrayRef?
                        if i + 1 < count, CGPDFArrayGetArray(w, i + 1, &list), let list {
                            for (k, width) in numbers(list).enumerated() { if let width { info.widths[Int(first) + k] = width } }
                            i += 2
                        } else if i + 2 < count {
                            var last: CGPDFInteger = 0
                            var object: CGPDFObjectRef?
                            guard CGPDFArrayGetInteger(w, i + 1, &last), CGPDFArrayGetObject(w, i + 2, &object),
                                  let width = object.flatMap(number), last >= first, last - first < 70_000
                            else { break }
                            for code in Int(first)...Int(last) { info.widths[code] = width }
                            i += 3
                        } else {
                            break
                        }
                    }
                }
                return info
            }
            if subtype == "Type3" {
                var matrix: CGPDFArrayRef?
                if CGPDFDictionaryGetArray(font, "FontMatrix", &matrix), let matrix, let a = numbers(matrix).first ?? nil { info.unit = a }
            }
            var first: CGPDFInteger = 0
            var widths: CGPDFArrayRef?
            if CGPDFDictionaryGetInteger(font, "FirstChar", &first), CGPDFDictionaryGetArray(font, "Widths", &widths), let widths {
                for (k, width) in numbers(widths).enumerated() { if let width { info.widths[Int(first) + k] = width } }
                var descriptor: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(font, "FontDescriptor", &descriptor), let descriptor {
                    var missing: CGPDFReal = 0
                    if CGPDFDictionaryGetNumber(descriptor, "MissingWidth", &missing) { info.defaultWidth = missing }
                }
            } else if let base = name(font, "BaseFont") {
                // The standard 14 fonts may come without widths; measure the matching installed font.
                let mapped = ["Helvetica": "Helvetica", "Times": "Times-Roman", "Courier": "Courier", "Symbol": "Symbol"]
                    .first { base.hasPrefix($0.key) }?.value ?? base
                info.fallback = NSFont(name: base, size: 1000) ?? NSFont(name: mapped, size: 1000)
            }
            return info
        }

        private static func images(in resources: CGPDFDictionaryRef) -> Set<String> {
            var xobjects: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects else { return [] }
            var result: Set<String> = []
            CGPDFDictionaryApplyBlock(xobjects, { key, object, _ in
                var stream: CGPDFStreamRef?
                if CGPDFObjectGetValue(object, .stream, &stream), let stream, let dict = CGPDFStreamGetDictionary(stream),
                   name(dict, "Subtype") == "Image" {
                    result.insert(String(cString: key))
                }
                return true
            }, nil)
            return result
        }

        // MARK: Writing

        /// The file with the page's contents replaced by `content`, as an incremental update.
        func writing(content: [UInt8]) -> Data? {
            guard let startxref = PageLabels.lastStartXref(in: bytes),
                  let trailerStart = PageLabels.find(Array("trailer".utf8), in: bytes, from: startxref, backwards: false),
                  let trailer = PageLabels.dictionary(in: bytes, at: trailerStart + 7)
            else { return nil }
            let trailerText = PageLabels.latin1(bytes[trailer])
            guard !trailerText.contains("/Encrypt"),
                  let size = PageLabels.firstMatch(#"/Size\s+(\d+)"#, in: trailerText)?.first.flatMap({ Int($0) }),
                  let root = reference("Root", in: trailerText),
                  let catalog = PageLabels.object(root.0, root.1, in: bytes),
                  let pagesRef = reference("Pages", in: PageLabels.latin1(bytes[catalog])),
                  let pages = PageLabels.object(pagesRef.0, pagesRef.1, in: bytes),
                  let kids = PageLabels.firstMatch(#"/Kids\s*\[\s*(\d+)\s+(\d+)\s+R"#, in: PageLabels.latin1(bytes[pages])),
                  let pageNumber = Int(kids[0]), let pageGeneration = Int(kids[1]),
                  let pageDict = PageLabels.object(pageNumber, pageGeneration, in: bytes)
            else { return nil }

            let streamNumber = size
            var update: [UInt8] = []
            var offsets: [(Int, Int, Int)] = []  // number, generation, offset
            func emit(_ text: String) { update += Array(text.utf8) }
            emit("\n")
            offsets.append((streamNumber, 0, bytes.count + update.count))
            emit("\(streamNumber) 0 obj\n<< /Length \(content.count) >>\nstream\n")
            update += content
            emit("\nendstream\nendobj\n")
            let entries = PageLabels.removingKey("Contents", from: PageLabels.latin1(bytes[pageDict]))
            offsets.append((pageNumber, pageGeneration, bytes.count + update.count))
            guard let pageObject = "\(pageNumber) \(pageGeneration) obj\n<< \(entries) /Contents \(streamNumber) 0 R >>\nendobj\n"
                .data(using: .isoLatin1)
            else { return nil }
            update += [UInt8](pageObject)
            let xref = bytes.count + update.count
            emit("xref\n")
            for (number, generation, offset) in offsets.sorted(by: { $0.0 < $1.0 }) {
                emit("\(number) 1\n" + String(format: "%010d %05d n \n", offset, generation))
            }
            var newTrailer = PageLabels.removingKey("Prev", from: trailerText)
            newTrailer = PageLabels.removingKey("XRefStm", from: newTrailer)
            newTrailer = PageLabels.removingKey("Size", from: newTrailer)
            guard let tail = "trailer\n<< \(newTrailer) /Size \(streamNumber + 1) /Prev \(startxref) >>\nstartxref\n\(xref)\n%%EOF\n"
                .data(using: .isoLatin1)
            else { return nil }
            return Data(bytes + update + [UInt8](tail))
        }

        private func reference(_ key: String, in dict: String) -> (Int, Int)? {
            guard let m = PageLabels.firstMatch("/\(key)\\s+(\\d+)\\s+(\\d+)\\s+R", in: dict), let n = Int(m[0]), let g = Int(m[1]) else { return nil }
            return (n, g)
        }
    }
}

/// Splits a content stream into operators with their operands and byte ranges.
struct ContentTokenizer {
    private let bytes: [UInt8]
    private var i = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    private static func isWhite(_ c: UInt8) -> Bool { c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x0C || c == 0x00 }
    private static func isDelimiter(_ c: UInt8) -> Bool { [0x28, 0x29, 0x3C, 0x3E, 0x5B, 0x5D, 0x7B, 0x7D, 0x2F, 0x25].contains(c) }

    mutating func ops() -> [ContentSurgery.Op] {
        var result: [ContentSurgery.Op] = []
        var operands: [ContentSurgery.Operand] = []
        var start: Int?
        while true {
            skipWhite()
            guard i < bytes.count else { break }
            let tokenStart = i
            if let operand = operand() {
                if start == nil { start = tokenStart }
                operands.append(operand)
                continue
            }
            // An operator: a run of regular characters.
            while i < bytes.count, !Self.isWhite(bytes[i]), !Self.isDelimiter(bytes[i]) { i += 1 }
            if i == tokenStart { i += 1; continue }  // stray delimiter
            let name = String(decoding: bytes[tokenStart..<i], as: UTF8.self)
            if name == "BI" { skipInlineImage() }
            result.append(.init(name: name, operands: operands, range: (start ?? tokenStart)..<i, kind: .other))
            operands = []
            start = nil
        }
        return result
    }

    private mutating func skipWhite() {
        while i < bytes.count {
            if Self.isWhite(bytes[i]) { i += 1 } else if bytes[i] == 0x25 {
                while i < bytes.count, bytes[i] != 0x0A, bytes[i] != 0x0D { i += 1 }
            } else { return }
        }
    }

    /// Skips an inline image's dictionary and data, through `EI`.
    private mutating func skipInlineImage() {
        while i + 1 < bytes.count {
            if bytes[i] == 0x49, bytes[i + 1] == 0x44, i > 0, Self.isWhite(bytes[i - 1]),
               i + 2 >= bytes.count || Self.isWhite(bytes[i + 2]) {
                i += 3
                break
            }
            i += 1
        }
        while i + 1 < bytes.count {
            if bytes[i] == 0x45, bytes[i + 1] == 0x49, Self.isWhite(bytes[i - 1]),
               i + 2 >= bytes.count || Self.isWhite(bytes[i + 2]) {
                i += 2
                return
            }
            i += 1
        }
        i = bytes.count
    }

    private mutating func operand() -> ContentSurgery.Operand? {
        let c = bytes[i]
        switch c {
        case 0x2F:  // name
            i += 1
            let s = i
            while i < bytes.count, !Self.isWhite(bytes[i]), !Self.isDelimiter(bytes[i]) { i += 1 }
            return .name(decodeName(bytes[s..<i]))
        case 0x28:
            return .string(literal())
        case 0x3C:
            if i + 1 < bytes.count, bytes[i + 1] == 0x3C { return dictionary() }
            return .string(hex())
        case 0x5B:
            i += 1
            var items: [ContentSurgery.Operand] = []
            while true {
                skipWhite()
                guard i < bytes.count else { break }
                if bytes[i] == 0x5D { i += 1; break }
                if let item = operand() { items.append(item) } else {
                    // Keywords inside arrays (true, false, null) are skipped.
                    while i < bytes.count, !Self.isWhite(bytes[i]), !Self.isDelimiter(bytes[i]) { i += 1 }
                    if i < bytes.count, bytes[i] != 0x5D, Self.isDelimiter(bytes[i]), bytes[i] != 0x5B, bytes[i] != 0x28, bytes[i] != 0x3C, bytes[i] != 0x2F { i += 1 }
                }
            }
            return .array(items)
        case 0x2B, 0x2D, 0x2E, 0x30...0x39:
            let s = i
            i += 1
            while i < bytes.count, bytes[i] == 0x2E || (0x30...0x39).contains(bytes[i]) { i += 1 }
            return .number(CGFloat(Double(String(decoding: bytes[s..<i], as: UTF8.self)) ?? 0))
        case 0x74, 0x66, 0x6E:  // true, false, null used as operands
            for word in ["true", "false", "null"] where bytes[i...].starts(with: word.utf8) {
                let end = i + word.count
                if end >= bytes.count || Self.isWhite(bytes[end]) || Self.isDelimiter(bytes[end]) { i = end; return .other }
            }
            return nil
        default:
            return nil
        }
    }

    private func decodeName(_ raw: ArraySlice<UInt8>) -> String {
        var out: [UInt8] = []
        var k = raw.startIndex
        while k < raw.endIndex {
            if raw[k] == 0x23, k + 2 < raw.endIndex, let v = UInt8(String(decoding: raw[(k + 1)...(k + 2)], as: UTF8.self), radix: 16) {
                out.append(v); k += 3
            } else { out.append(raw[k]); k += 1 }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private mutating func literal() -> [UInt8] {
        var out: [UInt8] = []
        var depth = 0
        i += 1
        while i < bytes.count {
            let c = bytes[i]
            if c == 0x5C, i + 1 < bytes.count {
                i += 1
                let e = bytes[i]
                switch e {
                case 0x6E: out.append(0x0A)
                case 0x72: out.append(0x0D)
                case 0x74: out.append(0x09)
                case 0x62: out.append(0x08)
                case 0x66: out.append(0x0C)
                case 0x0D: if i + 1 < bytes.count, bytes[i + 1] == 0x0A { i += 1 }
                case 0x0A: break
                case 0x30...0x37:
                    var v = 0, n = 0
                    while n < 3, i < bytes.count, (0x30...0x37).contains(bytes[i]) { v = v * 8 + Int(bytes[i] - 0x30); i += 1; n += 1 }
                    out.append(UInt8(truncatingIfNeeded: v))
                    continue
                default: out.append(e)
                }
                i += 1
                continue
            }
            if c == 0x28 { depth += 1 } else if c == 0x29 {
                if depth == 0 { i += 1; return out }
                depth -= 1
            }
            out.append(c)
            i += 1
        }
        return out
    }

    private mutating func hex() -> [UInt8] {
        i += 1
        var digits: [UInt8] = []
        while i < bytes.count, bytes[i] != 0x3E {
            if !Self.isWhite(bytes[i]) { digits.append(bytes[i]) }
            i += 1
        }
        i += 1
        if digits.count % 2 == 1 { digits.append(0x30) }
        return stride(from: 0, to: digits.count, by: 2).compactMap { UInt8(String(decoding: digits[$0...$0 + 1], as: UTF8.self), radix: 16) }
    }

    private mutating func dictionary() -> ContentSurgery.Operand {
        var depth = 0
        while i < bytes.count {
            if bytes[i] == 0x28 { _ = literal(); continue }
            if bytes[i] == 0x3C, i + 1 < bytes.count, bytes[i + 1] == 0x3C { depth += 1; i += 2; continue }
            if bytes[i] == 0x3E, i + 1 < bytes.count, bytes[i + 1] == 0x3E { depth -= 1; i += 2; if depth == 0 { break }; continue }
            i += 1
        }
        return .other
    }
}
