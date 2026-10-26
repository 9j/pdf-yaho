import CommonCrypto
import CryptoKit
import Foundation
import PDFKit

/// One run of page labels (PDF 32000 §12.4.2): from `startPage` on, pages are numbered in `style`
/// starting at `firstNumber`, each label preceded by `prefix`.
public struct PageLabelRange: Equatable, Hashable, Sendable {
    public enum Style: String, CaseIterable, Sendable {
        case decimal = "D", lowerRoman = "r", upperRoman = "R", lowerLetters = "a", upperLetters = "A", none = ""

        public var title: String {
            switch self {
            case .decimal: "1, 2, 3"
            case .lowerRoman: "i, ii, iii"
            case .upperRoman: "I, II, III"
            case .lowerLetters: "a, b, c"
            case .upperLetters: "A, B, C"
            case .none: "Prefix only"
            }
        }
    }

    public var startPage: Int
    public var style: Style
    public var prefix: String
    public var firstNumber: Int

    public init(startPage: Int, style: Style = .decimal, prefix: String = "", firstNumber: Int = 1) {
        self.startPage = startPage
        self.style = style
        self.prefix = prefix
        self.firstNumber = max(1, firstNumber)
    }
}

/// Reads page labels with CoreGraphics and writes them as an incremental update, since PDFKit has no API for them.
public enum PageLabels {
    /// The label of `page` under `ranges`, or nil when no range covers it.
    public static func label(forPage page: Int, in ranges: [PageLabelRange]) -> String? {
        guard let range = ranges.filter({ $0.startPage <= page }).max(by: { $0.startPage < $1.startPage }) else { return nil }
        let n = range.firstNumber + page - range.startPage
        return range.prefix + format(n, range.style)
    }

    static func format(_ n: Int, _ style: PageLabelRange.Style) -> String {
        switch style {
        case .decimal: String(n)
        case .lowerRoman: roman(n).lowercased()
        case .upperRoman: roman(n)
        case .lowerLetters: letters(n).lowercased()
        case .upperLetters: letters(n)
        case .none: ""
        }
    }

    static func roman(_ n: Int) -> String {
        var n = n, out = ""
        for (value, numeral) in [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                 (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")] {
            while n >= value { out += numeral; n -= value }
        }
        return out
    }

    /// A..Z, then AA..ZZ, AAA.. as the PDF spec defines.
    static func letters(_ n: Int) -> String {
        guard n > 0 else { return "" }
        let letter = Character(UnicodeScalar(UInt8(65 + (n - 1) % 26)))
        return String(repeating: letter, count: (n - 1) / 26 + 1)
    }

    /// The document's label ranges, sorted by start page; empty when it has none.
    public static func read(from doc: PDFDocument) -> [PageLabelRange] {
        guard let catalog = doc.documentRef?.catalog else { return [] }
        var tree: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "PageLabels", &tree), let tree else { return [] }
        var ranges: [PageLabelRange] = []
        collect(tree, into: &ranges, depth: 0)
        return ranges.sorted { $0.startPage < $1.startPage }
    }

    private static func collect(_ node: CGPDFDictionaryRef, into ranges: inout [PageLabelRange], depth: Int) {
        guard depth < 16 else { return }
        var nums: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Nums", &nums), let nums {
            let count = CGPDFArrayGetCount(nums)
            var i = 0
            while i + 1 < count {
                var key: CGPDFInteger = 0
                var entry: CGPDFDictionaryRef?
                if CGPDFArrayGetInteger(nums, i, &key), CGPDFArrayGetDictionary(nums, i + 1, &entry), let entry {
                    ranges.append(range(from: entry, start: key))
                }
                i += 2
            }
        }
        var kids: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Kids", &kids), let kids {
            for i in 0..<CGPDFArrayGetCount(kids) {
                var kid: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(kids, i, &kid), let kid { collect(kid, into: &ranges, depth: depth + 1) }
            }
        }
    }

    private static func range(from dict: CGPDFDictionaryRef, start: Int) -> PageLabelRange {
        var styleName: UnsafePointer<CChar>?
        let style = CGPDFDictionaryGetName(dict, "S", &styleName) && styleName != nil
            ? PageLabelRange.Style(rawValue: String(cString: styleName!)) ?? .decimal : .none
        var prefix = ""
        var string: CGPDFStringRef?
        if CGPDFDictionaryGetString(dict, "P", &string), let string, let text = CGPDFStringCopyTextString(string) {
            prefix = text as String
        }
        var first: CGPDFInteger = 1
        _ = CGPDFDictionaryGetInteger(dict, "St", &first)
        return PageLabelRange(startPage: start, style: style, prefix: prefix, firstNumber: first)
    }

    /// The `/PageLabels` number tree for `ranges` as PDF source.
    static func numberTree(_ ranges: [PageLabelRange], string: (String) -> String = pdfString) -> String {
        let entries = ranges.sorted { $0.startPage < $1.startPage }.map { r -> String in
            var dict = "<< /Type /PageLabel"
            if r.style != .none { dict += " /S /\(r.style.rawValue)" }
            if !r.prefix.isEmpty { dict += " /P \(string(r.prefix))" }
            if r.firstNumber != 1 { dict += " /St \(r.firstNumber)" }
            return "\(r.startPage) \(dict) >>"
        }
        return "<< /Nums [ \(entries.joined(separator: " ")) ] >>"
    }

    /// A literal string for ASCII text, otherwise UTF-16BE hex with a byte-order mark.
    static func pdfString(_ s: String) -> String {
        if s.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F }) {
            let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
            return "(\(escaped))"
        }
        return "<FEFF" + s.utf16.map { String(format: "%04X", $0) }.joined() + ">"
    }

    /// Appends an incremental update to `data` that replaces the catalog with one carrying `ranges`
    /// (or no labels when `ranges` is empty). Needs a classic xref table, as PDFKit writes; encrypted
    /// files (RC4 or AES-128, PDFKit's default) need the open password, empty when there is none.
    public static func apply(_ ranges: [PageLabelRange], to data: Data, password: String = "") -> Data? {
        let bytes = [UInt8](data)
        guard let startxref = lastStartXref(in: bytes),
              let trailerStart = find(Array("trailer".utf8), in: bytes, from: startxref, backwards: false),
              let trailer = dictionary(in: bytes, at: trailerStart + 7)
        else { return nil }
        let trailerText = latin1(bytes[trailer])
        guard let root = firstMatch(#"/Root\s+(\d+)\s+(\d+)\s+R"#, in: trailerText),
              let objectNumber = Int(root[0]), let generation = Int(root[1]),
              let catalog = object(objectNumber, generation, in: bytes)
        else { return nil }

        var encrypt: ((String, Int, Int) -> String)?
        if let ref = firstMatch(#"/Encrypt\s+(\d+)\s+(\d+)\s+R"#, in: trailerText) {
            guard let n = Int(ref[0]), let g = Int(ref[1]), let dict = object(n, g, in: bytes),
                  let id = value(of: "ID", in: trailerText),
                  let security = StandardSecurity(encryptDictionary: latin1(bytes[dict]), firstID: firstString(in: id), password: password)
            else { return nil }
            encrypt = security.encryptedString
        }

        var entries = removingKey("PageLabels", from: latin1(bytes[catalog]))
        if !ranges.isEmpty {
            entries += " /PageLabels \(numberTree(ranges) { text in encrypt?(text, objectNumber, generation) ?? pdfString(text) })"
        }
        let object = "\n\(objectNumber) \(generation) obj\n<< \(entries) >>\nendobj\n"
        let objectOffset = bytes.count + 1  // after the leading newline
        let xrefOffset = bytes.count + object.utf8.count

        var newTrailer = removingKey("Prev", from: trailerText)
        newTrailer = removingKey("XRefStm", from: newTrailer)
        let update = object
            + "xref\n\(objectNumber) 1\n" + String(format: "%010d %05d n \n", objectOffset, generation)
            + "trailer\n<< \(newTrailer) /Prev \(startxref) >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
        guard let tail = update.data(using: .isoLatin1) else { return nil }
        var out = data
        out.append(tail)
        return out
    }

    /// The byte range of the dictionary of the last definition of object `n g`.
    static func object(_ n: Int, _ g: Int, in bytes: [UInt8]) -> Range<Int>? {
        guard let header = find(Array("\(n) \(g) obj".utf8), in: bytes, from: bytes.count, backwards: true) else { return nil }
        return dictionary(in: bytes, at: header)
    }

    /// PDF syntax is bytes; Latin-1 maps them one-to-one so binary strings survive the round trip.
    static func latin1(_ bytes: ArraySlice<UInt8>) -> String { String(bytes.map { Character(UnicodeScalar($0)) }) }

    // MARK: - Minimal PDF lexing

    static func lastStartXref(in bytes: [UInt8]) -> Int? {
        guard let at = find(Array("startxref".utf8), in: bytes, from: bytes.count, backwards: true) else { return nil }
        var i = at + 9
        while i < bytes.count, isWhitespace(bytes[i]) { i += 1 }
        var n = 0, digits = 0
        while i < bytes.count, bytes[i] >= 48, bytes[i] <= 57 { n = n * 10 + Int(bytes[i] - 48); i += 1; digits += 1 }
        return digits > 0 ? n : nil
    }

    static func find(_ needle: [UInt8], in bytes: [UInt8], from: Int, backwards: Bool) -> Int? {
        guard !needle.isEmpty, bytes.count >= needle.count else { return nil }
        let last = bytes.count - needle.count
        var i = backwards ? min(from, last) : max(0, from)
        while i >= 0 && i <= last {
            if bytes[i] == needle[0], bytes[i..<(i + needle.count)].elementsEqual(needle),
               // Object headers must start a token, e.g. not match "12 0 obj" inside "112 0 obj".
               !backwards || i == 0 || isWhitespace(bytes[i - 1]) {
                return i
            }
            i += backwards ? -1 : 1
        }
        return nil
    }

    /// The byte range of the first `<< … >>` at or after `start`, delimiters included.
    static func dictionary(in bytes: [UInt8], at start: Int) -> Range<Int>? {
        var i = start
        while i + 1 < bytes.count, !(bytes[i] == 0x3C && bytes[i + 1] == 0x3C) { i += 1 }
        guard i + 1 < bytes.count else { return nil }
        let open = i
        var depth = 0
        while i < bytes.count {
            let c = bytes[i]
            if c == 0x28 {  // literal string, with nesting and escapes
                var nest = 0
                while i < bytes.count {
                    if bytes[i] == 0x5C { i += 2; continue }
                    if bytes[i] == 0x28 { nest += 1 } else if bytes[i] == 0x29 { nest -= 1; if nest == 0 { break } }
                    i += 1
                }
            } else if c == 0x25 {  // comment
                while i < bytes.count, bytes[i] != 0x0A, bytes[i] != 0x0D { i += 1 }
            } else if c == 0x3C, i + 1 < bytes.count, bytes[i + 1] == 0x3C {
                depth += 1; i += 1
            } else if c == 0x3E, i + 1 < bytes.count, bytes[i + 1] == 0x3E {
                depth -= 1; i += 1
                if depth == 0 { return open..<(i + 1) }
            } else if c == 0x3C {  // hex string
                while i < bytes.count, bytes[i] != 0x3E { i += 1 }
            }
            i += 1
        }
        return nil
    }

    private static func isWhitespace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x0C || c == 0x00 }

    static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: text).map { String(text[$0]) } }
    }

    /// The dictionary's entries (without `<<`/`>>`) minus `key` and its value.
    static func removingKey(_ key: String, from dictionary: String) -> String {
        let body = entries(of: dictionary)
        guard let (start, end) = keyRange(key, in: body) else { return body.trimmingCharacters(in: .whitespacesAndNewlines) }
        let chars = Array(body.unicodeScalars)
        return (String(String.UnicodeScalarView(chars[..<start])) + " " + String(String.UnicodeScalarView(chars[end...])))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The source text of `key`'s value in a dictionary.
    static func value(of key: String, in dictionary: String) -> String? {
        let body = entries(of: dictionary)
        guard let (start, end) = keyRange(key, in: body) else { return nil }
        let chars = Array(body.unicodeScalars)
        return String(String.UnicodeScalarView(chars[(start + key.count + 1)..<end])).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func entries(of dictionary: String) -> String {
        let body = dictionary.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.hasPrefix("<<") && body.hasSuffix(">>") ? String(body.dropFirst(2).dropLast(2)) : body
    }

    /// Scalar offsets of `/key value` at the top level of a dictionary body (Latin-1 text, so scalars are bytes).
    private static func keyRange(_ key: String, in body: String) -> (Int, Int)? {
        let chars = body.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }
        let needle = Array("/\(key)".utf8)
        var i = 0, depth = 0
        while i < chars.count {
            if chars[i] == 0x28 { i = skipString(chars, i); continue }
            if chars[i] == 0x3C, i + 1 < chars.count, chars[i + 1] == 0x3C { depth += 1; i += 2; continue }
            if chars[i] == 0x3E, i + 1 < chars.count, chars[i + 1] == 0x3E { depth -= 1; i += 2; continue }
            if chars[i] == 0x3C, depth == 0 { while i < chars.count, chars[i] != 0x3E { i += 1 }; i += 1; continue }
            if depth == 0, chars[i] == 0x2F, i + needle.count <= chars.count, chars[i..<(i + needle.count)].elementsEqual(needle),
               i + needle.count == chars.count || !isNameChar(chars[i + needle.count]) {
                return (i, skipValue(chars, i + needle.count))
            }
            i += 1
        }
        return nil
    }

    /// The bytes of the first string (literal or hex) in `source`, e.g. the first element of `/ID [<…> <…>]`.
    static func firstString(in source: String) -> [UInt8] {
        let chars = source.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }
        guard let start = chars.firstIndex(where: { $0 == 0x28 || $0 == 0x3C }) else { return [] }
        if chars[start] == 0x3C {
            let hex = chars[(start + 1)...].prefix { $0 != 0x3E }.filter { !isWhitespace($0) }
            var out: [UInt8] = [], i = hex.startIndex
            while i < hex.endIndex {
                let pair = String(decoding: hex[i..<min(i + 2, hex.endIndex)], as: UTF8.self)
                out.append(UInt8((pair.count == 1 ? pair + "0" : pair), radix: 16) ?? 0)
                i += 2
            }
            return out
        }
        var out: [UInt8] = [], i = start + 1, nest = 1
        while i < chars.count {
            let c = chars[i]
            if c == 0x5C, i + 1 < chars.count {
                i += 1
                switch chars[i] {
                case 0x6E: out.append(0x0A)
                case 0x72: out.append(0x0D)
                case 0x74: out.append(0x09)
                case 0x62: out.append(0x08)
                case 0x66: out.append(0x0C)
                case 0x0D, 0x0A: if chars[i] == 0x0D, i + 1 < chars.count, chars[i + 1] == 0x0A { i += 1 }
                case 0x30...0x37:
                    var v = 0, n = 0
                    while n < 3, i < chars.count, (0x30...0x37).contains(chars[i]) { v = v * 8 + Int(chars[i] - 0x30); i += 1; n += 1 }
                    out.append(UInt8(truncatingIfNeeded: v)); continue
                default: out.append(chars[i])
                }
                i += 1; continue
            }
            if c == 0x28 { nest += 1 } else if c == 0x29 { nest -= 1; if nest == 0 { break } }
            out.append(c); i += 1
        }
        return out
    }

    private static func isNameChar(_ c: UInt8) -> Bool {
        !(isWhitespace(c) || [0x2F, 0x3C, 0x3E, 0x5B, 0x5D, 0x28, 0x29, 0x7B, 0x7D, 0x25].contains(c))
    }

    private static func skipString(_ chars: [UInt8], _ start: Int) -> Int {
        var i = start, nest = 0
        while i < chars.count {
            if chars[i] == 0x5C { i += 2; continue }
            if chars[i] == 0x28 { nest += 1 } else if chars[i] == 0x29 { nest -= 1; if nest == 0 { return i + 1 } }
            i += 1
        }
        return i
    }

    /// The index just past one PDF value (an `N G R` reference counts as one value).
    private static func skipValue(_ chars: [UInt8], _ start: Int) -> Int {
        var i = start
        while i < chars.count, isWhitespace(chars[i]) { i += 1 }
        guard i < chars.count else { return i }
        switch chars[i] {
        case 0x28: return skipString(chars, i)
        case 0x3C where i + 1 < chars.count && chars[i + 1] == 0x3C, 0x5B:
            var depth = 0
            while i < chars.count {
                let c = chars[i], next = i + 1 < chars.count ? chars[i + 1] : 0
                if c == 0x28 { i = skipString(chars, i); continue }
                if c == 0x3C && next == 0x3C { depth += 1; i += 2; continue }
                if c == 0x3E && next == 0x3E { depth -= 1; i += 2; if depth == 0 { return i }; continue }
                if c == 0x3C { while i < chars.count, chars[i] != 0x3E { i += 1 }; i += 1; continue }
                if c == 0x5B { depth += 1 } else if c == 0x5D { depth -= 1; if depth == 0 { return i + 1 } }
                i += 1
            }
            return i
        case 0x3C:
            while i < chars.count, chars[i] != 0x3E { i += 1 }
            return i + 1
        default:
            // A name, number or keyword; a following "G R" makes it a reference.
            i += 1
            while i < chars.count, isNameChar(chars[i]) { i += 1 }
            let save = i
            let rest = String(decoding: chars[i..<min(chars.count, i + 24)], as: UTF8.self)
            if let m = try? NSRegularExpression(pattern: #"^\s+\d+\s+R(?![A-Za-z0-9])"#)
                .firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)) {
                return save + m.range.length
            }
            return save
        }
    }
}

/// The standard security handler's string encryption (PDF 32000 §7.6.3, algorithms 1 and 2) for revisions 2–4.
struct StandardSecurity {
    private let key: [UInt8]
    private let aes: Bool

    private static let padding: [UInt8] = [0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, 0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
                                           0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80, 0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A]

    init?(encryptDictionary dict: String, firstID: [UInt8], password: String) {
        guard PageLabels.value(of: "Filter", in: dict) == "/Standard",
              let r = PageLabels.value(of: "R", in: dict).flatMap(Int.init), (2...4).contains(r),
              let o = PageLabels.value(of: "O", in: dict).map(PageLabels.firstString), o.count >= 32,
              let p = PageLabels.value(of: "P", in: dict).flatMap(Int64.init)
        else { return nil }
        let v = PageLabels.value(of: "V", in: dict).flatMap(Int.init) ?? 0
        let length = r == 2 ? 5 : (PageLabels.value(of: "Length", in: dict).flatMap(Int.init) ?? 40) / 8
        aes = v == 4 && dict.contains("/AESV2")
        if v == 4, !aes, !dict.contains("/V2") { return nil }

        var input = Array(Array(password.data(using: .isoLatin1) ?? Data()).prefix(32))
        input += Self.padding.prefix(32 - input.count)
        input += o.prefix(32)
        let p32 = UInt32(truncatingIfNeeded: p)
        input += [UInt8(p32 & 0xFF), UInt8((p32 >> 8) & 0xFF), UInt8((p32 >> 16) & 0xFF), UInt8(p32 >> 24)]
        input += firstID
        if r >= 4, PageLabels.value(of: "EncryptMetadata", in: dict) == "false" { input += [0xFF, 0xFF, 0xFF, 0xFF] }
        var hash = Array(Insecure.MD5.hash(data: input))
        if r >= 3 { for _ in 0..<50 { hash = Array(Insecure.MD5.hash(data: hash.prefix(length))) } }
        key = Array(hash.prefix(length))
    }

    /// `text` as an encrypted hex string belonging to object `n g`.
    func encryptedString(_ text: String, _ n: Int, _ g: Int) -> String {
        let plain: [UInt8] = text.unicodeScalars.allSatisfy({ $0.value < 0x80 })
            ? Array(text.utf8) : [0xFE, 0xFF] + text.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        var seed = key + [UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8(g & 0xFF), UInt8((g >> 8) & 0xFF)]
        if aes { seed += Array("sAlT".utf8) }
        let objectKey = Array(Insecure.MD5.hash(data: seed).prefix(min(key.count + 5, 16)))
        let cipher = aes ? Self.aesCBC(plain, key: objectKey) : Self.rc4(plain, key: objectKey)
        return "<" + cipher.map { String(format: "%02X", $0) }.joined() + ">"
    }

    private static func aesCBC(_ plain: [UInt8], key: [UInt8]) -> [UInt8] {
        var iv = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        _ = SecRandomCopyBytes(kSecRandomDefault, iv.count, &iv)
        return iv + crypt(plain, key: key, algorithm: CCAlgorithm(kCCAlgorithmAES), options: CCOptions(kCCOptionPKCS7Padding), iv: iv)
    }

    private static func rc4(_ plain: [UInt8], key: [UInt8]) -> [UInt8] {
        crypt(plain, key: key, algorithm: CCAlgorithm(kCCAlgorithmRC4), options: 0, iv: nil)
    }

    private static func crypt(_ input: [UInt8], key: [UInt8], algorithm: CCAlgorithm, options: CCOptions, iv: [UInt8]?) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), algorithm, options, key, key.count, iv, input, input.count, &out, out.count, &moved)
        return status == kCCSuccess ? Array(out.prefix(moved)) : []
    }
}
