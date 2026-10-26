import PDFKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// DocumentGroup creates an untitled document at launch. Replace it with the Welcome window,
    /// or just drop it when the app was launched to open a file.
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            for document in NSDocumentController.shared.documents where document.fileURL == nil && !document.isDocumentEdited {
                document.close()
            }
            self.showWelcomeIfIdle()
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated { self.showWelcomeIfIdle() }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WelcomeWindowController.shared.show() }
        return false
    }

    private func showWelcomeIfIdle() {
        let hasDocumentWindow = NSApp.windows.contains { $0.isVisible && NSDocumentController.shared.document(for: $0) != nil }
        if !hasDocumentWindow, NSApp.modalWindow == nil, !NSApp.windows.contains(where: { $0 is NSSavePanel && $0.isVisible }) {
            WelcomeWindowController.shared.show()
        }
    }
}

@main
struct PagecraftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: { PDFFile() }) { configuration in
            DocumentView(file: configuration.document)
        }
        .defaultSize(width: 1280, height: 920)
        .commands { PagecraftCommands() }
        Settings { SettingsView() }
    }
}

struct EditorKey: FocusedValueKey {
    typealias Value = EditorController
}

extension FocusedValues {
    var editor: EditorController? {
        get { self[EditorKey.self] }
        set { self[EditorKey.self] = newValue }
    }
}

struct PagecraftCommands: Commands {
    @FocusedValue(\.editor) private var editor

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New PDF from Images…") { Exporter.newFromImages() }
            Button("Merge PDFs…") { Exporter.mergeFiles() }
            Button("Convert File to PDF…") { Exporter.convertFiles() }
            Button("Compare PDFs…") { CompareWindow.chooseFiles() }
            Divider()
            Button("Welcome to Pagecraft") { WelcomeWindowController.shared.show() }
                .keyboardShortcut("1", modifiers: [.command, .shift])
        }
        CommandGroup(after: .saveItem) {
            Button("Save As Flattened…") { run(Exporter.flattened) }
                .keyboardShortcut("s", modifiers: [.command, .option, .shift])
                .disabled(editor == nil)
            Menu("Export To") {
                Button("Word Document (.docx)…") { editor.map { Exporter.rich($0, .word) } }
                Button("Rich Text (.rtf)…") { editor.map { Exporter.rich($0, .rtf) } }
                Button("Web Page (.html)…") { editor.map { Exporter.rich($0, .html) } }
                Button("Plain Text…") { run(Exporter.text) }
                Button("Markdown…") { run(Exporter.markdown) }
                Divider()
                Button("Images…") { editor?.showExportImages = true }
                Button("Flattened PDF…") { run(Exporter.flattened) }
                Divider()
                Button("Annotations (XFDF)…") { run(Exporter.xfdf) }
                Button("Annotation Summary (Markdown)…") { run(Exporter.annotationSummary) }
            }
            .disabled(editor == nil)
            Menu("Share") {
                Button("Share Document…") { editor.map { Exporter.share($0, flattened: false) } }
                Button("Share Flattened…") { editor.map { Exporter.share($0, flattened: true) } }
                Divider()
                Button("Mail Document") { editor.map { Exporter.mail($0, flattened: false) } }
                Button("Mail Flattened") { editor.map { Exporter.mail($0, flattened: true) } }
            }
            .disabled(editor == nil)
            Divider()
            Button("Reduce File Size…") { editor?.showReduceSize = true }.disabled(editor == nil)
            Button("Recognize Text (OCR)…") { editor?.recognizeText() }.disabled(editor == nil)
            Button(editor?.isPasswordProtected == true ? "Change Password…" : "Set Password…") { editor?.showPasswordSheet = true }
                .disabled(editor == nil)
            if editor?.isPasswordProtected == true {
                Button("Remove Password") { editor?.setPassword(nil) }
            }
            Divider()
            Button("Properties…") { editor?.showProperties = true }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(editor == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { run(Exporter.print) }
                .keyboardShortcut("p")
                .disabled(editor == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find Next") { editor?.findNext() }.keyboardShortcut("g")
            Button("Find Previous") { editor?.findNext(-1) }.keyboardShortcut("g", modifiers: [.command, .shift])
        }
        CommandGroup(before: .toolbar) {
            ForEach(Array(EditorMode.allCases.enumerated()), id: \.element) { index, mode in
                Button(mode.rawValue) { editor?.mode = mode }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
            Button("Zoom In") { editor?.zoomIn() }.keyboardShortcut("+")
            Button("Zoom Out") { editor?.zoomOut() }.keyboardShortcut("-")
            Button("Actual Size") { editor?.actualSize() }.keyboardShortcut("0")
            Button("Zoom to Fit Width") { editor?.fitWidth() }.keyboardShortcut("9")
            Button("Zoom to Fit Page") { editor?.fitPage() }.keyboardShortcut("8")
            Divider()
            Menu("Page Layout") {
                ForEach(PageLayout.allCases) { layout in Button(layout.rawValue) { editor?.layout = layout } }
            }
            Menu("Theme") {
                ForEach(ReadingTheme.allCases) { theme in Button(theme.rawValue) { editor?.theme = theme } }
            }
            Button("Compare With Document…") { editor.map(CompareWindow.compare) }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(editor == nil)
            Divider()
        }
        CommandMenu("Go") {
            Button("Previous Page") { editor.map { $0.goToPage($0.currentPageIndex - 1) } }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Next Page") { editor.map { $0.goToPage($0.currentPageIndex + 1) } }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("Back") { editor?.pdfView?.goBack(nil) }.keyboardShortcut("[")
            Button("Forward") { editor?.pdfView?.goForward(nil) }.keyboardShortcut("]")
            Divider()
            Button("First Page") { editor?.goToPage(0) }.keyboardShortcut(.upArrow)
            Button("Last Page") { editor.map { $0.goToPage($0.pageCount - 1) } }.keyboardShortcut(.downArrow)
            Divider()
            Button("Go to Page…") { editor?.focusPageField = true }
                .keyboardShortcut("g", modifiers: [.command, .option])
        }
        CommandMenu("Markup") {
            ForEach(Tool.allCases) { tool in
                Button(tool.label) { editor?.tool = tool }
            }
            Divider()
            Button("New Signature…") { editor?.signaturePadInitials = false; editor?.showSignaturePad = true }
            Button("New Initials…") { editor?.signaturePadInitials = true; editor?.showSignaturePad = true }
            Divider()
            Button("Find and Redact…") { editor?.showFindRedact = true }.keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Apply Redactions…") { editor?.applyRedactions() }
            Divider()
            Button("Clear Form") { editor?.resetForm() }
            Divider()
            Button("Measurement Scale…") { editor?.showMeasureScale = true }
            Button("Snapshot Area") { editor?.tool = .snapshot }
            Divider()
            Button("Remove All Annotations") { editor?.removeAllAnnotations() }
        }
        CommandMenu("Page") {
            Menu("Insert") {
                Button("Blank Page") { editor?.insertBlankPage() }.keyboardShortcut("n", modifiers: [.command, .option])
                Button("From File…") { run(Exporter.insertFromFile) }
                Button("From Images…") { editor?.insertImages() }
                Button("From Clipboard") { editor?.insertFromClipboard() }
            }
            Button("Duplicate") { editor?.duplicatePages() }
            Button("Delete") { editor?.deletePages() }.keyboardShortcut(.delete, modifiers: [.command])
            Divider()
            Button("Rotate Left") { editor?.rotate(-90) }.keyboardShortcut("l")
            Button("Rotate Right") { editor?.rotate(90) }.keyboardShortcut("r")
            Button("Reverse Order") { editor?.reversePages() }
            Divider()
            Button("Crop…") { editor?.beginCrop() }.keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Clear Margins") { editor?.autoCrop() }
            Button("Reset Crop") { editor?.resetCrop() }
            Button("Page Size…") { editor?.showPageSize = true }
            Divider()
            Button("Extract…") { editor.map { Exporter.extract($0, indices: $0.targetPageIndices) } }
            Button("Split…") { editor?.showSplit = true }
            Divider()
            Button("Page Numbers…") { editor?.headerFooterPreset = .pageNumbers }
            Button("Header & Footer…") { editor?.headerFooterPreset = .custom }
            Button("Bates Numbering…") { editor?.headerFooterPreset = .bates }
            Button("Remove Header, Footer & Numbers") { editor?.removeStamps() }
            Divider()
            Button("Bookmark This Page") { editor?.addBookmark() }
                .keyboardShortcut("d")
        }
    }

    private func run(_ action: (EditorController) -> Void) {
        if let editor { action(editor) }
    }
}
