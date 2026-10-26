import AppKit
import PDFKit

/// What a document card shows in place of a first page.
enum PreviewState: Sendable {
    case ready
    case locked
    case unreadable
}

struct DocumentPreview: @unchecked Sendable {
    var image: NSImage?
    var state: PreviewState
    /// When the file was last opened (content access date), else last modified.
    var date: Date?
}

/// Renders and caches first-page thumbnails away from the main thread.
final class PreviewLoader: @unchecked Sendable {
    static let shared = PreviewLoader()

    private final class Entry {
        let image: NSImage?
        let state: PreviewState
        init(image: NSImage?, state: PreviewState) { self.image = image; self.state = state }
    }

    private let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 256
        return cache
    }()

    func preview(for url: URL) async -> DocumentPreview {
        await Task.detached(priority: .utility) { [self] in load(url) }.value
    }

    private func load(_ url: URL) -> DocumentPreview {
        let values = try? url.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey, .fileSizeKey])
        // The access date moves every time the file opens, so it is read fresh and never cached.
        let date = values?.contentAccessDate ?? values?.contentModificationDate
        let stamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(stamp)|\(values?.fileSize ?? 0)" as NSString
        if let hit = cache.object(forKey: key) {
            return DocumentPreview(image: hit.image, state: hit.state, date: date)
        }
        let rendered = Self.render(url)
        cache.setObject(Entry(image: rendered.image, state: rendered.state), forKey: key)
        return DocumentPreview(image: rendered.image, state: rendered.state, date: date)
    }

    private static func render(_ url: URL) -> (image: NSImage?, state: PreviewState) {
        guard let document = PDFDocument(url: url) else { return (nil, .unreadable) }
        if document.isLocked { return (nil, .locked) }
        guard let page = document.page(at: 0) else { return (nil, .unreadable) }
        var bounds = page.bounds(for: .cropBox)
        if page.rotation % 180 != 0 { bounds.size = CGSize(width: bounds.height, height: bounds.width) }
        guard bounds.width > 0, bounds.height > 0 else { return (nil, .unreadable) }
        // 2x of the largest size a card shows.
        let scale = min(360 / bounds.width, 360 / bounds.height)
        let size = CGSize(width: max(1, (bounds.width * scale).rounded()), height: max(1, (bounds.height * scale).rounded()))
        return (page.thumbnail(of: size, for: .cropBox), .ready)
    }
}
