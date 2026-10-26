import AppKit
import PDFKit
import PagecraftCore
import UniformTypeIdentifiers

/// What the Merge Files window knows about one file in its list.
struct MergeItem: Identifiable {
    enum State: Equatable {
        case loading
        case ready
        case locked
        case failed
    }

    let id = UUID()
    let url: URL
    let isPDF: Bool
    var state: State
    var pages = 0
    var fileSize: Int64?
    let modified: Date?
    var thumbnail: NSImage?
    /// True when `thumbnail` is the Finder icon rather than a rendered first page.
    var thumbnailIsIcon = true
    /// Kept so the merge does not read the file a second time and so a locked file stays unlocked.
    var document: PDFDocument?
    /// Why the file could not be read or converted.
    var error: String?

    var name: String { url.lastPathComponent }

    var detail: String {
        if let error { return error }
        switch state {
        case .loading: return "Reading…"
        case .locked: return "Password protected"
        case .failed: return "Couldn’t read this file"
        case .ready:
            guard isPDF else { return "Will be converted · \(MergeKind.label(for: url))" }
            let count = "\(pages) \(pages == 1 ? "page" : "pages")"
            guard let fileSize else { return count }
            return "\(count) · \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))"
        }
    }
}

enum MergeKind {
    /// Extensions Convert handles that the system may not map to a type Convert.supportedTypes conforms to.
    private static let extra: Set<String> = ["md", "markdown", "docx", "doc", "odt", "txt", "text", "csv", "log", "htm", "html", "rtf", "rtfd"]

    static func isPDF(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .pdf) == true
    }

    static func isSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if extra.contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return Convert.supportedTypes.contains { $0 != .data && type.conforms(to: $0) }
    }

    /// A short, human description of a convertible file.
    static func label(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "docx", "doc": return "Word document"
        case "odt": return "OpenDocument text"
        case "rtf", "rtfd": return "Rich text"
        case "html", "htm": return "Web page"
        case "md", "markdown": return "Markdown"
        case "txt", "text", "csv", "log": return "Plain text"
        default: break
        }
        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .image) { return "Image" }
            if let description = type.localizedDescription { return description.prefix(1).uppercased() + description.dropFirst() }
        }
        return "Document"
    }
}

/// Reads PDFs and renders their first page away from the main thread.
enum MergeLoader {
    struct Loaded: @unchecked Sendable {
        var document: PDFDocument?
        var locked = false
        var pages = 0
        var thumbnail: NSImage?
    }

    static func load(_ url: URL) async -> Loaded {
        await Task.detached(priority: .userInitiated) {
            guard let doc = PDFDocument(url: url) else { return Loaded() }
            if doc.isLocked { return Loaded(document: doc, locked: true) }
            return Loaded(document: doc, pages: doc.pageCount, thumbnail: thumbnail(of: doc))
        }.value
    }

    static func thumbnail(of doc: PDFDocument, in box: CGSize = CGSize(width: 96, height: 120)) -> NSImage? {
        guard let page = doc.page(at: 0) else { return nil }
        var bounds = page.bounds(for: .cropBox)
        if page.rotation % 180 != 0 { bounds.size = CGSize(width: bounds.height, height: bounds.width) }
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(box.width / bounds.width, box.height / bounds.height)
        return page.thumbnail(of: CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale)), for: .cropBox)
    }

    static func thumbnailAsync(of doc: PDFDocument) async -> NSImage? {
        struct Box: @unchecked Sendable { let doc: PDFDocument }
        let box = Box(doc: doc)
        return await Task.detached(priority: .userInitiated) { thumbnail(of: box.doc) }.value
    }
}

@MainActor
final class MergeModel: ObservableObject {
    @Published var items: [MergeItem] = []
    @Published var selection: UUID?
    /// Where a drop would land (0...items.count), while a drag hovers over the list.
    @Published var insertionIndex: Int?
    @Published var isTargeted = false
    @Published var isMerging = false
    @Published var progress: Double?
    @Published var progressText = ""

    /// The row currently being dragged for reordering.
    var draggingID: UUID?
    var onFinished: () -> Void = {}

    // MARK: Derived state

    var lockedCount: Int { items.filter { $0.state == .locked }.count }
    var isLoading: Bool { items.contains { $0.state == .loading } }
    var knownPages: Int { items.filter { $0.isPDF && $0.state == .ready }.reduce(0) { $0 + $1.pages } }
    var convertedCount: Int { items.filter { !$0.isPDF }.count }
    var canMerge: Bool { !items.isEmpty && lockedCount == 0 && !isLoading && !isMerging }

    // MARK: Adding

    /// Adds supported files (and the supported files directly inside dropped folders) at `index`, or at the end.
    func add(_ urls: [URL], at index: Int? = nil) {
        let files = urls.flatMap(Self.expand).filter(MergeKind.isSupported)
        guard !files.isEmpty else { return }
        var created: [MergeItem] = []
        for url in files {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let isPDF = MergeKind.isPDF(url)
            var item = MergeItem(url: url, isPDF: isPDF, state: isPDF ? .loading : .ready,
                                 modified: values?.contentModificationDate)
            item.fileSize = values?.fileSize.map(Int64.init)
            item.thumbnail = NSWorkspace.shared.icon(forFile: url.path)
            created.append(item)
        }
        let at = min(max(index ?? items.count, 0), items.count)
        items.insert(contentsOf: created, at: at)
        for item in created where item.isPDF { load(item.id, url: item.url) }
    }

    private static func expand(_ url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
              url.pathExtension.lowercased() != "rtfd"
        else { return [url] }
        let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return children.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func load(_ id: UUID, url: URL) {
        Task {
            let loaded = await MergeLoader.load(url)
            guard let i = items.firstIndex(where: { $0.id == id }) else { return }
            items[i].document = loaded.document
            if loaded.document == nil {
                items[i].state = .failed
            } else if loaded.locked {
                items[i].state = .locked
            } else if loaded.pages == 0 {
                items[i].state = .failed
                items[i].error = "This PDF has no pages"
            } else {
                items[i].state = .ready
                items[i].pages = loaded.pages
                if let thumbnail = loaded.thumbnail {
                    items[i].thumbnail = thumbnail
                    items[i].thumbnailIsIcon = false
                }
            }
        }
    }

    func unlock(_ id: UUID, password: String) -> Bool {
        guard let i = items.firstIndex(where: { $0.id == id }), let doc = items[i].document,
              doc.unlock(withPassword: password), doc.pageCount > 0
        else { return false }
        items[i].state = .ready
        items[i].pages = doc.pageCount
        items[i].error = nil
        Task {
            let image = await MergeLoader.thumbnailAsync(of: doc)
            guard let image, let j = items.firstIndex(where: { $0.id == id }) else { return }
            items[j].thumbnail = image
            items[j].thumbnailIsIcon = false
        }
        return true
    }

    // MARK: Editing the list

    func remove(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: i)
        if selection == id { selection = items.isEmpty ? nil : items[min(i, items.count - 1)].id }
    }

    func removeSelection() { selection.map(remove) }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        guard let selection, let i = items.firstIndex(where: { $0.id == selection }) else {
            self.selection = delta > 0 ? items.first?.id : items.last?.id
            return
        }
        self.selection = items[min(max(i + delta, 0), items.count - 1)].id
    }

    /// Moves a row so it sits at `insertion` (an index in the list before the move).
    func move(_ id: UUID, toInsertion insertion: Int) {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: from)
        let target = insertion > from ? insertion - 1 : insertion
        items.insert(item, at: min(max(target, 0), items.count))
    }

    func sortByName() {
        items.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func sortByDate() {
        items.sort { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
    }

    func reverse() { items.reverse() }

    // MARK: Merging

    func merge() {
        guard canMerge else { return }
        isMerging = true
        Task { await runMerge() }
    }

    private func runMerge() async {
        defer { isMerging = false; progress = nil; progressText = "" }
        for i in items.indices where items[i].state == .ready { items[i].error = nil }

        let snapshot = items
        var docs: [PDFDocument] = []
        var failed: [String] = []
        for (i, item) in snapshot.enumerated() {
            progress = Double(i) / Double(snapshot.count)
            progressText = item.isPDF ? "Adding \(i + 1) of \(snapshot.count)…" : "Converting \(i + 1) of \(snapshot.count)…"
            // Let the progress render before a long conversion occupies the main thread.
            try? await Task.sleep(nanoseconds: 20_000_000)

            func fail(_ message: String) {
                failed.append(item.name)
                if let j = items.firstIndex(where: { $0.id == item.id }) { items[j].error = message }
            }
            if item.state == .failed { failed.append(item.name); continue }
            if item.isPDF {
                if let doc = item.document, !doc.isLocked, doc.pageCount > 0 { docs.append(doc) } else { fail("Couldn’t read this file") }
            } else {
                do {
                    let doc = try Convert.document(from: item.url)
                    if doc.pageCount > 0 { docs.append(doc) } else { fail("Nothing to convert in this file") }
                } catch {
                    fail("Couldn’t convert this file")
                }
            }
        }

        if !failed.isEmpty {
            guard !docs.isEmpty else {
                Prompt.error("None of the files could be merged.")
                return
            }
            let list = failed.joined(separator: ", ")
            guard Prompt.confirm("\(failed.count) \(failed.count == 1 ? "file" : "files") can’t be merged",
                                 message: "\(list) will be left out. The other \(docs.count) will be merged.",
                                 button: "Merge Without Them")
            else { return }
        }

        progress = nil
        progressText = "Merging…"
        try? await Task.sleep(nanoseconds: 20_000_000)
        let merged = PDFOps.merge(docs)
        guard merged.pageCount > 0 else {
            Prompt.error("The merged document has no pages.")
            return
        }
        guard let url = Prompt.save(.pdf, name: "Merged.pdf", title: "Save Merged PDF") else { return }
        progressText = "Saving…"
        try? await Task.sleep(nanoseconds: 20_000_000)
        guard PDFOps.write(merged, to: url) else {
            Prompt.error("Could not write \(url.lastPathComponent).")
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        onFinished()
    }
}
