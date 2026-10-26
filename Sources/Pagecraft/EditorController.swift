import Combine
import PDFKit
import PagecraftCore
import SwiftUI

/// The toolset shown in the toolbar. Each one brings its own floating tool bar, so no single
/// palette has to hold every tool.
enum EditorMode: String, CaseIterable, Identifiable {
    case read, annotate, draw, fillSign, measure, redact, scan, pages
    var id: String { rawValue }

    var title: String {
        switch self {
        case .read: "Read"
        case .annotate: "Annotate"
        case .draw: "Draw"
        case .fillSign: "Fill & Sign"
        case .measure: "Measure"
        case .redact: "Redact"
        case .scan: "Scan"
        case .pages: "Pages"
        }
    }

    var symbol: String {
        switch self {
        case .read: "book"
        case .annotate: "highlighter"
        case .draw: "pencil.and.scribble"
        case .fillSign: "signature"
        case .measure: "ruler"
        case .redact: "eye.slash"
        case .scan: "doc.viewfinder"
        case .pages: "square.grid.2x2"
        }
    }

    var subtitle: String {
        switch self {
        case .read: "Read without tools"
        case .annotate: "Highlight, notes, stamps and links"
        case .draw: "Pens and shapes"
        case .fillSign: "Fill forms, sign and add form fields"
        case .measure: "Distances and areas"
        case .redact: "Remove sensitive content"
        case .scan: "OCR, enhance scans, trim and split pages"
        case .pages: "Reorder, insert, rotate and delete pages"
        }
    }

    /// Toolsets that edit annotations on the page.
    var isMarkup: Bool { [.annotate, .draw, .fillSign, .measure, .redact].contains(self) }

    var tools: [Tool] {
        switch self {
        case .annotate: [.select, .highlight, .underline, .strikeout, .text, .note, .stamp, .image, .link, .eraser]
        case .draw: [.select, .pen, .marker, .rectangle, .oval, .line, .arrow, .doubleArrow, .polygon, .polyline, .eraser]
        case .fillSign: [.select, .text, .checkmark, .cross, .date, .signature, .stamp, .formText, .formCheckbox, .formRadio, .formChoice, .eraser]
        case .measure: [.select, .measureDistance, .measurePerimeter, .measureArea, .eraser]
        case .redact: [.select, .redact, .eraser]
        case .read, .scan, .pages: [.select, .crop, .snapshot]
        }
    }

    var defaultTool: Tool {
        switch self {
        case .annotate: .highlight
        case .draw: .pen
        case .fillSign: .text
        case .measure: .measureDistance
        case .redact: .redact
        default: .select
        }
    }

    /// The toolset a tool belongs to when the current one does not offer it.
    static func home(of tool: Tool) -> EditorMode? {
        [EditorMode.annotate, .draw, .fillSign, .measure, .redact].first { $0.tools.contains(tool) }
    }
}

enum Tool: String, CaseIterable, Identifiable {
    case select, highlight, underline, strikeout, pen, marker, text, note
    case rectangle, oval, line, arrow, doubleArrow, polygon, polyline
    case signature, checkmark, cross, date, stamp, image, link
    case formText, formCheckbox, formRadio, formChoice
    case measureDistance, measurePerimeter, measureArea
    case redact, eraser, crop, snapshot

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: "Select"
        case .highlight: "Highlight"
        case .underline: "Underline"
        case .strikeout: "Strike"
        case .pen: "Pen"
        case .marker: "Marker"
        case .text: "Text"
        case .note: "Note"
        case .rectangle: "Rectangle"
        case .oval: "Oval"
        case .line: "Line"
        case .arrow: "Arrow"
        case .doubleArrow: "Double Arrow"
        case .polygon: "Polygon"
        case .polyline: "Polyline"
        case .signature: "Sign"
        case .checkmark: "Checkmark"
        case .cross: "Cross"
        case .date: "Date"
        case .stamp: "Stamp"
        case .image: "Image"
        case .link: "Link"
        case .measureDistance: "Distance"
        case .measurePerimeter: "Perimeter"
        case .measureArea: "Area"
        case .formText: "Text Field"
        case .formCheckbox: "Checkbox"
        case .formRadio: "Radio Button"
        case .formChoice: "Drop-down"
        case .redact: "Redact"
        case .eraser: "Eraser"
        case .crop: "Crop"
        case .snapshot: "Snapshot"
        }
    }

    var formKind: Forms.FieldKind? {
        switch self {
        case .formText: .text
        case .formCheckbox: .checkbox
        case .formRadio: .radio
        case .formChoice: .choice
        default: nil
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .highlight: "highlighter"
        case .underline: "underline"
        case .strikeout: "strikethrough"
        case .pen: "pencil.tip"
        case .marker: "paintbrush.pointed"
        case .text: "textformat"
        case .note: "note.text"
        case .rectangle: "rectangle"
        case .oval: "circle"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .doubleArrow: "arrow.up.left.and.arrow.down.right"
        case .polygon: "pentagon"
        case .polyline: "point.topleft.down.to.point.bottomright.curvepath"
        case .signature: "signature"
        case .checkmark: "checkmark"
        case .cross: "xmark"
        case .date: "calendar"
        case .stamp: "seal"
        case .image: "photo"
        case .link: "link"
        case .measureDistance: "ruler"
        case .measurePerimeter: "point.3.connected.trianglepath.dotted"
        case .measureArea: "square.dashed"
        case .formText: "rectangle.and.pencil.and.ellipsis"
        case .formCheckbox: "checkmark.square"
        case .formRadio: "largecircle.fill.circle"
        case .formChoice: "filemenu.and.selection"
        case .redact: "rectangle.inset.filled"
        case .eraser: "eraser"
        case .crop: "crop"
        case .snapshot: "camera.viewfinder"
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
        case .marker: "m"
        case .text: "t"
        case .note: "n"
        case .rectangle: "r"
        case .oval: "o"
        case .line: "l"
        case .arrow: "a"
        case .signature: "g"
        case .stamp: "j"
        case .image: "i"
        case .redact: "x"
        case .eraser: "e"
        case .crop: "c"
        case .snapshot: "s"
        default: nil
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
        case .doubleArrow: .doubleArrow
        default: nil
        }
    }

    static let shapes: [Tool] = [.rectangle, .oval, .line, .arrow, .doubleArrow, .polygon, .polyline]
    static let pens: [Tool] = [.pen, .marker]
    static let fillAndSign: [Tool] = [.signature, .checkmark, .cross, .date, .formText, .formCheckbox, .formRadio, .formChoice]
    static let formFields: [Tool] = [.formText, .formCheckbox, .formRadio, .formChoice]
    static let measures: [Tool] = [.measureDistance, .measurePerimeter, .measureArea]

    var isShapeTool: Bool { Tool.shapes.contains(self) }
    var isPointTool: Bool { [.polygon, .polyline, .measurePerimeter, .measureArea].contains(self) }
    var closesShape: Bool { self == .polygon || self == .measureArea }
    /// Tools that drag out a rectangle or stroke.
    var drags: Bool { self == .pen || self == .marker || shape != nil || formKind != nil || [.redact, .crop, .snapshot, .link, .image, .measureDistance].contains(self) }
    /// Tools whose look the user can tune with the style controls.
    var isStyled: Bool { [.highlight, .underline, .strikeout, .pen, .marker, .text, .note, .checkmark, .cross, .date].contains(self) || isShapeTool || Tool.measures.contains(self) }
    var usesWidth: Bool { [.pen, .marker, .text, .date].contains(self) || isShapeTool || Tool.measures.contains(self) }
    var usesFill: Bool { self == .rectangle || self == .oval || self == .polygon }
    var usesDash: Bool { isShapeTool }
    /// Tools that are part of document editing rather than annotation.
    var isUtility: Bool { [.select, .crop, .snapshot].contains(self) }
}

struct ToolStyle: Equatable {
    var color: NSColor
    /// Stroke width, or font size for text tools.
    var width: CGFloat
    var opacity: CGFloat = 1
    var fill: NSColor?
    var dash: Annotations.LineStyle = .solid
    /// Text boxes only.
    var fontName: String?
    var bold = false
    var italic = false
    var alignment: NSTextAlignment = .left
}

/// Font families offered for text boxes; nil means the system font.
enum TextFonts {
    static let families: [String?] = [nil, "Helvetica Neue", "Avenir Next", "Georgia", "Times New Roman", "Baskerville",
                                      "Courier New", "Menlo", "Marker Felt", "Apple SD Gothic Neo", "Hiragino Sans"]
        .filter { $0 == nil || NSFontManager.shared.availableFontFamilies.contains($0!) }

    static func font(family: String?, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        var font = family.flatMap { NSFont(name: $0, size: size) ?? NSFontManager.shared.font(withFamily: $0, traits: [], weight: 5, size: size) }
            ?? NSFont.systemFont(ofSize: size)
        if bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    static func family(of font: NSFont?) -> String? {
        guard let font, !font.fontName.hasPrefix(".") else { return nil }
        return font.familyName
    }
}

/// What the Stamp tool places.
enum StampChoice: Equatable {
    case preset(StampPreset)
    case image(NSImage)
    case custom(String)
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
    case thumbnails = "Pages", bookmarks = "Bookmarks", outline = "Outline", annotations = "Annotations", search = "Search"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .thumbnails: "square.grid.2x2"
        case .bookmarks: "bookmark"
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
    @Published var styles: [Tool: ToolStyle] = {
        var styles: [Tool: ToolStyle] = [
            .highlight: ToolStyle(color: Palette.swatches[4], width: 0),
            .underline: ToolStyle(color: Palette.swatches[7], width: 0),
            .strikeout: ToolStyle(color: Palette.swatches[2], width: 0),
            .pen: ToolStyle(color: Palette.swatches[7], width: 2),
            .marker: ToolStyle(color: Palette.swatches[4], width: 14, opacity: 0.45),
            .text: ToolStyle(color: Palette.swatches[0], width: 14),
            .note: ToolStyle(color: Palette.swatches[4], width: 0),
            .checkmark: ToolStyle(color: Palette.swatches[7], width: 18),
            .cross: ToolStyle(color: Palette.swatches[2], width: 18),
            .date: ToolStyle(color: Palette.swatches[0], width: 12),
        ]
        for shape in Tool.shapes { styles[shape] = ToolStyle(color: Palette.swatches[2], width: 2) }
        for measure in Tool.measures { styles[measure] = ToolStyle(color: Palette.swatches[7], width: 1.5) }
        return styles
    }()
    @Published var stampChoice: StampChoice = .preset(StampPreset.all[0])
    @Published var activeSignatureID: UUID?
    @Published var signatureLibrary: [SavedSignature] = SignatureLibrary.load()
    @Published var pendingLink: (page: PDFPage, rect: CGRect)?
    @Published var showLinkSheet = false
    @Published var showFindRedact = false
    @Published var signaturePadInitials = false
    /// Annotation copied with ⌘C, pasted with ⌘V.
    var annotationClipboard: PDFAnnotation?
    @Published private(set) var lastMarkupTool: Tool = .highlight
    @Published private(set) var lastShape: Tool = .rectangle
    @Published private(set) var lastPen: Tool = .pen
    @Published private(set) var lastFillAndSign: Tool = .signature
    @Published private(set) var lastMeasure: Tool = .measureDistance
    @Published var measureScale = Measure.Scale()
    @Published var showMeasureScale = false
    @Published var selected: SelectedAnnotation? { didSet { overlayTick += 1 } }
    @Published var textSelectionActive = false
    /// Bumped whenever on-screen geometry changes so overlays re-measure.
    @Published private(set) var overlayTick = 0

    @Published var layout: PageLayout = Preferences.defaultLayout { didSet { applyLayout() } }
    @Published var theme: ReadingTheme = Preferences.defaultTheme { didSet { applyTheme() } }
    /// Second document shown beside this one.
    @Published var split: SplitState? { didSet { splitChanged(from: oldValue) } }
    /// Page to return to after a jump through a link, the outline or search.
    @Published var backTarget: Int?
    @Published private var hudAwake = true
    @Published var hudHovered = false
    /// Page under the pointer, for the bookmark ribbon.
    @Published var hoverPage: PDFPage?
    @Published var searchHistory: [String] = UserDefaults.standard.stringArray(forKey: "searchHistory") ?? []
    /// Personal bookmarks (page indices), kept per file outside the PDF.
    @Published private(set) var bookmarks: [Int] = []
    /// Where to put a freshly created PDF view (for example after split view toggles).
    var pendingDestination: PDFDestination?
    private var hudTimer: DispatchWorkItem?
    private var backTimer: DispatchWorkItem?
    private var splitSync: ScrollSync?
    @Published var sidebarTab: SidebarTab = .thumbnails
    @Published var selectedPages: Set<Int> = []
    @Published private(set) var currentPageIndex = 0
    @Published private(set) var revision = 0
    @Published private(set) var scale: CGFloat = 1
    @Published var searchText = ""
    @Published private(set) var searchResults: [PDFSelection] = []
    @Published var searchIndex = 0
    @Published var searchMatchCase = false { didSet { if !searchResults.isEmpty { search() } } }
    @Published var searchWholeWords = false { didSet { if !searchResults.isEmpty { search() } } }
    @Published var showSignaturePad = false
    @Published var showProperties = false
    @Published var showPasswordSheet = false
    @Published var showReduceSize = false
    @Published var showExportImages = false
    @Published var showPageSize = false
    @Published var showSplit = false
    @Published var headerFooterPreset: HeaderFooterPreset?
    /// Rectangle being drawn with the Crop tool, in page space.
    @Published var cropDraft: (page: PDFPage, rect: CGRect)? { didSet { overlayTick += 1 } }
    /// Message for a blocking progress overlay, while a long operation runs.
    @Published var busy: String?
    @Published var needsPassword: Bool
    @Published var toast: Toast?
    @Published var focusPageField = false

    private var thumbnailCache: [ObjectIdentifier: [String: NSImage]] = [:]
    private var observers: [NSObjectProtocol] = []

    init(file: PDFFile) {
        self.file = file
        needsPassword = file.pdf.isLocked
    }

    var pageCount: Int { document.pageCount }
    var redactionCount: Int {
        PDFOps.pages(of: document).reduce(0) { $0 + $1.annotations.filter(Annotations.isRedaction).count }
    }

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

    var currentFileSize: Int? {
        fileURL.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? document.dataRepresentation()?.count
    }

    var isPasswordProtected: Bool { file.userPassword != nil }

    // MARK: View wiring

    func attach(_ view: EditorPDFView) {
        pdfView = view
        view.editor = self
        view.document = document
        applyLayout()
        applyTheme()
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        // PDFView posts these while AppKit is laying out. Publishing synchronously would invalidate
        // SwiftUI in the middle of that pass and can loop, so state is updated on the next turn.
        observers = [
            center.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleViewSync() }
            },
            center.addObserver(forName: .PDFViewScaleChanged, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleViewSync() }
            },
            center.addObserver(forName: .PDFViewSelectionChanged, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleViewSync() }
            },
            center.addObserver(forName: .PDFViewChangedHistory, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.historyChanged() }
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
                    self?.pdfView?.commitInline()
                    self?.scheduleViewSync()
                }
            })
        }
    }

    private var viewSyncPending = false

    // MARK: Page indicator, history and bookmarks

    var hudVisible: Bool {
        switch Preferences.pageIndicator {
        case .always: true
        case .never: false
        case .automatic: hudAwake || hudHovered || mode == .pages
        }
    }

    /// Shows the page indicator, then fades it after a pause.
    func pokeHUD() {
        if !hudAwake { hudAwake = true }
        hudTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hudAwake = false }
        hudTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
        objectWillChange.send()
    }

    private var historyFrom: Int?

    private func historyChanged() {
        // The page we were on before the jump; currentPageIndex has not been synced yet.
        let from = currentPageIndex
        DispatchQueue.main.async { [weak self] in
            guard let self, let view = self.pdfView, view.canGoBack, let page = view.currentPage else { return }
            let to = self.document.index(for: page)
            guard abs(to - from) > 1 else { return }
            self.backTarget = from
            self.backTimer?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.backTarget = nil }
            self.backTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
        }
    }

    func returnToBackTarget() {
        guard let target = backTarget else { return }
        backTarget = nil
        if let view = pdfView, view.canGoBack { view.goBack(nil) } else { goToPage(target) }
    }

    private var bookmarkKey: String? { fileURL.map { "bookmarks:" + $0.standardizedFileURL.resolvingSymlinksInPath().path } }

    func loadBookmarks() {
        guard let key = bookmarkKey else { return }
        bookmarks = (UserDefaults.standard.array(forKey: key) as? [Int] ?? []).filter { $0 < pageCount }.sorted()
    }

    func isBookmarked(_ index: Int) -> Bool { bookmarks.contains(index) }

    func toggleBookmark(_ index: Int? = nil) {
        let index = index ?? currentPageIndex
        if let i = bookmarks.firstIndex(of: index) { bookmarks.remove(at: i) } else { bookmarks = (bookmarks + [index]).sorted() }
        if let key = bookmarkKey { UserDefaults.standard.set(bookmarks, forKey: key) }
        showToast(isBookmarked(index) ? "Bookmarked page \(index + 1)" : "Bookmark removed")
    }

    // MARK: Split view

    func openSplit(vertical: Bool = false) {
        split = SplitState(vertical: vertical)
    }

    func closeSplit() { split = nil }

    func chooseSplitDocument() {
        guard let url = Prompt.open([.pdf], multiple: false, title: "Open in Split View").first else { return }
        openSplitDocument(url)
    }

    func openSplitDocument(_ url: URL) {
        guard let doc = PDFDocument(url: url) else { Prompt.error("Could not open \(url.lastPathComponent).") ; return }
        if doc.isLocked {
            guard let password = Prompt.text("Password Required", message: "“\(url.lastPathComponent)” is password protected.", secure: true),
                  doc.unlock(withPassword: password) else { return }
        }
        var state = split ?? SplitState(vertical: false)
        state.document = doc
        state.title = url.deletingPathExtension().lastPathComponent
        split = state
    }

    /// Remembers where the main view is so a re-created PDF view can return there.
    private func splitChanged(from old: SplitState?) {
        let layoutChanged = (old == nil) != (split == nil) || old?.vertical != split?.vertical || old?.swapped != split?.swapped
        if layoutChanged, let view = pdfView, let destination = view.currentDestination { pendingDestination = destination }
        if old?.document !== split?.document { splitSync = nil }
        splitSync?.enabled = split?.sync ?? false
    }

    func attachSplitView(_ view: PDFView) {
        let sync = ScrollSync()
        sync.enabled = split?.sync ?? true
        if let main = pdfView { sync.attach(main, isLeft: true) }
        sync.attach(view, isLeft: false)
        splitSync = sync
    }

    /// Coalesces PDFView geometry and page changes into one SwiftUI update after the current layout pass.
    private func scheduleViewSync() {
        guard !viewSyncPending else { return }
        viewSyncPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.viewSyncPending = false
            guard let view = self.pdfView else { return }
            if let page = view.currentPage {
                let index = self.document.index(for: page)
                if index != self.currentPageIndex { self.currentPageIndex = index }
            }
            if abs(view.scaleFactor - self.scale) > 0.001 { self.scale = view.scaleFactor }
            self.pokeHUD()
            if self.textSelectionActive, (view.currentSelection?.string ?? "").isEmpty { self.textSelectionActive = false }
            if self.selected != nil || self.textSelectionActive || self.cropDraft != nil || self.hoverPage != nil { self.overlayTick += 1 }
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
            for page in pages { thumbnailCache[ObjectIdentifier(page)] = nil }
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
        let key = "\(page.rotation)-\(bucket)"
        if let cached = thumbnailCache[ObjectIdentifier(page)]?[key] { return cached }
        let image = page.thumbnail(of: CGSize(width: bucket, height: bucket), for: .cropBox)
        thumbnailCache[ObjectIdentifier(page), default: [:]][key] = image
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

    var cropFrame: CGRect? {
        _ = overlayTick
        return cropDraft.flatMap { viewRect($0.rect, on: $0.page) }
    }

    var hoverPageFrame: CGRect? {
        _ = overlayTick
        return hoverPage.flatMap { viewRect($0.bounds(for: .cropBox), on: $0) }
    }

    var textSelectionFrame: CGRect? {
        _ = overlayTick
        guard textSelectionActive, let selection = pdfView?.currentSelection, let page = selection.pages.first else { return nil }
        return viewRect(selection.bounds(for: page), on: page)
    }

    // MARK: Modes and tools

    private var lastTool: [EditorMode: Tool] = [:]

    private func modeChanged(from old: EditorMode) {
        guard mode != old else { return }
        select(nil)
        pdfView?.commitInline()
        if old.isMarkup { lastTool[old] = tool }
        if !mode.tools.contains(tool) || tool == .select {
            tool = lastTool[mode] ?? mode.defaultTool
        }
        if mode == .pages { selectedPages = [currentPageIndex] }
    }

    private func toolChanged() {
        if tool != .crop { cropDraft = nil }
        pdfView?.cancelPointTool()
        if !tool.isUtility { lastMarkupTool = tool }
        if tool.isShapeTool { lastShape = tool }
        if Tool.pens.contains(tool) { lastPen = tool }
        if Tool.fillAndSign.contains(tool) { lastFillAndSign = tool }
        if Tool.measures.contains(tool) { lastMeasure = tool }
        if !mode.tools.contains(tool), let home = EditorMode.home(of: tool) { mode = home }
        if tool != .select { select(nil) }
        if let type = tool.markupType, let selection = pdfView?.currentSelection, !(selection.string ?? "").isEmpty {
            applyMarkup(type, to: selection)
        }
        if tool == .signature, signatureLibrary.filter({ !$0.isInitials }).isEmpty {
            signaturePadInitials = false
            showSignaturePad = true
        }
        if let view = pdfView { view.window?.invalidateCursorRects(for: view) }
    }

    func style(for tool: Tool) -> ToolStyle {
        styles[tool] ?? ToolStyle(color: Palette.swatches[0], width: 2)
    }

    /// Colour for a new annotation made with `tool`, including its opacity.
    func strokeColor(for tool: Tool) -> NSColor {
        let style = style(for: tool)
        return style.color.withAlphaComponent(style.opacity)
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

    var activeOpacity: CGFloat {
        if let selected {
            let a = selected.annotation
            return a.type == "FreeText" ? (a.fontColor?.alphaComponent ?? 1) : a.type == "Highlight" ? 1 : a.color.alphaComponent
        }
        return style(for: tool).opacity
    }

    var activeFill: NSColor? {
        if let selected {
            if selected.annotation.type == "FreeText" { return selected.annotation.color.alphaComponent > 0.01 ? selected.annotation.color : nil }
            return selected.annotation.interiorColor
        }
        return style(for: tool).fill
    }

    var activeDash: Annotations.LineStyle {
        if let selected { return Annotations.lineStyle(of: selected.annotation) }
        return style(for: tool).dash
    }

    private var selectedType: String { selected?.annotation.type ?? "" }
    var widthApplies: Bool { selected.map { _ in ["FreeText", "Ink", "Square", "Circle", "Line"].contains(selectedType) } ?? tool.usesWidth }
    var widthIsFontSize: Bool { selected.map { _ in selectedType == "FreeText" } ?? [.text, .date].contains(tool) }
    var fillApplies: Bool { selected.map { _ in ["Square", "Circle", "FreeText"].contains(selectedType) } ?? (tool.usesFill || tool == .text) }
    var textApplies: Bool { selected.map { _ in selectedType == "FreeText" } ?? (tool == .text) }

    var activeFontFamily: String? {
        if let selected { return TextFonts.family(of: selected.annotation.font) }
        return style(for: .text).fontName
    }

    var activeBold: Bool {
        if let selected { return selected.annotation.font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false }
        return style(for: .text).bold
    }

    var activeItalic: Bool {
        if let selected { return selected.annotation.font.map { NSFontManager.shared.traits(of: $0).contains(.italicFontMask) } ?? false }
        return style(for: .text).italic
    }

    var activeAlignment: NSTextAlignment {
        selected?.annotation.alignment ?? style(for: .text).alignment
    }

    func setTextFormat(family: String?? = nil, bold: Bool? = nil, italic: Bool? = nil, alignment: NSTextAlignment? = nil) {
        let newFamily = family ?? activeFontFamily
        let newBold = bold ?? activeBold, newItalic = italic ?? activeItalic
        if let selected, selected.annotation.type == "FreeText" {
            restyle(selected, name: "Format Text") { a in
                a.font = TextFonts.font(family: newFamily, size: a.font?.pointSize ?? 14, bold: newBold, italic: newItalic)
                if let alignment { a.alignment = alignment }
                self.refit(a)
            }
        }
        if selected == nil || tool == .text {
            var style = style(for: .text)
            style.fontName = newFamily
            style.bold = newBold
            style.italic = newItalic
            if let alignment { style.alignment = alignment }
            styles[.text] = style
        }
    }
    var dashApplies: Bool { selected.map { _ in ["Ink", "Square", "Circle", "Line"].contains(selectedType) } ?? tool.usesDash }
    var opacityApplies: Bool {
        if let selected { return !["Highlight", "Underline", "StrikeOut", "Text"].contains(selectedType) && !Annotations.isRedaction(selected.annotation) }
        return tool.isStyled && tool.markupType == nil && tool != .note
    }

    func setColor(_ color: NSColor) {
        let color = Palette.srgb(color)
        if let selected {
            let opacity = activeOpacity
            restyle(selected, name: "Change Color") { Annotations.setColor(color.withAlphaComponent(selected.annotation.type == "Highlight" ? 1 : opacity), of: $0) }
        }
        if tool.isStyled { styles[tool, default: style(for: tool)].color = color }
        if selected == nil, tool == .select { styles[.highlight]?.color = color }
    }

    func setWidth(_ width: CGFloat) {
        if let selected {
            restyle(selected, name: "Change Width") { a in
                if a.type == "FreeText" {
                    a.font = NSFont.systemFont(ofSize: width)
                    self.refit(a)
                } else {
                    let style = Annotations.lineStyle(of: a)
                    let border = PDFBorder()
                    border.lineWidth = width
                    a.border = border
                    Annotations.setLineStyle(style, of: a)
                }
            }
        }
        if tool.usesWidth { styles[tool, default: style(for: tool)].width = width }
    }

    func setOpacity(_ opacity: CGFloat) {
        if let selected {
            restyle(selected, name: "Change Opacity") { a in
                if a.type == "FreeText" { a.fontColor = a.fontColor?.withAlphaComponent(opacity) }
                else { a.color = a.color.withAlphaComponent(opacity) }
                if let fill = a.interiorColor { a.interiorColor = fill.withAlphaComponent(opacity) }
            }
        }
        if tool.isStyled { styles[tool, default: style(for: tool)].opacity = opacity }
    }

    func setFill(_ fill: NSColor?) {
        let fill = fill.map(Palette.srgb)
        if let selected {
            restyle(selected, name: "Change Fill") { a in
                if a.type == "FreeText" { a.color = fill ?? .clear } else { Annotations.setFill(fill?.withAlphaComponent(self.activeOpacity), of: a) }
            }
        }
        if tool.usesFill || tool == .text { styles[tool, default: style(for: tool)].fill = fill }
    }

    func setDash(_ dash: Annotations.LineStyle) {
        if let selected { restyle(selected, name: "Change Line Style") { Annotations.setLineStyle(dash, of: $0) } }
        if tool.usesDash { styles[tool, default: style(for: tool)].dash = dash }
    }

    /// Everything the style controls can change, captured for undo.
    private struct StyleSnapshot {
        let color: NSColor, fontColor: NSColor?, font: NSFont?, interior: NSColor?, border: PDFBorder?, bounds: CGRect
        init(_ a: PDFAnnotation) {
            color = a.color; fontColor = a.fontColor; font = a.font; interior = a.interiorColor; bounds = a.bounds
            border = a.border?.copy() as? PDFBorder
        }
        func apply(to a: PDFAnnotation) {
            a.color = color; a.fontColor = fontColor; a.font = font; a.interiorColor = interior; a.border = border; a.bounds = bounds
        }
    }

    private func restyle(_ target: SelectedAnnotation, name: String, _ change: (PDFAnnotation) -> Void) {
        let before = StyleSnapshot(target.annotation)
        change(target.annotation)
        let after = StyleSnapshot(target.annotation)
        registerStyleUndo(target, name: name, undo: before, redo: after)
        changed([target.page])
        objectWillChange.send()
    }

    private func registerStyleUndo(_ target: SelectedAnnotation, name: String, undo: StyleSnapshot, redo: StyleSnapshot) {
        registerUndo(name) { editor in
            undo.apply(to: target.annotation)
            editor.registerStyleUndo(target, name: name, undo: redo, redo: undo)
            editor.changed([target.page])
        }
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

    /// Name stamped on new annotations, shown in other PDF apps as the author.
    static var authorName: String {
        let saved = UserDefaults.standard.string(forKey: "authorName") ?? ""
        return saved.isEmpty ? NSFullUserName() : saved
    }

    func add(_ annotation: PDFAnnotation, to page: PDFPage) {
        if annotation.userName == nil || annotation.userName?.isEmpty == true { annotation.userName = Self.authorName }
        if annotation.modificationDate == nil { annotation.modificationDate = Date() }
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
        let a = Annotations.freeText(text, at: topLeft, color: style.color.withAlphaComponent(style.opacity), fontSize: style.width)
        a.font = TextFonts.font(family: style.fontName, size: style.width, bold: style.bold, italic: style.italic)
        a.alignment = style.alignment
        if let fill = style.fill { a.color = fill }
        refit(a)
        add(a, to: page)
        select(SelectedAnnotation(annotation: a, page: page))
    }

    func commitNewNote(_ text: String, at point: CGPoint, on page: PDFPage) {
        let a = Annotations.note(text, at: point, color: style(for: .note).color)
        add(a, to: page)
        select(SelectedAnnotation(annotation: a, page: page))
    }

    var activeSignature: SavedSignature? {
        signatureLibrary.first { $0.id == activeSignatureID } ?? signatureLibrary.first { !$0.isInitials }
    }

    func addSignature(_ signature: SavedSignature) {
        signatureLibrary.append(signature)
        SignatureLibrary.save(signatureLibrary)
        activeSignatureID = signature.id
    }

    func deleteSignature(_ signature: SavedSignature) {
        signatureLibrary.removeAll { $0.id == signature.id }
        SignatureLibrary.save(signatureLibrary)
        if activeSignatureID == signature.id { activeSignatureID = nil }
    }

    func placeSignature(at point: CGPoint, on page: PDFPage) {
        guard let signature = activeSignature else { showSignaturePad = true; return }
        let width: CGFloat = signature.isInitials ? 70 : 170
        if let a = signature.annotation(center: point, width: width, color: Palette.swatches[0]) {
            add(a, to: page)
            tool = .select
            select(SelectedAnnotation(annotation: a, page: page))
        }
    }

    /// Checkmark, cross and date: small text placed with one click.
    func placeMark(_ tool: Tool, at point: CGPoint, on page: PDFPage) {
        let style = style(for: tool)
        let text: String
        switch tool {
        case .checkmark: text = "✓"
        case .cross: text = "✗"
        default: text = Date().formatted(date: .numeric, time: .omitted)
        }
        let a = Annotations.freeText(text, at: .zero, color: strokeColor(for: tool), fontSize: style.width)
        a.bounds.origin = CGPoint(x: point.x - a.bounds.width / 2, y: point.y - a.bounds.height / 2)
        add(a, to: page)
        select(SelectedAnnotation(annotation: a, page: page))
    }

    func placeStamp(at point: CGPoint, on page: PDFPage) {
        let a: PDFAnnotation
        let subtitle = "\(Self.authorName) · \(Date().formatted(date: .abbreviated, time: .shortened))"
        switch stampChoice {
        case let .preset(preset): a = TextStampAnnotation.make(title: preset.title, subtitle: subtitle, tint: preset.color, at: point)
        case let .custom(text): a = TextStampAnnotation.make(title: text.uppercased(), subtitle: subtitle, tint: Palette.swatches[7], at: point)
        case let .image(image):
            let width = min(180, image.size.width), height = width * image.size.height / max(image.size.width, 1)
            a = ImageAnnotation(image: image, bounds: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height))
        }
        add(a, to: page)
        select(SelectedAnnotation(annotation: a, page: page))
    }

    func chooseImageStamp() {
        guard let url = Prompt.open([.image], multiple: false, title: "Choose an Image Stamp").first, let image = NSImage(contentsOf: url) else { return }
        stampChoice = .image(image)
        tool = .stamp
    }

    func chooseCustomStamp() {
        guard let text = Prompt.text("Custom Stamp", message: "Text for the stamp:"), !text.isEmpty else { return }
        stampChoice = .custom(text)
        tool = .stamp
    }

    /// Inserts an image fitted into `rect`, or a default size at `rect.origin` for a click.
    func placeImage(in rect: CGRect, on page: PDFPage) {
        guard let url = Prompt.open([.image], multiple: false, title: "Choose an Image").first, let image = NSImage(contentsOf: url) else { return }
        insertImage(image, in: rect, on: page)
    }

    func insertImage(_ image: NSImage, in rect: CGRect, on page: PDFPage) {
        let aspect = image.size.width / max(image.size.height, 1)
        var frame = rect
        if rect.width < 10 || rect.height < 10 {
            let width = min(240, image.size.width)
            frame = CGRect(x: rect.midX - width / 2, y: rect.midY - width / aspect / 2, width: width, height: width / aspect)
        } else if rect.width / rect.height > aspect {
            let width = rect.height * aspect
            frame = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
        } else {
            let height = rect.width / aspect
            frame = CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        }
        let a = ImageAnnotation(image: image, bounds: frame)
        add(a, to: page)
        tool = .select
        select(SelectedAnnotation(annotation: a, page: page))
    }

    func commitPolyline(_ points: [CGPoint], closed: Bool, on page: PDFPage) {
        let style = style(for: tool)
        guard let a = Annotations.polyline(points, closed: closed, color: strokeColor(for: tool), lineWidth: style.width) else { return }
        Annotations.setLineStyle(style.dash, of: a)
        if tool == .polygon, let fill = style.fill { a.interiorColor = fill }
        add(a, to: page)
        switch tool {
        case .measurePerimeter:
            addMeasureLabel(measureScale.format(length: Measure.perimeter(points, closed: false)), at: points[points.count / 2], on: page)
        case .measureArea:
            let center = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count), y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
            addMeasureLabel(measureScale.format(area: Measure.area(points)), at: center, on: page)
        default: break
        }
        undoManager?.setActionName(Tool.measures.contains(tool) ? "Measure" : tool.label)
    }

    func commitDistance(from start: CGPoint, to end: CGPoint, on page: PDFPage) {
        let style = style(for: .measureDistance)
        let line = Annotations.shape(.doubleArrow, from: start, to: end, color: strokeColor(for: .measureDistance), lineWidth: style.width)
        add(line, to: page)
        addMeasureLabel(measureScale.format(length: Measure.distance(start, end)),
                        at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 + 9), on: page)
        undoManager?.setActionName("Measure")
    }

    private func addMeasureLabel(_ text: String, at point: CGPoint, on page: PDFPage) {
        let label = Annotations.freeText(text, at: .zero, color: style(for: tool).color, fontSize: 10)
        label.color = NSColor.white.withAlphaComponent(0.85)
        label.bounds.origin = CGPoint(x: point.x - label.bounds.width / 2, y: point.y - label.bounds.height / 2)
        add(label, to: page)
    }

    func requestLink(in rect: CGRect, on page: PDFPage) {
        pendingLink = (page, rect)
        showLinkSheet = true
    }

    func commitLink(url: URL?, pageNumber: Int?) {
        guard let (page, rect) = pendingLink else { return }
        pendingLink = nil
        let a: PDFAnnotation
        if let url { a = Annotations.link(bounds: rect, url: url) }
        else if let pageNumber, let target = document.page(at: pageNumber - 1) { a = Annotations.link(bounds: rect, to: target) }
        else { return }
        add(a, to: page)
        showToast("Link added")
    }

    func snapshot(_ rect: CGRect, on page: PDFPage) {
        guard let cg = PDFOps.renderImage(page, scale: 3) else { return }
        let box = page.bounds(for: .mediaBox)
        let crop = CGRect(x: (rect.minX - box.minX) * 3, y: (box.maxY - rect.maxY) * 3, width: rect.width * 3, height: rect.height * 3)
        guard page.rotation == 0, let piece = cg.cropping(to: crop) else { showToast("Snapshots of rotated pages are not supported"); return }
        let image = NSImage(cgImage: piece, size: rect.size)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        showToast("Area copied as an image")
    }

    // MARK: Clipboard and stacking

    func copySelectedAnnotation(cut: Bool = false) {
        guard let selected, let copy = selected.annotation.copy() as? PDFAnnotation else { return }
        if let paths = selected.annotation.paths, copy.paths?.isEmpty ?? true { paths.forEach { copy.add($0.copy() as! NSBezierPath) } }
        annotationClipboard = copy
        if cut { remove(selected.annotation, from: selected.page) }
    }

    /// Pastes the copied annotation, or an image from the system clipboard, onto the current page.
    func paste() -> Bool {
        guard let page = pdfView?.currentPage else { return false }
        if let source = annotationClipboard, let copy = Annotations.duplicate(source) {
            if !page.bounds(for: .cropBox).intersects(copy.bounds) {
                let box = page.bounds(for: .cropBox)
                copy.bounds.origin = CGPoint(x: box.midX - copy.bounds.width / 2, y: box.midY - copy.bounds.height / 2)
            }
            annotationClipboard = copy
            add(copy, to: page)
            select(SelectedAnnotation(annotation: copy, page: page))
            return true
        }
        if let image = NSImage(pasteboard: .general), NSPasteboard.general.data(forType: .string) == nil {
            let box = page.bounds(for: .cropBox)
            insertImage(image, in: CGRect(x: box.midX, y: box.midY, width: 0, height: 0), on: page)
            return true
        }
        return false
    }

    func replaceSelectedImage() {
        guard let selected, let image = selected.annotation as? ImageAnnotation,
              let url = Prompt.open([.image], multiple: false, title: "Replace Image").first, let replacement = NSImage(contentsOf: url) else { return }
        let previous = image.image
        setImage(replacement, of: image, on: selected.page, previous: previous)
    }

    private func setImage(_ new: NSImage?, of annotation: ImageAnnotation, on page: PDFPage, previous: NSImage?) {
        annotation.image = new
        registerUndo("Replace Image") { $0.setImage(previous, of: annotation, on: page, previous: new) }
        changed([page])
    }

    func saveSelectedImage() {
        guard let image = (selected?.annotation as? ImageAnnotation)?.image,
              let url = Prompt.save(.png, name: "Image.png", title: "Save Image"),
              let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        do { try png.write(to: url); showToast("Image saved", url: url) } catch { Prompt.error(error.localizedDescription) }
    }

    func reorderSelected(toFront: Bool) {
        guard let selected else { return }
        let before = selected.page.annotations
        Annotations.reorder(selected.annotation, on: selected.page, toFront: toFront)
        registerUndo(toFront ? "Bring to Front" : "Send to Back") { editor in
            before.forEach(selected.page.removeAnnotation)
            before.forEach(selected.page.addAnnotation)
            editor.changed([selected.page])
        }
        changed([selected.page])
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

    @Published var redactionStyle: Annotations.RedactionStyle = .blackout

    func markForRedaction(_ queries: [String], matchCase: Bool, wholeWords: Bool, style: Annotations.RedactionStyle) {
        let results = queries.flatMap { Search.find($0, in: document, matchCase: matchCase, wholeWords: wholeWords) }
        let marks = Search.redactionMarks(for: results, style: style)
        for (page, annotation) in marks { add(annotation, to: page) }
        undoManager?.setActionName("Mark for Redaction")
        if mode != .redact { mode = .redact }
        if let first = results.first { go(to: first) }
        showToast("Marked \(results.count) \(results.count == 1 ? "match" : "matches") — review, then Apply Redactions")
    }

    // MARK: Forms

    func addFormField(_ kind: Forms.FieldKind, in rect: CGRect, on page: PDFPage) {
        let defaultSize: CGSize = kind == .text ? CGSize(width: 180, height: 22) : kind == .choice ? CGSize(width: 140, height: 22) : CGSize(width: 16, height: 16)
        let frame = rect.width < 6 || rect.height < 6 ? CGRect(origin: CGPoint(x: rect.minX, y: rect.minY - defaultSize.height / 2), size: defaultSize) : rect
        let field = Forms.field(kind, in: frame, document: document)
        add(field, to: page)
        select(SelectedAnnotation(annotation: field, page: page))
        showToast("\(kind.rawValue) “\(field.fieldName ?? "")” added — switch to Read to fill it in")
    }

    func resetForm() {
        let previous = Forms.reset(document)
        guard !previous.isEmpty else { showToast("This document has no form fields"); return }
        registerUndo("Clear Form") { editor in
            previous.forEach { $0.restore() }
            editor.changed()
        }
        changed()
        PDFOps.pages(of: document).forEach { pdfView?.annotationsChanged(on: $0) }
        showToast("Form cleared")
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
        let inserted = PDFOps.adopt(other)
        pages.insert(contentsOf: inserted, at: at)
        setPages(pages, actionName: "Insert Pages")
        selectedPages = Set(at..<(at + inserted.count))
        showToast("Inserted \(inserted.count) \(inserted.count == 1 ? "page" : "pages")")
    }

    // MARK: Crop, resize and generated pages

    func beginCrop() {
        if mode == .pages { mode = .read }
        tool = .crop
    }

    func applyCrop(toAll: Bool) {
        guard let draft = cropDraft, draft.rect.width > 10, draft.rect.height > 10 else { return }
        let pages = toAll ? PDFOps.pages(of: document) : selectedPages.count > 1 ? targetPageIndices.compactMap { document.page(at: $0) } : [draft.page]
        setCropBoxes(pages.map { ($0, draft.rect.intersection($0.bounds(for: .mediaBox))) }, actionName: "Crop")
        cropDraft = nil
        tool = .select
        showToast("Cropped \(pages.count) \(pages.count == 1 ? "page" : "pages")")
    }

    func autoCrop(_ indices: [Int]? = nil) {
        let pages = (indices ?? targetPageIndices).compactMap { document.page(at: $0) }
        let boxes = pages.compactMap { page -> (PDFPage, CGRect)? in
            guard let content = PageOps.contentBounds(page) else { return nil }
            return (page, content.insetBy(dx: -12, dy: -12).intersection(page.bounds(for: .mediaBox)))
        }
        guard !boxes.isEmpty else { showToast("Nothing to trim"); return }
        setCropBoxes(boxes, actionName: "Clear Margins")
        showToast("Trimmed margins on \(boxes.count) \(boxes.count == 1 ? "page" : "pages")")
    }

    func resetCrop(_ indices: [Int]? = nil) {
        let pages = (indices ?? targetPageIndices).compactMap { document.page(at: $0) }
        setCropBoxes(pages.map { ($0, $0.bounds(for: .mediaBox)) }, actionName: "Reset Crop")
    }

    private func setCropBoxes(_ boxes: [(PDFPage, CGRect)], actionName: String) {
        let previous = boxes.map { ($0.0, $0.0.bounds(for: .cropBox)) }
        for (page, rect) in boxes { page.setBounds(rect, for: .cropBox) }
        registerUndo(actionName) { $0.setCropBoxes(previous, actionName: actionName) }
        changed(boxes.map(\.0))
        pdfView?.layoutDocumentView()
    }

    enum Orientation: String, CaseIterable, Identifiable {
        case portrait = "Portrait", landscape = "Landscape", match = "Match Each Page"
        var id: String { rawValue }
    }

    func resizePages(_ indices: [Int], to size: CGSize, orientation: Orientation, scaleToFit: Bool) {
        let targets = Set(indices)
        let pages = PDFOps.pages(of: document).enumerated().map { index, page -> PDFPage in
            guard targets.contains(index) else { return page }
            let shown = PageOps.displaySize(page)
            let landscape = orientation == .landscape || (orientation == .match && shown.width > shown.height)
            let target = landscape ? CGSize(width: max(size.width, size.height), height: min(size.width, size.height))
                                   : CGSize(width: min(size.width, size.height), height: max(size.width, size.height))
            return PageOps.redrawn(page, size: target, scaleToFit: scaleToFit) ?? page
        }
        setPages(pages, actionName: "Page Size")
        showToast("Resized \(targets.count) \(targets.count == 1 ? "page" : "pages")")
    }

    private func insert(_ newPages: [PDFPage], actionName: String) {
        guard !newPages.isEmpty else { return }
        var pages = PDFOps.pages(of: document)
        let at = min((targetPageIndices.last ?? currentPageIndex) + 1, pages.count)
        pages.insert(contentsOf: newPages, at: at)
        setPages(pages, actionName: actionName)
        selectedPages = Set(at..<(at + newPages.count))
        goToPage(at)
        showToast("Inserted \(newPages.count) \(newPages.count == 1 ? "page" : "pages")")
    }

    func insertImages() {
        let urls = Prompt.open([.image], multiple: true, title: "Insert Pages from Images")
        let pages = urls.compactMap { NSImage(contentsOf: $0).flatMap(PDFPage.init(image:)) }
        insert(pages, actionName: "Insert Images")
    }

    func insertFromClipboard() {
        let pages = PageOps.pages(from: .general)
        guard !pages.isEmpty else { showToast("The clipboard has no PDF or image"); return }
        insert(pages, actionName: "Paste Pages")
    }

    func duplicatePages() {
        let indices = targetPageIndices
        var pages = PDFOps.pages(of: document)
        let copies = PDFOps.copies(of: indices.compactMap { document.page(at: $0) })
        let at = (indices.last ?? currentPageIndex) + 1
        pages.insert(contentsOf: copies, at: min(at, pages.count))
        setPages(pages, actionName: "Duplicate Pages")
        selectedPages = Set(at..<(at + copies.count))
    }

    func reversePages() {
        let indices = selectedPages.count > 1 ? selectedPages.sorted() : Array(0..<pageCount)
        var pages = PDFOps.pages(of: document)
        let reversed = indices.map { pages[$0] }.reversed()
        for (slot, page) in zip(indices, reversed) { pages[slot] = page }
        setPages(pages, actionName: "Reverse Pages")
    }

    func addStamp(_ stamp: PageOps.Stamp, pages indices: [Int]) {
        let added = PageOps.addStamp(stamp, to: document, pages: indices, fileName: title)
        registerUndo("Header & Footer") { editor in
            for (page, a) in added { page.removeAnnotation(a) }
            editor.changed()
        }
        changed()
        showToast("Added to \(added.count) \(added.count == 1 ? "page" : "pages")")
    }

    func removeStamps() {
        let removed = PageOps.removeStamps(from: document)
        guard !removed.isEmpty else { showToast("No headers, footers or page numbers to remove"); return }
        registerUndo("Remove Header & Footer") { editor in
            for (page, a) in removed { page.addAnnotation(a) }
            editor.changed()
        }
        changed()
        showToast("Removed from \(Set(removed.map { ObjectIdentifier($0.page) }).count) pages")
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

    func deleteOutlineItem(_ item: PDFOutline) {
        guard let parent = item.parent else { return }
        let index = (0..<parent.numberOfChildren).first { parent.child(at: $0) === item } ?? parent.numberOfChildren
        item.removeFromParent()
        registerUndo("Delete Outline Item") { editor in
            parent.insertChild(item, at: index)
            editor.changed()
        }
        changed()
    }

    func retarget(_ item: PDFOutline) {
        guard let page = pdfView?.currentPage else { return }
        let previous = item.destination
        item.destination = pdfView?.currentDestination ?? PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: .cropBox).maxY))
        registerUndo("Change Destination") { editor in
            item.destination = previous
            editor.changed()
        }
        changed()
        showToast("Now points to page \(document.index(for: page) + 1)")
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
        searchHistory = Array(([query] + searchHistory.filter { $0 != query }).prefix(10))
        UserDefaults.standard.set(searchHistory, forKey: "searchHistory")
        if mode == .pages { mode = .read }
        searchResults = Search.find(query, in: document, matchCase: searchMatchCase, wholeWords: searchWholeWords)
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
        file.userPassword = password
        needsPassword = false
        changed()
        return true
    }

    // MARK: Protection and OCR

    /// Sets (or with nil, removes) the password required to open this document. Takes effect when saved.
    func setPassword(_ password: String?) {
        let previous = file.userPassword
        file.userPassword = password
        file.ownerPassword = nil
        registerUndo(password == nil ? "Remove Password" : "Set Password") { $0.setPassword(previous) }
        objectWillChange.send()
        showToast(password == nil ? "Password removed — save to apply" : "Password set — save to apply")
    }

    /// Adds a searchable text layer to scanned pages using on-device text recognition.
    func recognizeText() {
        let scanned = PDFOps.pages(of: document).filter { ($0.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        guard scanned > 0 else {
            showToast("Every page already has selectable text")
            return
        }
        guard let data = document.dataRepresentation() else { return }
        busy = "Recognizing text on \(scanned) \(scanned == 1 ? "page" : "pages")…"
        Task.detached(priority: .userInitiated) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
            let ok = PDFDocument(data: data)?.write(to: url, withOptions: [.saveTextFromOCROption: true]) ?? false
            await MainActor.run { self.finishRecognition(ok ? url : nil, scanned: scanned) }
        }
    }

    private func finishRecognition(_ url: URL?, scanned: Int) {
        busy = nil
        guard let url, let recognized = PDFDocument(url: url), recognized.pageCount == pageCount else {
            Prompt.error("Couldn’t recognize text.")
            return
        }
        let found = PDFOps.pages(of: recognized).filter { !($0.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        setPages(PDFOps.adopt(recognized), actionName: "Recognize Text")
        showToast(found > pageCount - scanned ? "Text recognized — the document is now searchable" : "No legible text found")
    }
}
