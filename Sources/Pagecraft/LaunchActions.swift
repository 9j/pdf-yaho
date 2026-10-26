import AppKit
import PDFKit

/// Something to do as soon as a document window opens. Home-screen tools such as
/// "Compress PDF" pick a file, open it, and queue the action here.
enum LaunchAction: String, CaseIterable, Sendable {
    case annotate, draw, fillAndSign, measure, redact, scan, pages, sign
    case compress, recognizeText, setPassword, pageNumbers, resizePages, split, exportWord, exportExcel, exportPowerPoint, exportImages, compare
}

@MainActor
enum DocumentLauncher {
    private static var pending: [URL: LaunchAction] = [:]

    /// Opens `url` and runs `action` once its window is ready.
    static func open(_ url: URL, then action: LaunchAction? = nil) {
        if let action { pending[url.standardizedFileURL.resolvingSymlinksInPath()] = action }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, alreadyOpen, _ in
            // An already-open document does not re-run onAppear, so run the action directly.
            guard alreadyOpen, let window = document?.windowControllers.first?.window,
                  let editor = EditorRegistry.editor(for: window) else { return }
            if let action = take(for: url) { editor.perform(action) }
        }
    }

    /// Asks for a PDF, then opens it with `action`.
    static func chooseAndOpen(_ action: LaunchAction? = nil, title: String = "Choose a PDF") {
        guard let url = Prompt.open([.pdf], multiple: false, title: title).first else { return }
        open(url, then: action)
    }

    static func take(for url: URL) -> LaunchAction? {
        pending.removeValue(forKey: url.standardizedFileURL.resolvingSymlinksInPath())
    }
}

/// Maps windows to their editors so app-level code can reach an open document.
@MainActor
enum EditorRegistry {
    private static var editors: [ObjectIdentifier: WeakEditor] = [:]
    private struct WeakEditor { weak var editor: EditorController? }

    static func register(_ editor: EditorController, window: NSWindow) {
        editors[ObjectIdentifier(window)] = WeakEditor(editor: editor)
        editors = editors.filter { $0.value.editor != nil }
    }

    static func editor(for window: NSWindow) -> EditorController? {
        editors[ObjectIdentifier(window)]?.editor
    }
}

extension EditorController {
    func perform(_ action: LaunchAction) {
        switch action {
        case .annotate: mode = .annotate
        case .draw: mode = .draw
        case .fillAndSign: mode = .fillSign
        case .sign: mode = .fillSign; tool = .signature
        case .measure: mode = .measure
        case .redact: mode = .redact
        case .scan: mode = .scan
        case .pages: mode = .pages
        case .compress: showReduceSize = true
        case .recognizeText: recognizeText()
        case .setPassword: showPasswordSheet = true
        case .pageNumbers: headerFooterPreset = .pageNumbers
        case .resizePages: showPageSize = true
        case .split: showSplit = true
        case .exportWord: Exporter.rich(self, .word)
        case .exportExcel: Exporter.excel(self)
        case .exportPowerPoint: Exporter.powerPoint(self)
        case .exportImages: showExportImages = true
        case .compare: CompareWindow.compare(self)
        }
    }
}
