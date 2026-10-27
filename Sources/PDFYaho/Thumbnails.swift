import PDFKit
import SwiftUI

/// Page thumbnails kept within a memory budget. A 4,000-page document would otherwise hold a
/// gigabyte of images, and rendering them on the main thread stalled scrolling.
@MainActor
final class ThumbnailCache {
    private let cache: NSCache<Key, NSImage> = {
        let cache = NSCache<Key, NSImage>()
        cache.totalCostLimit = 160 << 20
        return cache
    }()
    /// Bumped when a page's content changes, so its old thumbnails stop matching.
    private var versions: [ObjectIdentifier: Int] = [:]
    private let gate = RenderGate(width: 2)

    func image(for page: PDFPage, side: CGFloat) -> NSImage? {
        cache.object(forKey: key(page, side))
    }

    func render(_ page: PDFPage, side: CGFloat) -> NSImage {
        let key = key(page, side)
        let image = page.thumbnail(of: CGSize(width: key.bucket, height: key.bucket), for: .cropBox)
        store(image, key)
        return image
    }

    func renderInBackground(_ page: PDFPage, side: CGFloat) async -> NSImage? {
        let key = key(page, side)
        await gate.enter()
        defer { Task { await gate.leave() } }
        // Rows scrolled away while waiting their turn don't need their thumbnail any more.
        guard !Task.isCancelled else { return nil }
        if let image = cache.object(forKey: key) { return image }
        let job = UncheckedPage(page: page)
        let size = CGSize(width: key.bucket, height: key.bucket)
        let image = await Task.detached(priority: .userInitiated) { job.page.thumbnail(of: size, for: .cropBox) }.value
        // The page may have changed while it rendered; keep the image only if the key still matches.
        if key == self.key(page, side) { store(image, key) }
        return image
    }

    func invalidate(_ page: PDFPage) { versions[ObjectIdentifier(page), default: 0] += 1 }

    func removeAll() {
        cache.removeAllObjects()
        versions.removeAll()
    }

    private func key(_ page: PDFPage, _ side: CGFloat) -> Key {
        Key(page: page, bucket: side <= 240 ? 240 : side <= 480 ? 480 : 720,
            rotation: page.rotation, version: versions[ObjectIdentifier(page)] ?? 0)
    }

    private func store(_ image: NSImage, _ key: Key) {
        cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
    }

    /// Holds its page strongly, so a cached entry can never match a new page at a reused address.
    final class Key: NSObject {
        let page: PDFPage, bucket: Int, rotation: Int, version: Int
        init(page: PDFPage, bucket: Int, rotation: Int, version: Int) {
            self.page = page; self.bucket = bucket; self.rotation = rotation; self.version = version
        }
        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Key else { return false }
            return other.page === page && other.bucket == bucket && other.rotation == rotation && other.version == version
        }
        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(ObjectIdentifier(page)); hasher.combine(bucket); hasher.combine(rotation); hasher.combine(version)
            return hasher.finalize()
        }
    }
}

/// PDFKit draws pages on background threads itself; a page is only read while its thumbnail renders.
private struct UncheckedPage: @unchecked Sendable { let page: PDFPage }

/// Limits concurrent renders. The newest request goes first, since that is the row the user just scrolled to.
private actor RenderGate {
    private let width: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(width: Int) { self.width = width }

    func enter() async {
        if running < width { running += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func leave() {
        if let next = waiting.popLast() { next.resume() } else { running -= 1 }
    }
}

/// A page thumbnail that renders in the background, showing a blank page of the right shape until it is ready.
struct PageThumbnail: View {
    let editor: EditorController
    let index: Int
    let side: CGFloat
    @State private var loaded: NSImage?

    var body: some View {
        // `revision` changes with every edit, so a changed or moved page re-renders.
        let key = "\(index)-\(side)-\(editor.revision)"
        Group {
            if let image = editor.cachedThumbnail(for: index, side: side) ?? loaded {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Color.white.aspectRatio(editor.pageAspect(index), contentMode: .fit)
            }
        }
        .task(id: key) {
            if let image = await editor.loadThumbnail(for: index, side: side) { loaded = image }
        }
    }
}
