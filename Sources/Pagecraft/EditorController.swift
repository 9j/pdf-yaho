import Combine
import PDFKit
import PagecraftCore
import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case select, highlight, underline, strikeout, pen, text, note, rectangle, oval, line, arrow, eraser, redact, signature

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: "Select"
        case .highlight: "Highlight"
        case .underline: "Underline"
        case .strikeout: "Strikeout"
        case .pen: "Pen"
        case .text: "Text"
        case .note: "Note"
        case .rectangle: "Rectangle"
        case .oval: "Oval"
        case .line: "Line"
        case .arrow: "Arrow"
        case .eraser: "Eraser"
        case .redact: "Redact"
        case .signature: "Signature"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .highlight: "highlighter"
        case .underline: "underline"
        case .strikeout: "strikethrough"
        case .pen: "pencil.tip"
        case .text: "textformat"
        case .note: "note.text"
        case .rectangle: "rectangle"
        case .oval: "circle"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .eraser: "eraser"
        case .redact: "rectangle.inset.filled"
        case .signature: "signature"
        }
    }

    var markupType: PDFAnnotationSubtype? {
        switch self {
        case .highlight: .highlight
        case .underline: .underline
        case .strikeout: .strikeOut
        default: nil
        }
    }

    var shape: ShapeKind? {
        switch self {
        case .rectangle: .rectangle
        case .oval: .oval
        case .line: .line
        case .arrow: .arrow
        default: nil
        }
    }

    /// Tools that draw by dragging on the page instead of selecting text.
    var draws: Bool { self == .pen || shape != nil || self == .redact }
}

enum PageLayout: String, CaseIterable, Identifiable {
    case single = "Single Page", continuous = "Continuous", twoUp = "Two Pages", book = "Two Pages, Cover Single"
    var id: String { rawValue }
}

enum ReadingTheme: String, CaseIterable, Identifiable {
    case day = "Day", night = "Night", sepia = "Sepia"
    var id: String { rawValue }
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case thumbnails, outline, annotations, search
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .thumbnails: "square.grid.2x2"
        case .outline: "list.bullet.indent"
        case .annotations: "pencil.tip.crop.circle"
        case .search: "magnifyingglass"
        }
    }
}

/// Per-window editing state and every mutation of the document. Mutations register undo
/// actions, which is also how SwiftUI learns that the document has unsaved changes.
@MainActor
final class EditorController: ObservableObject {
    let file: PDFFile
    var document: PDFDocument { file.pdf }
    weak var pdfView: EditorPDFView?
    weak var undoManager: UndoManager?

    @Published var tool: Tool = .select { didSet { toolChanged() } }
    @Published var color: Color = .yellow
    @Published var lineWidth: CGFloat = 2
    @Published var fontSize: CGFloat = 14
    @Published var layout: PageLayout = .continuous { didSet { applyLayout() } }
    @Published var theme: ReadingTheme = .day { didSet { applyTheme() } }
    @Published var sidebarTab: SidebarTab = .thumbnails
    @Published var selectedPages: Set<Int> = []
    @Published private(set) var currentPageIndex = 0
    @Published private(set) var revision = 0
    @Published private(set) var scale: CGFloat = 1
    @Published var searchText = ""
    @Published private(set) var searchResults: [PDFSelection] = []
    @Published var searchIndex = 0
    @Published var showSignaturePad = false
    @Published var showProperties = false
    @Published var needsPassword: Bool

    private var thumbnailCache: [ObjectIdentifier: (rotation: Int, image: NSImage)] = [:]
    private var observers: [NSObjectProtocol] = []

    init(file: PDFFile) {
        self.file = file
        needsPassword = file.pdf.isLocked
    }

    var nsColor: NSColor { NSColor(color) }
    var pageCount: Int { document.pageCount }
    var hasRedactions: Bool {
        PDFOps.pages(of: document).contains { $0.annotations.contains(where: Annotations.isRedaction) }
    }

    var title: String {
        if let window = pdfView?.window, !window.title.isEmpty { return (window.title as NSString).deletingPathExtension }
        return "Document"
    }

    // MARK: View wiring

    func attach(_ view: EditorPDFView) {
        pdfView = view
        view.editor = self
        view.document = document
        applyLayout()
        applyTheme()
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers = [
            center.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncCurrentPage() }
            },
            center.addObserver(forName: .PDFViewScaleChanged, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scale = view.scaleFactor }
            },
            center.addObserver(forName: .PDFViewAnnotationHit, object: view, queue: .main) { [weak self] note in
                // Form widgets are edited by PDFKit directly; record that the document changed.
                let annotation = note.userInfo?["PDFAnnotationHit"] as? PDFAnnotation
                MainActor.assumeIsolated {
                    if annotation?.type == "Widget" { self?.markEdited() }
                }
            },
        ]
    }

    private func syncCurrentPage() {
        guard let page = pdfView?.currentPage else { return }
        currentPageIndex = document.index(for: page)
    }

    func markEdited() {
        guard let window = pdfView?.window else { return }
        NSDocumentController.shared.document(for: window)?.updateChangeCount(.changeDone)
    }

    private func changed(_ pages: [PDFPage] = []) {
        for page in pages { thumbnailCache[ObjectIdentifier(page)] = nil }
        if pages.isEmpty { thumbnailCache.removeAll() }
        for page in pages { pdfView?.annotationsChanged(on: page) }
        revision += 1
    }

    private func registerUndo(_ name: String, _ action: @escaping @MainActor (EditorController) -> Void) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { action(target) }
        }
        undoManager?.setActionName(name)
    }

    func thumbnail(for index: Int) -> NSImage? {
        guard let page = document.page(at: index) else { return nil }
        let key = ObjectIdentifier(page)
        if let cached = thumbnailCache[key], cached.rotation == page.rotation { return cached.image }
        let image = page.thumbnail(of: CGSize(width: 240, height: 300), for: .cropBox)
        thumbnailCache[key] = (page.rotation, image)
        return image
    }

    // MARK: Tools

    private func toolChanged() {
        if let type = tool.markupType, let selection = pdfView?.currentSelection, !(selection.string ?? "").isEmpty {
            applyMarkup(type, to: selection)
        }
        if tool == .signature, SignatureStore.load() == nil { showSignaturePad = true }
        if tool == .highlight, color == .black { color = .yellow }
    }

    func applyMarkup(_ type: PDFAnnotationSubtype, to selection: PDFSelection) {
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard bounds.width > 0.5, bounds.height > 0.5 else { continue }
                add(Annotations.markup(type, bounds: bounds, color: nsColor), to: page)
            }
        }
        pdfView?.clearSelection()
    }

    func add(_ annotation: PDFAnnotation, to page: PDFPage) {
        page.addAnnotation(annotation)
        registerUndo("Add \(Annotations.displayName(annotation))") { $0.remove(annotation, from: page) }
        changed([page])
    }

    func remove(_ annotation: PDFAnnotation, from page: PDFPage) {
        page.removeAnnotation(annotation)
        registerUndo("Delete \(Annotations.displayName(annotation))") { $0.add(annotation, to: page) }
        changed([page])
    }

    func erase(_ annotation: PDFAnnotation, on page: PDFPage) {
        guard Annotations.isUserEditable(annotation) else { return }
        remove(annotation, from: page)
    }

    func setBounds(_ bounds: CGRect, of annotation: PDFAnnotation, on page: PDFPage, previous: CGRect) {
        annotation.bounds = bounds
        registerUndo("Move Annotation") { $0.setBounds(previous, of: annotation, on: page, previous: bounds) }
        changed([page])
    }

    func setContents(_ contents: String, of annotation: PDFAnnotation, on page: PDFPage) {
        let previous = annotation.contents ?? ""
        annotation.contents = contents
        if annotation.type == "FreeText", let font = annotation.font {
            let size = (contents as NSString).boundingRect(with: CGSize(width: 400, height: 10_000),
                                                           options: [.usesLineFragmentOrigin], attributes: [.font: font]).size
            var b = annotation.bounds
            b.origin.y = b.maxY - ceil(size.height) - 6
            b.size = CGSize(width: ceil(size.width) + 12, height: ceil(size.height) + 6)
            annotation.bounds = b
        }
        registerUndo("Edit Text") { $0.setContents(previous, of: annotation, on: page) }
        changed([page])
    }

    func placeText(at point: CGPoint, on page: PDFPage) {
        guard let text = Prompt.text("Add Text", message: "Text to place on the page:"), !text.isEmpty else { return }
        add(Annotations.freeText(text, at: point, color: textColor, fontSize: fontSize), to: page)
    }

    func placeNote(at point: CGPoint, on page: PDFPage) {
        guard let text = Prompt.text("Add Note", message: "Note contents:"), !text.isEmpty else { return }
        add(Annotations.note(text, at: point, color: nsColor), to: page)
    }

    func placeSignature(at point: CGPoint, on page: PDFPage) {
        guard let signature = SignatureStore.load() else { showSignaturePad = true; return }
        if let a = signature.annotation(center: point, width: 160, color: textColor) { add(a, to: page) }
    }

    func editAnnotation(_ annotation: PDFAnnotation, on page: PDFPage) {
        guard ["FreeText", "Text"].contains(annotation.type ?? "") else { return }
        guard let text = Prompt.text("Edit", message: "", defaultValue: annotation.contents ?? "") else { return }
        setContents(text, of: annotation, on: page)
    }

    /// Yellow is a highlighter colour; text and ink default to something legible instead.
    private var textColor: NSColor { color == .yellow ? .black : nsColor }

    func removeAllAnnotations() {
        for page in PDFOps.pages(of: document) {
            for a in page.annotations where Annotations.isUserEditable(a) { remove(a, from: page) }
        }
        undoManager?.setActionName("Remove All Annotations")
    }

    func applyRedactions() {
        let targets = PDFOps.pages(of: document).filter { $0.annotations.contains(where: Annotations.isRedaction) }
        guard !targets.isEmpty else { return }
        guard Prompt.confirm("Apply \(targets.count == 1 ? "redaction" : "redactions")?",
                             message: "Pages with redaction marks will be flattened into images. Covered text is permanently removed, and the rest of those pages stops being selectable.",
                             button: "Apply")
        else { return }
        let replaced = PDFOps.pages(of: document).map { page in
            targets.contains(page) ? (PDFOps.rasterized(page) ?? page) : page
        }
        setPages(replaced, actionName: "Apply Redactions")
    }

    // MARK: Pages

    func setPages(_ pages: [PDFPage], actionName: String) {
        let previous = PDFOps.pages(of: document)
        let current = currentPageIndex
        PDFOps.setPages(pages, in: document)
        registerUndo(actionName) { $0.setPages(previous, actionName: actionName) }
        changed()
        goToPage(min(current, max(pages.count - 1, 0)))
        selectedPages = selectedPages.filter { $0 < pages.count }
    }

    var targetPageIndices: [Int] {
        selectedPages.isEmpty ? [currentPageIndex] : selectedPages.sorted()
    }

    func rotate(_ degrees: Int, pages indices: [Int]? = nil) {
        rotate(degrees, pages: (indices ?? targetPageIndices).compactMap { document.page(at: $0) })
    }

    private func rotate(_ degrees: Int, pages: [PDFPage]) {
        for page in pages { page.rotation = (page.rotation + degrees + 360) % 360 }
        registerUndo("Rotate") { $0.rotate(-degrees, pages: pages) }
        changed(pages)
        pdfView?.layoutDocumentView()
    }

    func deletePages(_ indices: [Int]? = nil) {
        let doomed = Set(indices ?? targetPageIndices)
        guard doomed.count < pageCount else { NSSound.beep(); return }
        let kept = PDFOps.pages(of: document).enumerated().filter { !doomed.contains($0.offset) }.map(\.element)
        selectedPages = []
        setPages(kept, actionName: doomed.count == 1 ? "Delete Page" : "Delete Pages")
    }

    func insertBlankPage(after index: Int? = nil) {
        var pages = PDFOps.pages(of: document)
        let at = min((index ?? currentPageIndex) + 1, pages.count)
        let size = pages.first?.bounds(for: .mediaBox).size ?? PDFOps.letter
        pages.insert(PDFOps.blankPage(size: size), at: at)
        setPages(pages, actionName: "Insert Page")
        goToPage(at)
    }

    func movePages(from source: IndexSet, to destination: Int) {
        setPages(PDFOps.moved(PDFOps.pages(of: document), from: source, to: destination), actionName: "Move Pages")
    }

    func insertPages(from url: URL) {
        guard let other = PDFDocument(url: url) else { Prompt.error("Could not open \(url.lastPathComponent).") ; return }
        var pages = PDFOps.pages(of: document)
        let at = min(currentPageIndex + 1, pages.count)
        pages.insert(contentsOf: PDFOps.copies(of: PDFOps.pages(of: other)), at: at)
        setPages(pages, actionName: "Insert Pages")
    }

    func addPageNumbers() {
        let added = PDFOps.addPageNumbers(to: document)
        registerUndo("Add Page Numbers") { editor in
            for (page, a) in added { page.removeAnnotation(a) }
            editor.changed()
        }
        changed()
    }

    func removePageNumbers() {
        let removed = PDFOps.removePageNumbers(from: document)
        guard !removed.isEmpty else { return }
        registerUndo("Remove Page Numbers") { editor in
            for (page, a) in removed { page.addAnnotation(a) }
            editor.changed()
        }
        changed()
    }

    func addBookmark(label: String, page index: Int) {
        guard let page = document.page(at: index) else { return }
        let hadRoot = document.outlineRoot != nil
        let root = document.outlineRoot ?? PDFOutline()
        if !hadRoot { document.outlineRoot = root }
        let item = PDFOutline()
        item.label = label
        let top = page.bounds(for: .cropBox).maxY
        item.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: top))
        root.insertChild(item, at: root.numberOfChildren)
        registerUndo("Add Bookmark") { editor in
            item.removeFromParent()
            if !hadRoot { editor.document.outlineRoot = nil }
            editor.changed()
        }
        changed()
    }

    func setAttributes(_ attributes: [AnyHashable: Any]) {
        let previous = document.documentAttributes ?? [:]
        document.documentAttributes = attributes
        registerUndo("Change Properties") { $0.setAttributes(previous) }
    }

    // MARK: Navigation and view

    func goToPage(_ index: Int) {
        guard let page = document.page(at: index) else { return }
        pdfView?.go(to: page)
        currentPageIndex = index
    }

    func go(to selection: PDFSelection) {
        pdfView?.setCurrentSelection(selection, animate: true)
        pdfView?.go(to: selection)
    }

    func zoomIn() { pdfView?.zoomIn(nil) }
    func zoomOut() { pdfView?.zoomOut(nil) }
    func actualSize() { pdfView?.autoScales = false; pdfView?.scaleFactor = 1 }
    func fitWidth() { pdfView?.autoScales = true }

    func fitPage() {
        guard let view = pdfView, let page = view.currentPage else { return }
        view.autoScales = false
        var box = page.bounds(for: view.displayBox).size
        if page.rotation % 180 != 0 { box = CGSize(width: box.height, height: box.width) }
        let available = view.bounds.insetBy(dx: 24, dy: 24).size
        view.scaleFactor = min(available.width / box.width, available.height / box.height)
    }

    private func applyLayout() {
        guard let view = pdfView else { return }
        switch layout {
        case .single: view.displayMode = .singlePage; view.displaysAsBook = false
        case .continuous: view.displayMode = .singlePageContinuous; view.displaysAsBook = false
        case .twoUp: view.displayMode = .twoUpContinuous; view.displaysAsBook = false
        case .book: view.displayMode = .twoUpContinuous; view.displaysAsBook = true
        }
    }

    private func applyTheme() {
        guard let view = pdfView else { return }
        view.wantsLayer = true
        view.layerUsesCoreImageFilters = true
        switch theme {
        case .day:
            view.contentFilters = []
        case .night:
            let invert = CIFilter(name: "CIColorInvert")!
            let hue = CIFilter(name: "CIHueAdjust")!
            hue.setValue(Float.pi, forKey: kCIInputAngleKey)
            view.contentFilters = [invert, hue]
        case .sepia:
            let sepia = CIFilter(name: "CISepiaTone")!
            sepia.setValue(0.55, forKey: kCIInputIntensityKey)
            view.contentFilters = [sepia]
        }
    }

    // MARK: Search

    func search() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { clearSearch(); return }
        searchResults = document.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
        for result in searchResults { result.color = NSColor.systemYellow.withAlphaComponent(0.6) }
        pdfView?.highlightedSelections = searchResults
        searchIndex = 0
        sidebarTab = .search
        if let first = searchResults.first { go(to: first) }
    }

    func clearSearch() {
        searchResults = []
        pdfView?.highlightedSelections = nil
        if sidebarTab == .search { sidebarTab = .thumbnails }
    }

    func findNext(_ step: Int = 1) {
        guard !searchResults.isEmpty else { search(); return }
        searchIndex = (searchIndex + step + searchResults.count) % searchResults.count
        go(to: searchResults[searchIndex])
    }

    func unlock(with password: String) -> Bool {
        guard document.unlock(withPassword: password) else { return false }
        needsPassword = false
        changed()
        return true
    }
}
