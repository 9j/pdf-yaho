#if DEBUG
import PDFKit
import PDFYahoCore

extension EditorController {
    /// Places one of each newer annotation type on page 1, for automated screenshots in debug builds.
    func placeQADemo() {
        guard let page = document.page(at: 0) else { return }
        if let match = document.findString("Line 3:", withOptions: []).first {
            for l in match.selectionsByLine() { add(Annotations.squiggly(bounds: l.bounds(for: page), color: Palette.swatches[2]), to: page) }
        }
        add(CalloutAnnotation.make(text: "Check this figure", box: CGRect(x: 380, y: 600, width: 150, height: 34),
                                   anchor: CGPoint(x: 300, y: 560), color: Palette.swatches[7], fontSize: 12), to: page)
        add(Annotations.cloud(rect: CGRect(x: 80, y: 300, width: 200, height: 90), color: Palette.swatches[2], lineWidth: 1.5), to: page)
        if let cloud = Annotations.cloudPolygon(points: [CGPoint(x: 360, y: 300), CGPoint(x: 520, y: 330), CGPoint(x: 470, y: 420)],
                                                color: Palette.swatches[8], lineWidth: 1.5, fill: Palette.swatches[8].withAlphaComponent(0.15)) {
            add(cloud, to: page)
        }
        let arrow = Annotations.shape(.line, from: CGPoint(x: 80, y: 220), to: CGPoint(x: 300, y: 220), color: Palette.swatches[0], lineWidth: 2)
        Annotations.setLineEndings(start: .circle, end: .closedArrow, of: arrow)
        Annotations.setLineStyle(.dashDotted, of: arrow)
        add(arrow, to: page)
        toggleBookmark(0)
    }
}
#endif

#if DEBUG
extension EditorController {
    /// Edit-mode states for automated screenshots: "select", "edit" (inline editor open) or "replace" (text rewritten).
    func runContentQA(_ step: String) {
        mode = .edit
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            guard let page = document.page(at: 0) else { return }
            loadContent(on: page, force: true)
            guard let block = contentBlocks.first(where: { $0.kind == .text && $0.text.count > 40 }) ?? contentBlocks.first else { return }
            switch step {
            case "edit":
                selectedContent = block
                pdfView?.beginContentEditing(block, on: page)
            case "replace":
                replaceContentText(block, on: page, with: "편집된 문단입니다. PDF Yaho rewrote this paragraph with PDFium, keeping its font size and width.")
            default:
                selectedContent = block
            }
        }
    }
}
#endif

