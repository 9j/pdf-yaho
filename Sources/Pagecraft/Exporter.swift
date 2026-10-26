import AppKit
import PDFKit
import PagecraftCore
import UniformTypeIdentifiers

/// File-producing actions: exports, copies with save options, and new documents built from files.
@MainActor
enum Exporter {
    static func pdfCopy(_ editor: EditorController, suffix: String, options: PDFOps.WriteOptions, title: String) {
        guard let url = Prompt.save(.pdf, name: "\(editor.title) \(suffix).pdf", title: title) else { return }
        guard PDFOps.write(editor.document, to: url, options: options) else { Prompt.error("Could not write \(url.lastPathComponent)."); return }
        var message = "Saved \(url.lastPathComponent)"
        if options.compressImages, let before = editor.document.dataRepresentation()?.count,
           let after = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            let f = ByteCountFormatter()
            message = "Saved \(url.lastPathComponent) · \(f.string(fromByteCount: Int64(before))) → \(f.string(fromByteCount: Int64(after)))"
        }
        editor.showToast(message, url: url)
    }

    static func flattened(_ editor: EditorController) {
        pdfCopy(editor, suffix: "(flattened)", options: .init(flatten: true), title: "Save as Flattened")
    }

    static func reducedSize(_ editor: EditorController) {
        pdfCopy(editor, suffix: "(reduced)", options: .init(compressImages: true), title: "Reduce File Size")
    }

    static func passwordProtected(_ editor: EditorController, password: String) {
        pdfCopy(editor, suffix: "(protected)", options: .init(userPassword: password), title: "Save Password-Protected Copy")
    }

    static func text(_ editor: EditorController) {
        write(editor, PDFOps.plainText(editor.document), type: .plainText, name: "\(editor.title).txt")
    }

    static func markdown(_ editor: EditorController) {
        write(editor, PDFOps.markdown(editor.document, title: editor.title), type: UTType(filenameExtension: "md") ?? .plainText,
              name: "\(editor.title).md")
    }

    static func annotationSummary(_ editor: EditorController) {
        write(editor, PDFOps.annotationSummary(editor.document, title: editor.title), type: UTType(filenameExtension: "md") ?? .plainText,
              name: "\(editor.title) annotations.md")
    }

    static func images(_ editor: EditorController) {
        guard let folder = Prompt.folder(title: "Export Pages as PNG") else { return }
        let pages = PDFOps.pages(of: editor.document)
        for (i, page) in pages.enumerated() {
            try? PDFOps.pngData(page)?.write(to: folder.appendingPathComponent("\(editor.title) \(i + 1).png"))
        }
        editor.showToast("Exported \(pages.count) images", url: folder)
    }

    static func extract(_ editor: EditorController, indices: [Int]) {
        let doc = PDFOps.extract(indices, from: editor.document)
        guard let url = Prompt.save(.pdf, name: "\(editor.title) (pages).pdf", title: "Extract Pages") else { return }
        if PDFOps.write(doc, to: url) {
            editor.showToast("Extracted \(indices.count) \(indices.count == 1 ? "page" : "pages")", url: url)
        }
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

    private static func write(_ editor: EditorController, _ string: String, type: UTType, name: String) {
        guard let url = Prompt.save(type, name: name, title: "Export") else { return }
        do {
            try string.write(to: url, atomically: true, encoding: .utf8)
            editor.showToast("Exported \(url.lastPathComponent)", url: url)
        } catch {
            Prompt.error(error.localizedDescription)
        }
    }
}
