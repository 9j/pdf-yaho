import PDFKit
import PagecraftCore
import SwiftUI

/// PDFView that turns mouse gestures into annotations for the active tool.
final class EditorPDFView: PDFView {
    weak var editor: EditorController?

    private var dragPage: PDFPage?
    private var dragStart: CGPoint = .zero
    private var stroke: [CGPoint] = []
    private var preview: PDFAnnotation?
    private var moving: (annotation: PDFAnnotation, original: CGRect)?
    private var didShowFirstPage = false

    /// Auto-scaling settles after the first layout and leaves the view mid-page; start at the top instead.
    override func layout() {
        super.layout()
        guard !didShowFirstPage, bounds.width > 0, let first = document?.page(at: 0) else { return }
        didShowFirstPage = true
        DispatchQueue.main.async { [weak self] in
            let box = first.bounds(for: .cropBox)
            self?.go(to: PDFDestination(page: first, at: CGPoint(x: box.minX, y: box.maxY)))
        }
    }

    private func location(_ event: NSEvent) -> (page: PDFPage, point: CGPoint)? {
        let loc = convert(event.locationInWindow, from: nil)
        guard let page = dragPage ?? page(for: loc, nearest: true) else { return nil }
        return (page, convert(loc, to: page))
    }

    override func mouseMoved(with event: NSEvent) {
        guard let tool = editor?.tool, tool != .select, tool.markupType == nil else { return super.mouseMoved(with: event) }
        NSCursor.crosshair.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let editor, let (page, point) = location(event) else { return super.mouseDown(with: event) }
        switch editor.tool {
        case .select:
            if let hit = page.annotation(at: point), Annotations.isMovable(hit) {
                if event.clickCount == 2 { editor.editAnnotation(hit, on: page); return }
                dragPage = page
                dragStart = point
                moving = (hit, hit.bounds)
                return
            }
            super.mouseDown(with: event)
        case .highlight, .underline, .strikeout:
            super.mouseDown(with: event)
        case .text:
            editor.placeText(at: point, on: page)
        case .note:
            editor.placeNote(at: point, on: page)
        case .signature:
            editor.placeSignature(at: point, on: page)
        case .eraser:
            if let hit = page.annotation(at: point) { editor.erase(hit, on: page) }
        case .pen, .rectangle, .oval, .line, .arrow, .redact:
            dragPage = page
            dragStart = point
            stroke = [point]
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let editor, let page = dragPage, let (_, point) = location(event) else { return super.mouseDragged(with: event) }
        if let (annotation, original) = moving {
            annotation.bounds.origin = original.origin + (point - dragStart)
            annotationsChanged(on: page)
            return
        }
        stroke.append(point)
        showPreview(makeAnnotation(editor, to: point), on: page)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragPage = nil; moving = nil; stroke = []; showPreview(nil, on: nil) }
        guard let editor else { return super.mouseUp(with: event) }
        if let page = dragPage, let (annotation, original) = moving {
            if annotation.bounds != original { editor.setBounds(annotation.bounds, of: annotation, on: page, previous: original) }
            return
        }
        if let page = dragPage, let (_, point) = location(event) {
            showPreview(nil, on: nil)
            let large = abs(point.x - dragStart.x) > 3 || abs(point.y - dragStart.y) > 3
            if (large || editor.tool == .pen), let annotation = makeAnnotation(editor, to: point) {
                editor.add(annotation, to: page)
            }
            return
        }
        super.mouseUp(with: event)
        if let type = editor.tool.markupType, let selection = currentSelection, !(selection.string ?? "").isEmpty {
            editor.applyMarkup(type, to: selection)
        }
    }

    private func makeAnnotation(_ editor: EditorController, to point: CGPoint) -> PDFAnnotation? {
        let color = editor.tool == .pen && editor.color == .yellow ? NSColor.systemRed : editor.nsColor
        if editor.tool == .pen {
            return Annotations.ink(strokes: [stroke], color: color, lineWidth: editor.lineWidth)
        }
        if editor.tool == .redact {
            return Annotations.redaction(bounds: CGRect(x: min(dragStart.x, point.x), y: min(dragStart.y, point.y),
                                                        width: abs(point.x - dragStart.x), height: abs(point.y - dragStart.y)))
        }
        guard let shape = editor.tool.shape else { return nil }
        return Annotations.shape(shape, from: dragStart, to: point, color: color, lineWidth: editor.lineWidth)
    }

    private func showPreview(_ annotation: PDFAnnotation?, on page: PDFPage?) {
        if let preview, let owner = preview.page { owner.removeAnnotation(preview) }
        preview = annotation
        if let annotation, let page { page.addAnnotation(annotation) }
    }
}

struct PDFKitView: NSViewRepresentable {
    let editor: EditorController

    func makeNSView(context: Context) -> EditorPDFView {
        let view = EditorPDFView()
        view.autoScales = true
        view.backgroundColor = .underPageBackgroundColor
        view.pageShadowsEnabled = true
        editor.attach(view)
        return view
    }

    func updateNSView(_ view: EditorPDFView, context: Context) {}
}
