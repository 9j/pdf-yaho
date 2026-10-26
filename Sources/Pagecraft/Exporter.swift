import AppKit
import PDFKit
import PagecraftCore
import UniformTypeIdentifiers

/// File-producing actions: exports, copies with save options, sharing, and new documents built from files.
@MainActor
enum Exporter {
    // MARK: PDF copies

    /// Options that keep the document's own password protection on every copy.
    private static func options(_ editor: EditorController, flatten: Bool = false, compression: PDFOps.Compression? = nil) -> PDFOps.WriteOptions {
        PDFOps.WriteOptions(flatten: flatten, compression: compression,
                            userPassword: editor.file.userPassword, ownerPassword: editor.file.ownerPassword)
    }

    static func flattened(_ editor: EditorController) {
        guard let url = Prompt.save(.pdf, name: "\(editor.title) (flattened).pdf", title: "Save As Flattened") else { return }
        guard PDFOps.write(editor.document, to: url, options: options(editor, flatten: true)) else {
            Prompt.error("This document cannot be flattened.")
            return
        }
        editor.showToast("Saved flattened copy", url: url)
    }

    static func reduceSize(_ editor: EditorController, compression: PDFOps.Compression) {
        guard let url = Prompt.save(.pdf, name: "\(editor.title) (\(compression.rawValue.lowercased())).pdf", title: "Reduce File Size") else { return }
        guard PDFOps.write(editor.document, to: url, options: options(editor, compression: compression)) else {
            Prompt.error("Cannot reduce the file size.")
            return
        }
        let f = ByteCountFormatter()
        let before = editor.currentFileSize.map { f.string(fromByteCount: Int64($0)) } ?? "?"
        let after = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { f.string(fromByteCount: Int64($0)) } ?? "?"
        editor.showToast("\(before) → \(after)", url: url)
    }

    static func extract(_ editor: EditorController, indices: [Int]) {
        let doc = PDFOps.extract(indices, from: editor.document)
        guard let url = Prompt.save(.pdf, name: "\(editor.title) (pages).pdf", title: "Extract Pages") else { return }
        if PDFOps.write(doc, to: url) {
            editor.showToast("Extracted \(indices.count) \(indices.count == 1 ? "page" : "pages")", url: url)
        }
    }

    // MARK: Other formats

    static func rich(_ editor: EditorController, _ format: PDFOps.TextFormat) {
        let type: UTType = format == .word ? UTType(filenameExtension: "docx") ?? .data : format == .rtf ? .rtf : .html
        guard let url = Prompt.save(type, name: "\(editor.title).\(format.rawValue)", title: "Export") else { return }
        guard let data = PDFOps.exportData(editor.document, as: format), (try? data.write(to: url)) != nil else {
            Prompt.error("Export failed. The document may contain no selectable text — run Recognize Text first.")
            return
        }
        editor.showToast("Exported \(url.lastPathComponent)", url: url)
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

    static func xfdf(_ editor: EditorController) {
        write(editor, PDFOps.xfdf(editor.document, fileName: "\(editor.title).pdf"), type: UTType(filenameExtension: "xfdf") ?? .xml,
              name: "\(editor.title).xfdf")
    }

    static func images(_ editor: EditorController, format: PDFOps.ImageFormat, dpi: CGFloat, indices: [Int]) {
        guard let folder = Prompt.folder(title: "Export Pages as \(format.rawValue)") else { return }
        for index in indices {
            guard let page = editor.document.page(at: index) else { continue }
            let name = indices.count == 1 ? editor.title : "\(editor.title) \(index + 1)"
            try? PDFOps.imageData(page, format: format, dpi: dpi)?.write(to: folder.appendingPathComponent("\(name).\(format.fileExtension)"))
        }
        editor.showToast("Exported \(indices.count) \(indices.count == 1 ? "image" : "images")", url: folder)
    }

    // MARK: Sharing

    /// A copy in a private temporary folder, named after the document, for sharing or mail.
    private static func temporaryCopy(_ editor: EditorController, flattened: Bool) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(editor.title)\(flattened ? " (flattened)" : "").pdf")
        return PDFOps.write(editor.document, to: url, options: options(editor, flatten: flattened)) ? url : nil
    }

    static func share(_ editor: EditorController, flattened: Bool) {
        guard let view = editor.pdfView, let url = temporaryCopy(editor, flattened: flattened) else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: CGRect(x: view.bounds.maxX - 40, y: view.bounds.maxY - 4, width: 1, height: 1), of: view, preferredEdge: .maxY)
    }

    static func mail(_ editor: EditorController, flattened: Bool) {
        guard let url = temporaryCopy(editor, flattened: flattened) else { return }
        guard let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: [url]) else {
            Prompt.error("No mail app is set up on this Mac.")
            return
        }
        service.subject = editor.title
        service.perform(withItems: [url])
    }

    static func print(_ editor: EditorController) {
        editor.pdfView?.print(with: NSPrintInfo.shared, autoRotate: true, pageScaling: .pageScaleToFit)
    }

    // MARK: New documents

    static func insertFromFile(_ editor: EditorController) {
        guard let url = Prompt.open([.pdf], multiple: false, title: "Insert Pages").first else { return }
        editor.insertPages(from: url)
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

    static func saveAndOpen(_ doc: PDFDocument, name: String, title: String) {
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
