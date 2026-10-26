import PDFKit
import PagecraftCore
import SwiftUI

/// PDFView that turns mouse and keyboard input into annotation edits for the active tool.
final class EditorPDFView: PDFView {
    weak var editor: EditorController?

    private enum Drag {
        case draw(page: PDFPage, start: CGPoint, stroke: [CGPoint])
        case move(SelectedAnnotation, start: CGPoint, original: CGRect)
        case resize(SelectedAnnotation, anchor: CGPoint, original: CGRect)
        case crop(page: PDFPage, start: CGPoint)
    }

    /// Annotation under the pointer when a drawing tool was pressed; a plain click selects it instead of drawing.
    private var pendingHit: SelectedAnnotation?

    /// Vertices placed so far with the Polygon or Polyline tool.
    private var points: (page: PDFPage, list: [CGPoint])?

    private var drag: Drag?
    private var preview: PDFAnnotation?
    private var inline: InlineTextEditor?
    private var didShowFirstPage = false

    var scrollView: NSScrollView? { documentView?.enclosingScrollView }
    override var acceptsFirstResponder: Bool { true }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        editor?.hoverPage = nil
    }

    /// Auto-scaling settles after the first layout and leaves the view mid-page; start at the top instead.
    override func layout() {
        super.layout()
        guard !didShowFirstPage, bounds.width > 0, let first = document?.page(at: 0) else { return }
        didShowFirstPage = true
        let pending = editor?.pendingDestination
        editor?.pendingDestination = nil
        DispatchQueue.main.async { [weak self] in
            if let pending { self?.go(to: pending); return }
            let box = first.bounds(for: .cropBox)
            self?.go(to: PDFDestination(page: first, at: CGPoint(x: box.minX, y: box.maxY)))
        }
    }

    private func pagePoint(_ event: NSEvent, page fixed: PDFPage? = nil) -> (page: PDFPage, point: CGPoint, view: CGPoint)? {
        let loc = convert(event.locationInWindow, from: nil)
        guard let page = fixed ?? page(for: loc, nearest: true) else { return nil }
        return (page, convert(loc, to: page), loc)
    }

    /// Topmost user annotation under the point, with a little slack for thin shapes.
    private func hit(_ point: CGPoint, on page: PDFPage) -> PDFAnnotation? {
        let slack = 4 / max(scaleFactor, 0.1)
        // Links are followed when reading and edited in Markup mode.
        let editing = editor?.mode.isMarkup == true
        return page.annotations.reversed().first {
            (Annotations.isUserEditable($0) || (editing && ["Link", "Widget"].contains($0.type ?? "")))
                && $0.bounds.insetBy(dx: -slack, dy: -slack).contains(point)
        }
    }

    /// The corner handle under a view point, returning the opposite corner as the resize anchor (page space).
    private func resizeAnchor(at viewPoint: CGPoint) -> (SelectedAnnotation, CGPoint)? {
        guard let selected = editor?.selected, Annotations.isResizable(selected.annotation) else { return nil }
        let b = selected.annotation.bounds
        let corners = [(CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.maxY)),
                       (CGPoint(x: b.maxX, y: b.minY), CGPoint(x: b.minX, y: b.maxY)),
                       (CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.maxX, y: b.minY)),
                       (CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.minY))]
        for (corner, opposite) in corners {
            let v = convert(corner, from: selected.page)
            if abs(v.x - viewPoint.x) <= 7, abs(v.y - viewPoint.y) <= 7 { return (selected, opposite) }
        }
        return nil
    }

    // MARK: Cursor

    override func mouseMoved(with event: NSEvent) {
        guard let editor else { return super.mouseMoved(with: event) }
        let loc = convert(event.locationInWindow, from: nil)
        let hovered = page(for: loc, nearest: false)
        if hovered !== editor.hoverPage { editor.hoverPage = hovered }
        if loc.y < 70 { editor.pokeHUD() }
        if let (selected, anchor) = resizeAnchor(at: loc) { resizeCursor(for: selected, anchor: anchor).set(); return }
        if editor.tool != .eraser, editor.mode != .read, let (page, point, _) = pagePoint(event), let a = hit(point, on: page), Annotations.isMovable(a) {
            NSCursor.openHand.set()
            return
        }
        switch editor.tool {
        case .select, .highlight, .underline, .squiggly, .strikeout:
            super.mouseMoved(with: event)
        case .text: NSCursor.iBeam.set()
        case .eraser, .note, .signature, .stamp, .checkmark, .cross, .date: NSCursor.pointingHand.set()
        default: NSCursor.crosshair.set()
        }
    }

    private func resizeCursor(for selected: SelectedAnnotation, anchor: CGPoint) -> NSCursor {
        if #available(macOS 15, *) {
            let b = selected.annotation.bounds
            let right = anchor.x < b.midX, top = anchor.y < b.midY
            let position: NSCursor.FrameResizePosition = top ? (right ? .topRight : .topLeft) : (right ? .bottomRight : .bottomLeft)
            return NSCursor.frameResize(position: position, directions: .all)
        }
        return NSCursor.crosshair
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        if inline != nil { commitInline(); return }
        window?.makeFirstResponder(self)
        guard let editor, let (page, point, viewPoint) = pagePoint(event) else { return super.mouseDown(with: event) }
        editor.textSelectionActive = false

        if let (selected, anchor) = resizeAnchor(at: viewPoint) {
            drag = .resize(selected, anchor: anchor, original: selected.annotation.bounds)
            return
        }

        // Clicking an existing annotation selects it whatever the tool, as in Preview.
        let existing = hit(point, on: page).map { SelectedAnnotation(annotation: $0, page: page) }
        pendingHit = nil
        let placesOnClick: Set<Tool> = [.note, .signature, .checkmark, .cross, .date, .stamp]
        if let existing, placesOnClick.contains(editor.tool) || (editor.tool == .text && existing.annotation.type != "FreeText") {
            editor.select(existing)
            if event.clickCount == 2 { editor.beginEditingSelected(); return }
            if Annotations.isMovable(existing.annotation) { drag = .move(existing, start: point, original: existing.annotation.bounds) }
            return
        }
        if editor.tool != .select, editor.tool != .eraser { pendingHit = existing }

        switch editor.tool {
        case .select:
            if let a = hit(point, on: page) {
                let selection = SelectedAnnotation(annotation: a, page: page)
                editor.select(selection)
                if event.clickCount == 2 { editor.beginEditingSelected(); return }
                if Annotations.isMovable(a) { drag = .move(selection, start: point, original: a.bounds) }
                return
            }
            editor.select(nil)
            super.mouseDown(with: event)
        case .highlight, .underline, .squiggly, .strikeout:
            editor.select(nil)
            super.mouseDown(with: event)
        case .text:
            if let a = hit(point, on: page), a.type == "FreeText" {
                editor.select(SelectedAnnotation(annotation: a, page: page))
                beginEditing(a, on: page)
            } else {
                editor.select(nil)
                beginNewText(at: point, on: page)
            }
        case .note:
            editor.select(nil)
            beginNewNote(at: point, on: page)
        case .signature:
            editor.placeSignature(at: point, on: page)
        case .checkmark, .cross, .date:
            editor.placeMark(editor.tool, at: point, on: page)
        case .stamp:
            editor.placeStamp(at: point, on: page)
        case .eraser:
            if let a = hit(point, on: page) { editor.erase(a, on: page) }
        case .polygon, .polyline, .cloudPolygon, .measurePerimeter, .measureArea:
            editor.select(nil)
            addPoint(point, on: page, finish: event.clickCount >= 2)
        case .pen, .marker, .rectangle, .oval, .line, .arrow, .doubleArrow, .redact, .link, .image, .snapshot,
             .formText, .formCheckbox, .formRadio, .formChoice, .measureDistance, .callout, .cloud:
            editor.select(nil)
            drag = .draw(page: page, start: point, stroke: [point])
        case .crop:
            drag = .crop(page: page, start: point)
            editor.cropDraft = nil
        }
    }

    // MARK: Polygon and polyline

    private func addPoint(_ point: CGPoint, on page: PDFPage, finish: Bool) {
        guard let editor else { return }
        if points?.page !== page { points = (page, []) }
        if !finish { points?.list.append(point) }
        let list = points?.list ?? []
        if finish {
            finishPointTool()
            return
        }
        showPreview(Annotations.polyline(list, closed: false, color: editor.strokeColor(for: editor.tool),
                                         lineWidth: editor.style(for: editor.tool).width), on: page)
    }

    /// Commits the points placed so far (needs at least two, three for a polygon).
    func finishPointTool() {
        guard let editor, let (page, list) = points else { return }
        points = nil
        showPreview(nil, on: nil)
        let closed = editor.tool.closesShape
        if list.count >= (closed ? 3 : 2) { editor.commitPolyline(list, closed: closed, on: page) }
    }

    func cancelPointTool() {
        guard points != nil else { return }
        points = nil
        showPreview(nil, on: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let editor, let drag else { return super.mouseDragged(with: event) }
        switch drag {
        case let .move(selected, start, original):
            guard let (_, point, _) = pagePoint(event, page: selected.page) else { return }
            NSCursor.closedHand.set()
            selected.annotation.bounds.origin = original.origin + (point - start)
            annotationsChanged(on: selected.page)
            editor.objectWillChange.send()
        case let .resize(selected, anchor, _):
            guard let (_, point, _) = pagePoint(event, page: selected.page) else { return }
            var rect = CGRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                              width: abs(point.x - anchor.x), height: abs(point.y - anchor.y))
            rect.size.width = max(rect.width, 8)
            rect.size.height = max(rect.height, 8)
            Annotations.resize(selected.annotation, to: rect)
            annotationsChanged(on: selected.page)
            editor.objectWillChange.send()
        case let .crop(page, start):
            guard let (_, point, _) = pagePoint(event, page: page) else { return }
            let media = page.bounds(for: .mediaBox)
            let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                              width: abs(point.x - start.x), height: abs(point.y - start.y)).intersection(media)
            editor.cropDraft = (page, rect)
        case let .draw(page, start, stroke):
            guard let (_, raw, _) = pagePoint(event, page: page) else { return }
            let point = constrained(raw, from: start, event: event)
            self.drag = .draw(page: page, start: start, stroke: stroke + [point])
            showPreview(makeAnnotation(editor, from: start, to: point, stroke: stroke + [point]), on: page)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = nil; showPreview(nil, on: nil) }
        guard let editor else { return super.mouseUp(with: event) }
        switch drag {
        case let .move(selected, _, original), let .resize(selected, _, original):
            let now = selected.annotation.bounds
            if now != original {
                Annotations.resize(selected.annotation, to: original)
                editor.setBounds(now, of: selected.annotation, on: selected.page, previous: original)
            }
            if case .move = drag { NSCursor.openHand.set() }
        case .crop:
            break
        case let .draw(page, start, stroke):
            showPreview(nil, on: nil)
            guard let (_, raw, _) = pagePoint(event, page: page) else { return }
            let point = constrained(raw, from: start, event: event)
            let large = abs(point.x - start.x) > 3 || abs(point.y - start.y) > 3
            let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
            if !large, let pending = pendingHit {
                editor.select(pending)
                pendingHit = nil
                return
            }
            switch editor.tool {
            case .image:
                DispatchQueue.main.async { editor.placeImage(in: large ? rect : CGRect(origin: point, size: .zero), on: page) }
            case .link:
                if large { DispatchQueue.main.async { editor.requestLink(in: rect, on: page) } }
            case .snapshot:
                if large { editor.snapshot(rect, on: page) }
            case .measureDistance:
                if large { editor.commitDistance(from: start, to: point, on: page) }
            case .callout:
                // Drag from what the callout points at to where its text goes.
                let boxCorner = large ? point : CGPoint(x: start.x + 40, y: start.y + 50)
                DispatchQueue.main.async { self.beginNewCallout(anchor: start, boxTopLeft: boxCorner, on: page) }
            case .cloud:
                if large {
                    let style = editor.style(for: .cloud)
                    editor.add(Annotations.cloud(rect: rect, color: editor.strokeColor(for: .cloud), lineWidth: style.width, fill: style.fill), to: page)
                }
            case .formText, .formCheckbox, .formRadio, .formChoice:
                if let kind = editor.tool.formKind { editor.addFormField(kind, in: large ? rect : CGRect(origin: point, size: .zero), on: page) }
            default:
                if large || Tool.pens.contains(editor.tool), let a = makeAnnotation(editor, from: start, to: point, stroke: stroke) {
                    editor.add(a, to: page)
                    if editor.tool == .redact { editor.select(SelectedAnnotation(annotation: a, page: page)) }
                }
            }
        case nil:
            super.mouseUp(with: event)
            guard let selection = currentSelection, !(selection.string ?? "").isEmpty else {
                if let pending = pendingHit { editor.select(pending); pendingHit = nil }
                return
            }
            if let type = editor.tool.markupType {
                editor.applyMarkup(type, to: selection)
            } else if editor.tool == .select {
                editor.textSelectionActive = true
            }
        }
    }

    private func makeAnnotation(_ editor: EditorController, from start: CGPoint, to point: CGPoint, stroke: [CGPoint]) -> PDFAnnotation? {
        let tool = editor.tool
        let style = editor.style(for: tool)
        let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        switch tool {
        case .pen, .marker:
            return Annotations.ink(strokes: [stroke], color: editor.strokeColor(for: tool), lineWidth: style.width)
        case .redact:
            return Annotations.redaction(bounds: rect, style: editor.redactionStyle)
        case .link, .image, .snapshot, .formText, .formCheckbox, .formRadio, .formChoice:
            let a = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
            a.color = .controlAccentColor
            let border = PDFBorder()
            border.lineWidth = 1
            border.style = .dashed
            border.dashPattern = [4, 3]
            a.border = border
            a.interiorColor = NSColor.controlAccentColor.withAlphaComponent(0.08)
            return a
        case .measureDistance, .callout:
            return Annotations.shape(tool == .callout ? .arrow : .line, from: tool == .callout ? point : start, to: tool == .callout ? start : point,
                                     color: editor.strokeColor(for: tool), lineWidth: tool == .callout ? 1.5 : style.width)
        case .cloud:
            return Annotations.cloud(rect: rect, color: editor.strokeColor(for: tool), lineWidth: style.width, fill: style.fill)
        default:
            guard let shape = tool.shape else { return nil }
            let a = Annotations.shape(shape, from: start, to: point, color: editor.strokeColor(for: tool), lineWidth: style.width)
            Annotations.setLineStyle(style.dash, of: a)
            if tool.usesFill, let fill = style.fill { a.interiorColor = fill.withAlphaComponent(style.opacity) }
            return a
        }
    }

    /// Shift keeps lines at 45° steps and boxes square.
    private func constrained(_ point: CGPoint, from start: CGPoint, event: NSEvent) -> CGPoint {
        guard event.modifierFlags.contains(.shift), let kind = editor?.tool.constraint else { return point }
        return Geometry.constrained(from: start, to: point, kind: kind)
    }

    private func showPreview(_ annotation: PDFAnnotation?, on page: PDFPage?) {
        if let preview, let owner = preview.page { owner.removeAnnotation(preview) }
        preview = annotation
        if let annotation, let page { page.addAnnotation(annotation) }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let editor, inline == nil else { return super.keyDown(with: event) }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // In Pages mode this view is hidden behind the grid but keeps keyboard focus; act on pages.
        if editor.mode == .pages {
            editor.handlePagesKey(event)
            return
        }
        switch event.keyCode {
        case 51, 117 where editor.selected != nil:
            editor.deleteSelected()
            return
        case 53:
            if points != nil { cancelPointTool() }
            else if editor.tool == .crop { editor.cropDraft = nil; editor.tool = .select }
            else if editor.selected != nil { editor.select(nil) }
            else if editor.textSelectionActive { clearSelection(); editor.textSelectionActive = false }
            else if editor.tool != .select { editor.tool = .select }
            return
        case 36 where points != nil:
            finishPointTool()
            return
        case 36 where editor.cropDraft != nil:
            editor.applyCrop(toAll: false)
            return
        case 36 where editor.selected != nil:
            editor.beginEditingSelected()
            return
        case 123, 124, 125, 126 where editor.selected != nil:
            let step: CGFloat = modifiers.contains(.shift) ? 10 : 1
            let delta: (CGFloat, CGFloat) = [123: (-step, 0), 124: (step, 0), 125: (0, -step), 126: (0, step)][event.keyCode]!
            editor.nudgeSelected(dx: delta.0, dy: delta.1)
            return
        default:
            break
        }
        if modifiers.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased().first,
           let tool = Tool.allCases.first(where: { $0.key == key }) {
            if editor.mode == .read {
                // Reading: letters only act on selected text, so a stray key never switches toolsets.
                if editor.textSelectionActive, tool.markupType != nil { editor.markSelection(with: tool) ; return }
                return super.keyDown(with: event)
            }
            editor.tool = tool
            return
        }
        super.keyDown(with: event)
    }

    // MARK: Clipboard

    @objc override func copy(_ sender: Any?) {
        if editor?.mode == .pages { editor?.copyPages(); return }
        if let editor, editor.selected != nil { editor.copySelectedAnnotation() } else { super.copy(sender) }
    }

    @objc func cut(_ sender: Any?) {
        if editor?.mode == .pages { editor?.cutPages(); return }
        editor?.copySelectedAnnotation(cut: true)
    }

    @objc func paste(_ sender: Any?) {
        if editor?.mode == .pages { editor?.insertFromClipboard(); return }
        if editor?.paste() != true { NSSound.beep() }
    }

    @objc func delete(_ sender: Any?) {
        if editor?.mode == .pages { editor?.deletePages(); return }
        editor?.deleteSelected()
    }

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(cut(_:)), #selector(delete(_:)): return editor?.selected != nil || (editor?.mode == .pages && !(editor?.selectedPages.isEmpty ?? true))
        case #selector(paste(_:)): return editor?.annotationClipboard != nil || NSImage.canInit(with: .general)
        case #selector(copy(_:)): return editor?.selected != nil || editor?.mode == .pages || !(currentSelection?.string ?? "").isEmpty
        default: return true
        }
    }

    // MARK: Inline text editing

    func beginNewText(at point: CGPoint, on page: PDFPage) {
        guard let editor else { return }
        let style = editor.style(for: .text)
        startInline(kind: .text, page: page, anchor: point, text: "", fontSize: style.width, color: style.color) { [weak self] text in
            guard let self, let editor = self.editor, !text.isEmpty else { return }
            editor.commitNewText(text, at: point, on: page)
        }
    }

    func beginNewCallout(anchor: CGPoint, boxTopLeft: CGPoint, on page: PDFPage) {
        guard let editor else { return }
        let style = editor.style(for: .callout)
        startInline(kind: .text, page: page, anchor: boxTopLeft, text: "", fontSize: style.width, color: style.color) { [weak self] text in
            guard let self, let editor = self.editor, !text.isEmpty else { return }
            editor.commitCallout(text, anchor: anchor, boxTopLeft: boxTopLeft, on: page)
        }
    }

    func beginNewNote(at point: CGPoint, on page: PDFPage) {
        startInline(kind: .note, page: page, anchor: point, text: "", fontSize: 12, color: .black) { [weak self] text in
            guard let self, let editor = self.editor, !text.isEmpty else { return }
            editor.commitNewNote(text, at: point, on: page)
        }
    }

    func beginEditing(_ annotation: PDFAnnotation, on page: PDFPage) {
        if let callout = annotation as? CalloutAnnotation {
            callout.shouldDisplay = false
            annotationsChanged(on: page)
            startInline(kind: .text, page: page, anchor: CGPoint(x: callout.box.minX + 4, y: callout.box.maxY - 3), text: callout.text,
                        fontSize: callout.fontSize, color: callout.color) { [weak self] text in
                guard let self, let editor = self.editor else { return }
                callout.shouldDisplay = true
                self.annotationsChanged(on: page)
                if text.isEmpty { editor.remove(callout, from: page) }
                else if text != callout.text { editor.setCalloutText(text, of: callout, on: page) }
            }
            return
        }
        let isText = annotation.type == "FreeText"
        let anchor = isText ? CGPoint(x: annotation.bounds.minX, y: annotation.bounds.maxY) : CGPoint(x: annotation.bounds.midX, y: annotation.bounds.midY)
        if isText { annotation.shouldDisplay = false; annotationsChanged(on: page) }
        startInline(kind: isText ? .text : .note, page: page, anchor: anchor, text: annotation.contents ?? "",
                    fontSize: annotation.font?.pointSize ?? 12, color: annotation.fontColor ?? .black) { [weak self] text in
            guard let self, let editor = self.editor else { return }
            annotation.shouldDisplay = true
            self.annotationsChanged(on: page)
            if text.isEmpty { editor.remove(annotation, from: page) }
            else if text != annotation.contents { editor.setContents(text, of: annotation, on: page) }
        }
    }

    private func startInline(kind: InlineTextEditor.Kind, page: PDFPage, anchor: CGPoint, text: String,
                             fontSize: CGFloat, color: NSColor, commit: @escaping (String) -> Void) {
        commitInline()
        let viewAnchor = convert(anchor, from: page)
        let editorView = InlineTextEditor(kind: kind, fontSize: fontSize * scaleFactor, color: color, text: text)
        editorView.onFinish = { [weak self, weak editorView] result in
            guard let self, let editorView, self.inline === editorView else { return }
            self.inline = nil
            editorView.removeFromSuperview()
            self.window?.makeFirstResponder(self)
            if let result { commit(result.trimmingCharacters(in: .whitespacesAndNewlines)) } else { commit(text) }
        }
        addSubview(editorView)
        editorView.place(at: viewAnchor, flipped: isFlipped)
        inline = editorView
        window?.makeFirstResponder(editorView)
    }

    func commitInline() {
        inline?.finish(cancelled: false)
    }
}

/// A borderless text view placed over the page while a text box or note is being typed.
final class InlineTextEditor: NSTextView, NSTextViewDelegate {
    enum Kind { case text, note }

    let kind: Kind
    var onFinish: ((String?) -> Void)?
    private var anchor: CGPoint = .zero
    private var anchorFlipped = false
    private var finished = false

    init(kind: Kind, fontSize: CGFloat, color: NSColor, text: String) {
        self.kind = kind
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: kind == .note ? 220 : 2000, height: 1_000_000))
        container.widthTracksTextView = kind == .note
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        delegate = self
        isRichText = false
        allowsUndo = true
        font = NSFont.systemFont(ofSize: max(fontSize, 9))
        textColor = color
        insertionPointColor = .controlAccentColor
        string = text
        textContainerInset = CGSize(width: 6, height: 5)
        isVerticallyResizable = true
        isHorizontallyResizable = kind == .text
        drawsBackground = true
        backgroundColor = kind == .note ? NSColor(srgbRed: 1, green: 0.96, blue: 0.72, alpha: 1) : NSColor.white.withAlphaComponent(0.92)
        wantsLayer = true
        layer?.cornerRadius = kind == .note ? 8 : 4
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        shadow = {
            let s = NSShadow()
            s.shadowBlurRadius = 8
            s.shadowColor = NSColor.black.withAlphaComponent(0.2)
            s.shadowOffset = CGSize(width: 0, height: -2)
            return s
        }()
        selectAll(nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func place(at point: CGPoint, flipped: Bool) {
        anchor = point
        anchorFlipped = flipped
        resize()
    }

    private func resize() {
        guard let layout = layoutManager, let container = textContainer else { return }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).size
        let width = kind == .note ? 220 : max(used.width + 14, 120)
        let height = max(used.height + 12, (font?.pointSize ?? 14) + 14)
        let origin = kind == .note
            ? CGPoint(x: anchor.x + 14, y: anchorFlipped ? anchor.y - 10 : anchor.y + 10 - height)
            : CGPoint(x: anchor.x - 6, y: anchorFlipped ? anchor.y - 3 : anchor.y + 3 - height)
        frame = CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    override func didChangeText() {
        super.didChangeText()
        resize()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { insertNewlineIgnoringFieldEditor(nil); return true }
            finish(cancelled: false)
            return true
        case #selector(cancelOperation(_:)):
            finish(cancelled: true)
            return true
        default:
            return false
        }
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { DispatchQueue.main.async { [weak self] in self?.finish(cancelled: false) } }
        return result
    }

    func finish(cancelled: Bool) {
        guard !finished else { return }
        finished = true
        onFinish?(cancelled ? nil : string)
    }
}

struct PDFKitView: NSViewRepresentable {
    let editor: EditorController

    func makeNSView(context: Context) -> EditorPDFView {
        let view = EditorPDFView()
        view.autoScales = true
        view.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1)
                : NSColor(srgbRed: 0.91, green: 0.91, blue: 0.92, alpha: 1)
        }
        view.pageShadowsEnabled = true
        view.pageBreakMargins = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        editor.attach(view)
        return view
    }

    func updateNSView(_ view: EditorPDFView, context: Context) {}
}
