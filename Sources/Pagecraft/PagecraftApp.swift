import PDFKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// DocumentGroup always creates an untitled document at launch. When the app was launched
    /// to open a file, close that blank document so only the requested file is shown.
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let documents = NSDocumentController.shared.documents
            guard documents.contains(where: { $0.fileURL != nil }) else { return }
            for document in documents where document.fileURL == nil && !document.isDocumentEdited {
                document.close()
            }
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
            Button("Merge Files…") { Exporter.mergeFiles() }
        }
        CommandGroup(after: .saveItem) {
            Menu("Export As") {
                Button("Plain Text…") { run(Exporter.text) }
                Button("Markdown…") { run(Exporter.markdown) }
                Button("PNG Images…") { run(Exporter.images) }
                Button("Annotation Summary…") { run(Exporter.annotationSummary) }
            }
            .disabled(editor == nil)
            Button("Save as Flattened…") { run(Exporter.flattened) }.disabled(editor == nil)
            Button("Reduce File Size…") { run(Exporter.reducedSize) }.disabled(editor == nil)
            Button("Set Password…") { run(Exporter.passwordProtected) }.disabled(editor == nil)
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
            Divider()
        }
        CommandMenu("Go") {
            Button("Previous Page") { editor.map { $0.goToPage($0.currentPageIndex - 1) } }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Next Page") { editor.map { $0.goToPage($0.currentPageIndex + 1) } }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("First Page") { editor?.goToPage(0) }.keyboardShortcut(.upArrow)
            Button("Last Page") { editor.map { $0.goToPage($0.pageCount - 1) } }.keyboardShortcut(.downArrow)
            Divider()
            Button("Go to Page…") {
                guard let editor, let text = Prompt.text("Go to Page", message: "Page number (1–\(editor.pageCount)):"),
                      let number = Int(text) else { return }
                editor.goToPage(number - 1)
            }
            .keyboardShortcut("g", modifiers: [.command, .option])
        }
        CommandMenu("Annotate") {
            ForEach(Array(Tool.allCases.enumerated()), id: \.element) { index, tool in
                if index < 9 {
                    Button(tool.label) { editor?.tool = tool }.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .control])
                } else {
                    Button(tool.label) { editor?.tool = tool }
                }
            }
            Divider()
            Button("Edit Signature…") { editor?.showSignaturePad = true }
            Button("Apply Redactions…") { editor?.applyRedactions() }
            Divider()
            Button("Remove All Annotations") { editor?.removeAllAnnotations() }
        }
        CommandMenu("Page") {
            Button("Rotate Left") { editor?.rotate(-90) }.keyboardShortcut("l")
            Button("Rotate Right") { editor?.rotate(90) }.keyboardShortcut("r")
            Divider()
            Button("Insert Blank Page") { editor?.insertBlankPage() }.keyboardShortcut("n", modifiers: [.command, .option])
            Button("Insert Pages from File…") { run(Exporter.insertFromFile) }
            Button("Extract Pages…") { editor.map { Exporter.extract($0, indices: $0.targetPageIndices) } }
            Button("Delete Page") { editor?.deletePages() }.keyboardShortcut(.delete, modifiers: [.command])
            Divider()
            Button("Add Page Numbers") { editor?.addPageNumbers() }
            Button("Remove Page Numbers") { editor?.removePageNumbers() }
            Button("Add Bookmark…") {
                guard let editor,
                      let label = Prompt.text("Add Bookmark", message: "Bookmark title:", defaultValue: "Page \(editor.currentPageIndex + 1)")
                else { return }
                editor.addBookmark(label: label, page: editor.currentPageIndex)
            }
            .keyboardShortcut("d")
        }
    }

    private func run(_ action: (EditorController) -> Void) {
        if let editor { action(editor) }
    }
}
