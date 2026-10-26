import AppKit
import PDFKit
import PagecraftCore
import UniformTypeIdentifiers

/// File-producing actions: exports, copies with save options, and new documents built from files.
@MainActor
enum Exporter {
    static func pdfCopy(_ editor: EditorController, suffix: String, options: PDFOps.WriteOptions, title: String) {
        guard let url = Prompt.save(.pdf, name: "\(editor.title) \(suffix).pdf", title: title) else { return }
        if !PDFOps.write(editor.document, to: url, options: options) { Prompt.error("Could not write \(url.lastPathComponent).") }
    }

    static func flattened(_ editor: EditorController) {
        pdfCopy(editor, suffix: "(flattened)", options: .init(flatten: true), title: "Save as Flattened")
    }

    static func reducedSize(_ editor: EditorController) {
        pdfCopy(editor, suffix: "(reduced)", options: .init(compressImages: true), title: "Reduce File Size")
    }

    static func passwordProtected(_ editor: EditorController) {
        guard let password = Prompt.text("Set Password", message: "Readers will need this password to open the copy.", secure: true),
              !password.isEmpty
        else { return }
        guard Prompt.text("Confirm Password", message: "Type the password again.", secure: true) == password else {
            Prompt.error("Passwords did not match.")
            return
        }
        pdfCopy(editor, suffix: "(protected)", options: .init(userPassword: password), title: "Save Password-Protected Copy")
    }

    static func text(_ editor: EditorController) {
        write(PDFOps.plainText(editor.document), type: .plainText, name: "\(editor.title).txt")
    }

    static func markdown(_ editor: EditorController) {
        write(PDFOps.markdown(editor.document, title: editor.title), type: UTType(filenameExtension: "md") ?? .plainText,
              name: "\(editor.title).md")
    }

    static func annotationSummary(_ editor: EditorController) {
        write(PDFOps.annotationSummary(editor.document, title: editor.title), type: UTType(filenameExtension: "md") ?? .plainText,
              name: "\(editor.title) annotations.md")
    }

    static func images(_ editor: EditorController) {
        guard let folder = Prompt.folder(title: "Export Pages as PNG") else { return }
        for (i, page) in PDFOps.pages(of: editor.document).enumerated() {
            try? PDFOps.pngData(page)?.write(to: folder.appendingPathComponent("\(editor.title) \(i + 1).png"))
        }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    static func extract(_ editor: EditorController, indices: [Int]) {
        let doc = PDFOps.extract(indices, from: editor.document)
        guard let url = Prompt.save(.pdf, name: "\(editor.title) (pages).pdf", title: "Extract Pages") else { return }
        PDFOps.write(doc, to: url)
    }

    static func insertFromFile(_ editor: EditorController) {
        guard let url = Prompt.open([.pdf], multiple: false, title: "Insert Pages").first else { return }
        editor.insertPages(from: url)
    }

    static func print(_ editor: EditorController) {
        editor.pdfView?.print(with: NSPrintInfo.shared, autoRotate: true, pageScaling: .pageScaleToFit)
    }

    static func mergeFiles() {
        let urls = Prompt.open([.pdf], multiple: true, title: "Choose PDFs to Merge")
        guard !urls.isEmpty else { return }
        let docs = urls.compactMap(PDFDocument.init(url:))
        saveAndOpen(PDFOps.merge(docs), name: "Merged.pdf", title: "Save Merged PDF")
    }

    static func newFromImages() {
        let urls = Prompt.open([.image], multiple: true, title: "Choose Images")
        guard !urls.isEmpty else { return }
        let images = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap(NSImage.init(contentsOf:))
        saveAndOpen(PDFOps.document(fromImages: images), name: "Images.pdf", title: "Save PDF")
    }

    private static func saveAndOpen(_ doc: PDFDocument, name: String, title: String) {
        guard doc.pageCount > 0, let url = Prompt.save(.pdf, name: name, title: title) else { return }
        guard PDFOps.write(doc, to: url) else { Prompt.error("Could not write \(url.lastPathComponent)."); return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    private static func write(_ string: String, type: UTType, name: String) {
        guard let url = Prompt.save(type, name: name, title: "Export") else { return }
        do { try string.write(to: url, atomically: true, encoding: .utf8) } catch { Prompt.error(error.localizedDescription) }
    }
}
