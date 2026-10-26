import Combine
import PDFKit
import PagecraftCore
import SwiftUI

enum EditorMode: String, CaseIterable, Identifiable {
    case read = "Read", markup = "Markup", pages = "Pages"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .read: "book"
        case .markup: "pencil.tip.crop.circle"
        case .pages: "square.grid.2x2"
        }
    }
}

enum Tool: String, CaseIterable, Identifiable {
    case select, highlight, underline, strikeout, pen, text, note, rectangle, oval, line, arrow, signature, redact, eraser

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: "Select"
        case .highlight: "Highlight"
        case .underline: "Underline"
        case .strikeout: "Strike"
        case .pen: "Pen"
        case .text: "Text"
        case .note: "Note"
        case .rectangle: "Rectangle"
        case .oval: "Oval"
        case .line: "Line"
        case .arrow: "Arrow"
        case .signature: "Sign"
        case .redact: "Redact"
        case .eraser: "Eraser"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .highlight: "highlighter"
        case .underline: "underline"
        case .strikeout: "strikethrough"
        case .pen: "pencil.tip"
        case .text: "character.textbox"
        case .note: "note.text"
        case .rectangle: "rectangle"
        case .oval: "circle"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .signature: "signature"
        case .redact: "rectangle.inset.filled"
        case .eraser: "eraser"
        }
    }

    /// Single-key shortcut, active while the document has focus.
    var key: Character? {
        switch self {
        case .select: "v"
        case .highlight: "h"
        case .underline: "u"
        case .strikeout: "k"
        case .pen: "p"
        case .text: "t"
        case .note: "n"
        case .rectangle: "r"
        case .oval: "o"
        case .line: "l"
        case .arrow: "a"
        case .signature: "g"
        case .redact: "x"
        case .eraser: "e"
        }
    }

    var help: String { key.map { "\(label) (\(String($0).uppercased()))" } ?? label }

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

    static let shapes: [Tool] = [.rectangle, .oval, .line, .arrow]

    /// Tools whose look the user can tune with the colour and width controls.
    var isStyled: Bool { ![.select, .eraser, .redact, .signature].contains(self) }
    var usesWidth: Bool { self == .pen || shape != nil || self == .text }
}

struct ToolStyle: Equatable {
    var color: NSColor
    /// Stroke width, or font size for the text tool.
    var width: CGFloat
}

struct SelectedAnnotation: Equatable {
    let annotation: PDFAnnotation
    let page: PDFPage
    static func == (a: Self, b: Self) -> Bool { a.annotation === b.annotation }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    var url: URL?
}

enum Palette {
    static let swatches: [NSColor] = [
        NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1),
        NSColor(srgbRed: 0.56, green: 0.56, blue: 0.58, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.80, blue: 0.00, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1),
        NSColor(srgbRed: 0.19, green: 0.69, blue: 0.78, alpha: 1),
        NSColor(srgbRed: 0.00, green: 0.48, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.35, green: 0.34, blue: 0.84, alpha: 1),
        NSColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.18, blue: 0.33, alpha: 1),
        NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
    ]
    static func srgb(_ c: NSColor) -> NSColor { c.usingColorSpace(.sRGB) ?? c }
    static func same(_ a: NSColor, _ b: NSColor) -> Bool {
        let x = srgb(a), y = srgb(b)
        return abs(x.redComponent - y.redComponent) + abs(x.greenComponent - y.greenComponent) + abs(x.blueComponent - y.blueComponent) < 0.05
    }
}

enum PageLayout: String, CaseIterable, Identifiable {
    case single = "Single Page", continuous = "Continuous", twoUp = "Two Pages", book = "Two Pages, Cover Alone"
    var id: String { rawValue }
}

enum ReadingTheme: String, CaseIterable, Identifiable {
    case day = "Day", night = "Night", sepia = "Sepia"
    var id: String { rawValue }
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case thumbnails = "Pages", outline = "Outline", annotations = "Annotations", search = "Search"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .thumbnails: "square.grid.2x2"
        case .outline: "list.bullet.indent"
        case .annotations: "highlighter"
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

    @Published var mode: EditorMode = .read { didSet { modeChanged(from: oldValue) } }
    @Published var tool: Tool = .select { didSet { toolChanged() } }
    @Published var styles: [Tool: ToolStyle] = [
        .highlight: ToolStyle(color: Palette.swatches[4], width: 0),
        .underline: ToolStyle(color: Palette.swatches[7], width: 0),
        .strikeout: ToolStyle(color: Palette.swatches[2], width: 0),
        .pen: ToolStyle(color: Palette.swatches[7], width: 2),
        .text: ToolStyle(color: Palette.swatches[0], width: 14),
        .note: ToolStyle(color: Palette.swatches[4], width: 0),
        .rectangle: ToolStyle(color: Palette.swatches[2], width: 2),
        .oval: ToolStyle(color: Palette.swatches[2], width: 2),
        .line: ToolStyle(color: Palette.swatches[2], width: 2),
        .arrow: ToolStyle(color: Palette.swatches[2], width: 2),
    ]
    @Published private(set) var lastMarkupTool: Tool = .highlight
    @Published private(set) var lastShape: Tool = .rectangle
    @Published var selected: SelectedAnnotation? { didSet { overlayTick += 1 } }
    @Published var textSelectionActive = false
    /// Bumped whenever on-screen geometry changes so overlays re-measure.
    @Published private(set) var overlayTick = 0

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
    @Published var showPasswordSheet = false
    @Published var needsPassword: Bool
    @Published var toast: Toast?
    @Published var focusPageField = false

    private var thumbnailCache: [String: NSImage] = [:]
    private var observers: [NSObjectProtocol] = []

    init(file: PDFFile) {
        self.file = file
        needsPassword = file.pdf.isLocked
    }

    var pageCount: Int { document.pageCount }
    var hasRedactions: Bool {
        PDFOps.pages(of: document).contains { $0.annotations.contains(where: Annotations.isRedaction) }
    }

    var title: String {
        if let window = pdfView?.window, !window.title.isEmpty { return (window.title as NSString).deletingPathExtension }
        return "Document"
    }

    var fileURL: URL? {
        pdfView?.window.flatMap { NSDocumentController.shared.document(for: $0)?.fileURL }
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
                MainActor.assumeIsolated {
                    self?.scale = view.scaleFactor
                    self?.overlayTick += 1
                }
            },
            center.addObserver(forName: .PDFViewSelectionChanged, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if (view.currentSelection?.string ?? "").isEmpty { self?.textSelectionActive = false }
                }
            },
            center.addObserver(forName: .PDFViewAnnotationHit, object: view, queue: .main) { [weak self] note in
                // Form widgets are edited by PDFKit directly; record that the document changed.
                let annotation = note.userInfo?["PDFAnnotationHit"] as? PDFAnnotation
                MainActor.assumeIsolated {
                    if annotation?.type == "Widget" { self?.markEdited() }
                }
            },
        ]
        if let clip = view.scrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.overlayTick += 1
                    self?.pdfView?.commitInline()
                }
            })
        }
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
        if pages.isEmpty {
            thumbnailCache.removeAll()
        } else {
            let keys = Set(pages.map { "\(ObjectIdentifier($0).hashValue)" })
            thumbnailCache = thumbnailCache.filter { !keys.contains(String($0.key.split(separator: "-")[0])) }
        }
        for page in pages { pdfView?.annotationsChanged(on: page) }
        revision += 1
        overlayTick += 1
    }

    private func registerUndo(_ name: String, _ action: @escaping @MainActor (EditorController) -> Void) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { action(target) }
        }
        undoManager?.setActionName(name)
    }

    func thumbnail(for index: Int, side: CGFloat = 240) -> NSImage? {
        guard let page = document.page(at: index) else { return nil }
        let bucket = side <= 240 ? 240 : side <= 480 ? 480 : 720
        let key = "\(ObjectIdentifier(page).hashValue)-\(page.rotation)-\(bucket)"
        if let cached = thumbnailCache[key] { return cached }
        let image = page.thumbnail(of: CGSize(width: bucket, height: bucket), for: .cropBox)
        thumbnailCache[key] = image
        return image
    }

    func showToast(_ message: String, url: URL? = nil) {
        let toast = Toast(message: message, url: url)
        withAnimation(.snappy) { self.toast = toast }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard self?.toast == toast else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }

    // MARK: Geometry for SwiftUI overlays (top-left origin, PDF view coordinates)

    func viewRect(_ rect: CGRect, on page: PDFPage) -> CGRect? {
        guard let view = pdfView else { return nil }
        let r = view.convert(rect, from: page)
        return CGRect(x: r.minX, y: view.bounds.height - r.maxY, width: r.width, height: r.height)
    }

    var selectionFrame: CGRect? {
        _ = overlayTick
        return selected.flatMap { viewRect($0.annotation.bounds, on: $0.page) }
    }

    var textSelectionFrame: CGRect? {
        _ = overlayTick
        guard textSelectionActive, let selection = pdfView?.currentSelection, let page = selection.pages.first else { return nil }
        return viewRect(selection.bounds(for: page), on: page)
    }

    // MARK: Modes and tools

    private func modeChanged(from old: EditorMode) {
        guard mode != old else { return }
        select(nil)
        switch mode {
        case .read: tool = .select
        case .markup: if tool == .select { tool = lastMarkupTool }
        case .pages:
            tool = .select
            selectedPages = [currentPageIndex]
        }
    }

    private func toolChanged() {
        if tool != .select { lastMarkupTool = tool }
        if tool.shape != nil { lastShape = tool }
        if tool != .select, mode != .markup { mode = .markup }
        if tool != .select { select(nil) }
        if let type = tool.markupType, let selection = pdfView?.currentSelection, !(selection.string ?? "").isEmpty {
            applyMarkup(type, to: selection)
        }
        if tool == .signature, SignatureStore.load() == nil { showSignaturePad = true }
        if let view = pdfView { view.window?.invalidateCursorRects(for: view) }
    }

    func style(for tool: Tool) -> ToolStyle {
        styles[tool] ?? ToolStyle(color: Palette.swatches[0], width: 2)
    }

    /// The colour shown in the palette: the selected annotation's, else the active tool's.
    var activeColor: NSColor {
        if let selected { return Annotations.color(of: selected.annotation) }
        return style(for: tool).color
    }

    var activeWidth: CGFloat {
        if let selected {
            return selected.annotation.type == "FreeText" ? (selected.annotation.font?.pointSize ?? 14) : (selected.annotation.border?.lineWidth ?? 1)
        }
        return style(for: tool).width
    }

    var widthApplies: Bool {
        if let selected { return ["FreeText", "Ink", "Square", "Circle", "Line"].contains(selected.annotation.type ?? "") }
        return tool.usesWidth
    }

    var widthIsFontSize: Bool { selected?.annotation.type == "FreeText" || (selected == nil && tool == .text) }

    func setColor(_ color: NSColor) {
        let color = Palette.srgb(color)
        if let selected {
            recolor(selected.annotation, on: selected.page, to: color)
        }
        if tool.isStyled { styles[tool, default: style(for: tool)].color = color }
        if selected == nil, tool == .select { styles[.highlight]?.color = color }
    }

    func setWidth(_ width: CGFloat) {
        if let selected { restyleWidth(selected.annotation, on: selected.page, to: width) }
        if tool.usesWidth { styles[tool, default: style(for: tool)].width = width }
    }

    private func recolor(_ annotation: PDFAnnotation, on page: PDFPage, to color: NSColor) {
        let previous = Annotations.color(of: annotation)
        Annotations.setColor(color, of: annotation)
        registerUndo("Change Color") { $0.recolor(annotation, on: page, to: previous) }
        changed([page])
        objectWillChange.send()
    }

    private func restyleWidth(_ annotation: PDFAnnotation, on page: PDFPage, to width: CGFloat) {
        let previous: CGFloat
        if annotation.type == "FreeText" {
            previous = annotation.font?.pointSize ?? 14
            annotation.font = NSFont.systemFont(ofSize: width)
            refit(annotation)
        } else {
            previous = annotation.border?.lineWidth ?? 1
            let border = PDFBorder()
            border.lineWidth = width
            annotation.border = border
        }
        registerUndo("Change Width") { $0.restyleWidth(annotation, on: page, to: previous) }
        changed([page])
        objectWillChange.send()
    }

    // MARK: Annotation editing

    func select(_ selection: SelectedAnnotation?) {
        guard selected != selection else { return }
        selected = selection
        if selection != nil { textSelectionActive = false }
    }

    func applyMarkup(_ type: PDFAnnotationSubtype, to selection: PDFSelection, tool markupTool: Tool? = nil) {
        let color = style(for: markupTool ?? tool.markupType.map { _ in tool } ?? .highlight).color
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard bounds.width > 0.5, bounds.height > 0.5 else { continue }
                add(Annotations.markup(type, bounds: bounds, color: color), to: page)
            }
        }
        undoManager?.setActionName(type == .highlight ? "Highlight" : type == .underline ? "Underline" : "Strikeout")
        pdfView?.clearSelection()
        textSelectionActive = false
    }

    /// Markup from the floating text-selection menu.
    func markSelection(with markupTool: Tool) {
        guard let type = markupTool.markupType, let selection = pdfView?.currentSelection else { return }
        applyMarkup(type, to: selection, tool: markupTool)
    }

    func copySelection() {
        guard let text = pdfView?.currentSelection?.string else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        textSelectionActive = false
        showToast("Copied")
    }

    func add(_ annotation: PDFAnnotation, to page: PDFPage) {
        page.addAnnotation(annotation)
        registerUndo("Add \(Annotations.displayName(annotation))") { $0.remove(annotation, from: page) }
        changed([page])
    }

    func remove(_ annotation: PDFAnnotation, from page: PDFPage) {
        if selected?.annotation === annotation { select(nil) }
        page.removeAnnotation(annotation)
        registerUndo("Delete \(Annotations.displayName(annotation))") { $0.add(annotation, to: page) }
        changed([page])
    }

    func erase(_ annotation: PDFAnnotation, on page: PDFPage) {
        guard Annotations.isUserEditable(annotation) else { return }
        remove(annotation, from: page)
    }

    func deleteSelected() {
        guard let selected else { return }
        remove(selected.annotation, from: selected.page)
    }

    func duplicateSelected() {
        guard let selected, let copy = Annotations.duplicate(selected.annotation) else { return }
        add(copy, to: selected.page)
        select(SelectedAnnotation(annotation: copy, page: selected.page))
    }

    func nudgeSelected(dx: CGFloat, dy: CGFloat) {
        guard let selected else { return }
        let old = selected.annotation.bounds
        setBounds(old.offsetBy(dx: dx, dy: dy), of: selected.annotation, on: selected.page, previous: old)
    }

    func setBounds(_ bounds: CGRect, of annotation: PDFAnnotation, on page: PDFPage, previous: CGRect) {
        Annotations.resize(annotation, to: bounds)
        let resized = bounds.size != previous.size
        registerUndo(resized ? "Resize" : "Move") { $0.setBounds(previous, of: annotation, on: page, previous: bounds) }
        changed([page])
    }

    func setContents(_ contents: String, of annotation: PDFAnnotation, on page: PDFPage) {
        let previous = annotation.contents ?? ""
        annotation.contents = contents
        refit(annotation)
        registerUndo("Edit Text") { $0.setContents(previous, of: annotation, on: page) }
        changed([page])
    }

    /// Grows a text box to fit its contents, keeping its top-left corner fixed.
    private func refit(_ annotation: PDFAnnotation) {
        guard annotation.type == "FreeText", let font = annotation.font else { return }
        let size = ((annotation.contents ?? "") as NSString).boundingRect(
            with: CGSize(width: 400, height: 10_000), options: [.usesLineFragmentOrigin], attributes: [.font: font]).size
        var b = annotation.bounds
        b.origin.y = b.maxY - ceil(size.height) - 6
        b.size = CGSize(width: ceil(size.width) + 12, height: ceil(size.height) + 6)
        annotation.bounds = b
    }

    func commitNewText(_ text: String, at topLeft: CGPoint, on page: PDFPage) {
        let style = style(for: .text)
        let a = Annotations.freeText(text, at: topLeft, color: style.color, fontSize: style.width)
        add(a, to: page)
        select(SelectedAnnotation(annotation: a, page: page))
    }

    func commitNewNote(_ text: String, at point: CGPoint, on page: PDFPage) {
        let a = Annotations.note(text, at: point, color: style(for: .note).color)
        add(a, to: page)
        select(SelectedAnnotation(annotation: a, page: page))
    }

    func placeSignature(at point: CGPoint, on page: PDFPage) {
        guard let signature = SignatureStore.load() else { showSignaturePad = true; return }
        if let a = signature.annotation(center: point, width: 160, color: Palette.swatches[0]) {
            add(a, to: page)
            tool = .select
            select(SelectedAnnotation(annotation: a, page: page))
        }
    }

    func beginEditingSelected() {
        guard let selected, ["FreeText", "Text"].contains(selected.annotation.type ?? "") else { return }
        pdfView?.beginEditing(selected.annotation, on: selected.page)
    }

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
                             message: "Marked pages are flattened into images. Text under the marks is permanently removed, and text elsewhere on those pages stops being selectable.",
                             button: "Apply Redactions")
        else { return }
        select(nil)
        let replaced = PDFOps.pages(of: document).map { page in
            targets.contains(page) ? (PDFOps.rasterized(page) ?? page) : page
        }
        setPages(replaced, actionName: "Apply Redactions")
        showToast("Redacted \(targets.count) \(targets.count == 1 ? "page" : "pages")")
    }

    // MARK: Pages

    func setPages(_ pages: [PDFPage], actionName: String) {
        let previous = PDFOps.pages(of: document)
        let current = currentPageIndex
        select(nil)
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
        guard doomed.count < pageCount else { NSSound.beep(); showToast("A document needs at least one page"); return }
        let kept = PDFOps.pages(of: document).enumerated().filter { !doomed.contains($0.offset) }.map(\.element)
        selectedPages = []
        setPages(kept, actionName: doomed.count == 1 ? "Delete Page" : "Delete Pages")
        showToast(doomed.count == 1 ? "Page deleted" : "\(doomed.count) pages deleted")
    }

    func insertBlankPage(after index: Int? = nil) {
        var pages = PDFOps.pages(of: document)
        let at = min((index ?? targetPageIndices.last ?? currentPageIndex) + 1, pages.count)
        let size = pages.first?.bounds(for: .mediaBox).size ?? PDFOps.letter
        pages.insert(PDFOps.blankPage(size: size), at: at)
        setPages(pages, actionName: "Insert Page")
        goToPage(at)
        selectedPages = [at]
    }

    func movePages(from source: IndexSet, to destination: Int) {
        let moving = source.compactMap { document.page(at: $0) }
        setPages(PDFOps.moved(PDFOps.pages(of: document), from: source, to: destination), actionName: "Move Pages")
        selectedPages = Set(moving.map { document.index(for: $0) })
    }

    func insertPages(from url: URL) {
        guard let other = PDFDocument(url: url) else { Prompt.error("Could not open \(url.lastPathComponent).") ; return }
        var pages = PDFOps.pages(of: document)
        let at = min((targetPageIndices.last ?? currentPageIndex) + 1, pages.count)
        let inserted = PDFOps.copies(of: PDFOps.pages(of: other))
        pages.insert(contentsOf: inserted, at: at)
        setPages(pages, actionName: "Insert Pages")
        selectedPages = Set(at..<(at + inserted.count))
        showToast("Inserted \(inserted.count) \(inserted.count == 1 ? "page" : "pages")")
    }

    func addPageNumbers() {
        let added = PDFOps.addPageNumbers(to: document)
        registerUndo("Add Page Numbers") { editor in
            for (page, a) in added { page.removeAnnotation(a) }
            editor.changed()
        }
        changed()
        showToast("Page numbers added")
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

    func addBookmark(label: String? = nil, page index: Int? = nil) {
        let index = index ?? currentPageIndex
        guard let page = document.page(at: index) else { return }
        let hadRoot = document.outlineRoot != nil
        let root = document.outlineRoot ?? PDFOutline()
        if !hadRoot { document.outlineRoot = root }
        let item = PDFOutline()
        item.label = label ?? "Page \(index + 1)"
        item.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: .cropBox).maxY))
        root.insertChild(item, at: root.numberOfChildren)
        registerUndo("Add Bookmark") { editor in
            item.removeFromParent()
            if !hadRoot { editor.document.outlineRoot = nil }
            editor.changed()
        }
        changed()
        if label == nil { showToast("Bookmarked page \(index + 1)") }
    }

    func rename(_ item: PDFOutline, to label: String) {
        let previous = item.label ?? ""
        item.label = label
        registerUndo("Rename Bookmark") { $0.rename(item, to: previous) }
        changed()
    }

    func setAttributes(_ attributes: [AnyHashable: Any]) {
        let previous = document.documentAttributes ?? [:]
        document.documentAttributes = attributes
        registerUndo("Change Properties") { $0.setAttributes(previous) }
    }

    // MARK: Navigation and view

    func goToPage(_ index: Int) {
        guard let page = document.page(at: max(0, min(index, pageCount - 1))) else { return }
        pdfView?.go(to: PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: .cropBox).maxY)))
        currentPageIndex = document.index(for: page)
    }

    func go(to selection: PDFSelection) {
        pdfView?.setCurrentSelection(selection, animate: true)
        pdfView?.go(to: selection)
    }

    func zoomIn() { pdfView?.zoomIn(nil) }
    func zoomOut() { pdfView?.zoomOut(nil) }
    func zoom(to factor: CGFloat) { pdfView?.autoScales = false; pdfView?.scaleFactor = factor }
    func actualSize() { zoom(to: 1) }
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
        if mode == .pages { mode = .read }
        searchResults = document.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
        for result in searchResults { result.color = NSColor.systemYellow.withAlphaComponent(0.55) }
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
