import AppKit
import SwiftUI

/// One launchable tool on the Tools page and in "Tools for You".
struct HomeTool: Identifiable {
    let id: String
    let title: String
    let summary: String
    let symbol: String
    let tint: Color
    let run: @MainActor () -> Void
}

struct HomeToolCategory: Identifiable {
    let title: String
    let tools: [HomeTool]
    var id: String { title }
}

@MainActor
enum HomeTools {
    private static func picking(_ action: LaunchAction, _ prompt: String) -> @MainActor () -> Void {
        { DocumentLauncher.chooseAndOpen(action, title: prompt) }
    }

    static let categories: [HomeToolCategory] = [
        HomeToolCategory(title: "Edit & Sign", tools: [
            HomeTool(id: "annotate", title: "Annotate", summary: "Highlight, underline and add notes.",
                     symbol: "highlighter", tint: .blue,
                     run: picking(.annotate, "Select a file to annotate.")),
            HomeTool(id: "draw", title: "Draw", summary: "Sketch freehand with a pen.",
                     symbol: EditorMode.draw.symbol, tint: .blue,
                     run: picking(.draw, "Select a PDF to draw on.")),
            HomeTool(id: "fillAndSign", title: "Fill & Sign", summary: "Complete forms and type into any page.",
                     symbol: EditorMode.fillSign.symbol, tint: .blue,
                     run: picking(.fillAndSign, "Select a PDF to fill and sign.")),
            HomeTool(id: "sign", title: "Sign PDF", summary: "Add your signature to a document.",
                     symbol: "signature", tint: .blue,
                     run: picking(.sign, "Select a PDF to sign.")),
            HomeTool(id: "measure", title: "Measure", summary: "Measure distances, perimeters and areas.",
                     symbol: "ruler", tint: .blue,
                     run: picking(.measure, "Select a PDF to measure.")),
            HomeTool(id: "redact", title: "Redact", summary: "Permanently black out sensitive content.",
                     symbol: "eye.slash", tint: .blue,
                     run: picking(.redact, "Select a PDF to redact.")),
        ]),
        HomeToolCategory(title: "Organize", tools: [
            HomeTool(id: "pages", title: "Manage Pages", summary: "Reorder, rotate, delete and insert pages.",
                     symbol: EditorMode.pages.symbol, tint: .orange,
                     run: picking(.pages, "Select a PDF to manage its pages.")),
            HomeTool(id: "merge", title: "Merge PDFs", summary: "Combine several files into one.",
                     symbol: "square.stack.3d.down.right", tint: .orange,
                     run: { Exporter.mergeFiles() }),
            HomeTool(id: "split", title: "Split PDF", summary: "Break a document into smaller files.",
                     symbol: "scissors", tint: .orange,
                     run: picking(.split, "Select a PDF to split.")),
            HomeTool(id: "pageNumbers", title: "Add Page Numbers", summary: "Number pages with a header or footer.",
                     symbol: "number", tint: .orange,
                     run: picking(.pageNumbers, "Select a PDF to add page numbers to.")),
            HomeTool(id: "resizePages", title: "Resize Pages", summary: "Change the paper size of every page.",
                     symbol: "arrow.up.left.and.arrow.down.right", tint: .orange,
                     run: picking(.resizePages, "Select a PDF to resize its pages.")),
            HomeTool(id: "compare", title: "Compare PDFs", summary: "View two documents side by side.",
                     symbol: "rectangle.split.2x1", tint: .orange,
                     run: { CompareWindow.chooseFiles() }),
        ]),
        HomeToolCategory(title: "Convert", tools: [
            HomeTool(id: "exportWord", title: "PDF to Word", summary: "Turn a PDF into an editable .docx.",
                     symbol: "doc.text", tint: .green,
                     run: picking(.exportWord, "Select a PDF to convert to Word.")),
            HomeTool(id: "exportImages", title: "PDF to Images", summary: "Export pages as PNG or JPEG.",
                     symbol: "photo.on.rectangle", tint: .green,
                     run: picking(.exportImages, "Select a PDF to export as images.")),
            HomeTool(id: "imagesToPDF", title: "Images to PDF", summary: "Build a PDF from photos and scans.",
                     symbol: "photo.badge.plus", tint: .green,
                     run: { Exporter.newFromImages() }),
            HomeTool(id: "anyToPDF", title: "Any File to PDF", summary: "Convert documents, text and web pages.",
                     symbol: "doc.badge.arrow.up", tint: .green,
                     run: { Exporter.convertFiles() }),
            HomeTool(id: "blank", title: "New Blank PDF", summary: "Start from an empty page.",
                     symbol: "doc.badge.plus", tint: .green,
                     run: { NSDocumentController.shared.newDocument(nil) }),
        ]),
        HomeToolCategory(title: "Protect & Optimize", tools: [
            HomeTool(id: "compress", title: "Compress PDF", summary: "Reduce the file size for sharing.",
                     symbol: "arrow.down.right.and.arrow.up.left", tint: .purple,
                     run: picking(.compress, "Select a PDF to reduce file size.")),
            HomeTool(id: "setPassword", title: "Set Password", summary: "Require a password to open the file.",
                     symbol: "lock", tint: .purple,
                     run: picking(.setPassword, "Select a PDF to protect with a password.")),
            HomeTool(id: "ocr", title: "Recognize Text (OCR)", summary: "Make scanned pages searchable.",
                     symbol: "text.viewfinder", tint: .purple,
                     run: picking(.recognizeText, "Select a PDF to recognize text in.")),
        ]),
    ]

    /// The fixed shortlist shown on the Home page.
    static let featured: [HomeTool] = {
        let all = Dictionary(uniqueKeysWithValues: categories.flatMap(\.tools).map { ($0.id, $0) })
        return ["annotate", "sign", "merge", "compress", "exportWord", "ocr"].compactMap { all[$0] }
    }()
}
