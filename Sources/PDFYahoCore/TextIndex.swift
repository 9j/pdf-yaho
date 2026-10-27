import Foundation
import PDFKit

/// The text of every page, extracted once and kept for searching. PDFKit's `findString` extracts
/// all page text on the calling thread; on a 4,000-page manual the first search froze the app for
/// about 19 seconds. The index fills in the background and searches run off the main thread.
public final class TextIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [ObjectIdentifier: (page: PDFPage, text: NSString)] = [:]

    public init() {}

    /// The page's text with line breaks as spaces, so phrases match across lines.
    /// Each break is one UTF-16 unit, so ranges stay valid for `PDFPage.selection(for:)`.
    public func text(of page: PDFPage) -> NSString {
        let key = ObjectIdentifier(page)
        lock.lock()
        if let entry = texts[key], entry.page === page { lock.unlock(); return entry.text }
        lock.unlock()
        let raw = page.string ?? ""
        let text = raw.replacingOccurrences(of: "[\\r\\n]", with: " ", options: .regularExpression) as NSString
        lock.lock()
        texts[key] = (page, text)
        lock.unlock()
        return text
    }

    /// Extracts the text of pages not yet indexed, on several threads (about 3× faster than one),
    /// in page order so a search that starts meanwhile mostly finds pages ready. Stops when the
    /// surrounding task is cancelled; the worker threads can't see that themselves, so it is relayed.
    public func fill(_ pages: [PDFPage], workers: Int = 4) async {
        let stop = StopFlag()
        await withTaskCancellationHandler {
            DispatchQueue.concurrentPerform(iterations: workers) { worker in
                var i = worker
                while i < pages.count, !stop.isSet {
                    _ = text(of: pages[i])
                    i += workers
                }
            }
        } onCancel: {
            stop.set()
        }
    }

    public func invalidate(_ page: PDFPage) {
        lock.lock()
        texts[ObjectIdentifier(page)] = nil
        lock.unlock()
    }

    public func removeAll() {
        lock.lock()
        texts.removeAll()
        lock.unlock()
    }

    /// Ranges of `query` in `text`, in order.
    public static func ranges(of query: String, in text: NSString, matchCase: Bool, wholeWords: Bool) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let options: NSString.CompareOptions = matchCase ? [] : [.caseInsensitive, .diacriticInsensitive]
        var found: [NSRange] = []
        var from = 0
        while from < text.length {
            let match = text.range(of: query, options: options, range: NSRange(location: from, length: text.length - from))
            if match.location == NSNotFound { break }
            if !wholeWords || isWholeWord(match, in: text) { found.append(match) }
            from = NSMaxRange(match)
        }
        return found
    }

    static func isWholeWord(_ range: NSRange, in text: NSString) -> Bool {
        func isWordCharacter(at index: Int) -> Bool {
            guard index >= 0, index < text.length else { return false }
            let character = text.substring(with: text.rangeOfComposedCharacterSequence(at: index))
            return character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        }
        return !isWordCharacter(at: range.location - 1) && !isWordCharacter(at: NSMaxRange(range))
    }

    /// The match with up to a few words either side, trimmed at word boundaries.
    public static func snippet(for range: NSRange, in text: NSString) -> (before: String, match: String, after: String) {
        let start = max(0, range.location - 40)
        let end = min(text.length, NSMaxRange(range) + 50)
        var before = text.substring(with: NSRange(location: start, length: range.location - start))
        var after = text.substring(with: NSRange(location: NSMaxRange(range), length: end - NSMaxRange(range)))
        if start > 0, let space = before.firstIndex(of: " ") { before = "…" + before[before.index(after: space)...] }
        if end < text.length, let space = after.lastIndex(of: " ") { after = after[..<space] + "…" }
        return (before, text.substring(with: range), after)
    }
}

private final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}
