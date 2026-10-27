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
            case "click":
                clickQA(block, on: page)
            default:
                selectedContent = block
            }
        }
    }
}

extension EditorController {
    /// Clicks a paragraph, types and clicks away using in-process events (no system input), logging each step.
    func clickQA(_ block: ContentBlock, on page: PDFPage) {
        guard let view = pdfView else { return }
        let log = { (line: String) in
            let url = URL(fileURLWithPath: "/tmp/pdfyaho-qa.log")
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? (text + line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        func event(_ type: NSEvent.EventType, at viewPoint: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(viewPoint, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let target = view.convert(CGPoint(x: block.bounds.minX + 20, y: block.bounds.maxY - 6), from: page)
        log("click at \(target) block \(block.text.prefix(30))")
        let windowPoint = view.convert(target, to: nil)
        if let content = view.window?.contentView {
            let hit = content.hitTest(content.convert(windowPoint, from: nil))
            log("hitTest → \(hit.map { String(describing: type(of: $0)) } ?? "nil") isPDFView=\(hit === view)")
        }
        // Deliver to whatever view is on top, as a real click is (sendEvent would be eaten as an activation click
        // because the QA app runs in the background).
        let hit = view.window?.contentView.flatMap { $0.hitTest($0.convert(windowPoint, from: nil)) } ?? view
        hit.mouseDown(with: event(.leftMouseDown, at: target))
        hit.mouseUp(with: event(.leftMouseUp, at: target))
        log("after click: inline=\(view.isEditingInline) responder=\(String(describing: view.window?.firstResponder))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            log("after 1s: inline=\(view.isEditingInline) responder=\(String(describing: view.window?.firstResponder))")
            (view.window?.firstResponder as? NSTextView)?.insertText("수정됨 ", replacementRange: NSRange(location: 0, length: 0))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let away = CGPoint(x: view.bounds.midX, y: 30)
                let awayHit = view.window?.contentView.flatMap { $0.hitTest($0.convert(view.convert(away, to: nil), from: nil)) } ?? view
                awayHit.mouseDown(with: event(.leftMouseDown, at: away))
                awayHit.mouseUp(with: event(.leftMouseUp, at: away))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    let text = self.document.page(at: self.document.index(for: page) == NSNotFound ? 0 : 0)?.string ?? ""
                    log("result contains 수정됨: \(text.contains("수정됨"))")
                }
            }
        }
    }
}

extension EditorController {
    /// Opens a sheet by name for screenshots: signature, initials, password, reduce, images, pageSize, split,
    /// labels, link, findRedact, scale, header, properties.
    func openSheetQA(_ name: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            switch name {
            case "signature": signaturePadInitials = false; showSignaturePad = true
            case "initials": signaturePadInitials = true; showSignaturePad = true
            case "password": showPasswordSheet = true
            case "reduce": showReduceSize = true
            case "images": showExportImages = true
            case "pageSize": showPageSize = true
            case "split": showSplit = true
            case "labels": showPageLabels = true
            case "findRedact": showFindRedact = true
            case "scale": showMeasureScale = true
            case "header": headerFooterPreset = .custom
            case "properties": showProperties = true
            default: break
            }
        }
    }
}

extension EditorController {
    /// Runs comma-separated steps a second apart (a mode name, or tool:<name>) and logs whether the signature pad opened.
    func runStepsQA(_ steps: String) {
        let url = URL(fileURLWithPath: "/tmp/pdfyaho-qa.log")
        func log(_ line: String) {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? (text + line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        for (i, step) in steps.split(separator: ",").map(String.init).enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + Double(i)) { [self] in
                if step.hasPrefix("tool:"), let tool = Tool(rawValue: String(step.dropFirst(5))) { self.tool = tool }
                else if step == "dismiss" { showSignaturePad = false }
                else if step == "rotate" {
                    rotate(90)
                    let doc = pdfView?.window.flatMap { NSDocumentController.shared.document(for: $0) }
                    log("right after rotate: edited=\(doc?.isDocumentEdited as Any) undo=\(undoManager?.canUndo as Any) docUndo=\(doc?.undoManager?.canUndo as Any) same=\(doc?.undoManager === undoManager)")
                }
                else if step == "undo" { undoManager?.undo() }
                else if step == "mark" {
                    let doc = pdfView?.window.flatMap { NSDocumentController.shared.document(for: $0) }
                    doc?.updateChangeCount(.changeDone)
                    log("mark: edited=\(doc?.isDocumentEdited as Any) grouping=\(undoManager?.groupingLevel as Any) byEvent=\(undoManager?.groupsByEvent as Any)")
                }
                else if step == "check" {
                    let doc = pdfView?.window.flatMap { NSDocumentController.shared.document(for: $0) }
                    log("check: edited=\(doc?.isDocumentEdited as Any) unautosaved=\(doc?.hasUnautosavedChanges as Any) title=\(pdfView?.window?.title ?? "") edited-dot=\(pdfView?.window?.isDocumentEdited as Any)")
                }
                else if step == "close" {
                    let doc = pdfView?.window.flatMap { NSDocumentController.shared.document(for: $0) }
                    log("before close: edited=\(doc?.isDocumentEdited as Any) autosaves=\(doc.map { type(of: $0).autosavesInPlace } as Any) class=\(doc.map { String(describing: type(of: $0)) } ?? "nil") confirm=\(UserDefaults.standard.bool(forKey: "NSCloseAlwaysConfirmsChanges"))")
                    pdfView?.window?.performClose(nil)
                }
                else if step.hasPrefix("key:"), let view = pdfView, let window = view.window {
                    window.makeFirstResponder(view)
                    let chars = String(step.dropFirst(4))
                    if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                    windowNumber: window.windowNumber, context: nil, characters: chars,
                                                    charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 5) {
                        view.keyDown(with: event)
                    }
                }
                else if let mode = EditorMode(rawValue: step) { self.mode = mode }
                log("\(step) → mode \(mode) tool \(tool) pad \(showSignaturePad)")
            }
        }
    }
}

extension EditorController {
    /// Stages a scene on the demo workshop PDF for marketing screenshots: edit, annotate, sign or pages.
    func stageShotQA(_ shot: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [self] in
            pdfView?.window?.setFrame(CGRect(x: 80, y: 60, width: 1440, height: 900), display: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
                guard let first = document.page(at: 0) else { return }
                let zoomOverride = ProcessInfo.processInfo.environment["PDFYAHO_QA_ZOOM"].flatMap(Double.init)
                zoom(to: zoomOverride.map { CGFloat($0) } ?? (shot == "edit" ? 1.15 : 0.95))
                pdfView?.go(to: PDFDestination(page: first, at: CGPoint(x: 0, y: first.bounds(for: .cropBox).maxY)))
                switch shot {
                case "edit":
                    mode = .edit
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                        loadContent(on: first, force: true)
                        guard let block = contentBlocks.first(where: { $0.text.hasPrefix("한 해의") }) else { return }
                        selectedContent = block
                        pdfView?.beginContentEditing(block, on: first)
                        (pdfView?.window?.firstResponder as? NSTextView)?.insertText(" 저녁에는 산장 마당에서 바비큐도 준비합니다.",
                                                                                     replacementRange: NSRange(location: block.text.utf16.count, length: 0))
                    }
                case "annotate":
                    mode = .annotate
                    for phrase in ["4월 4일까지", "등산화와 물은 꼭"] {
                        if let match = document.findString(phrase, withOptions: []).first { applyMarkup(.highlight, to: match) }
                    }
                    if let match = document.findString("둘레길 코스", withOptions: []).first { applyMarkup(.underline, to: match, tool: .underline) }
                    add(CalloutAnnotation.make(text: "비 오면 실내 일정으로?", box: CGRect(x: 360, y: 250, width: 170, height: 30),
                                               anchor: CGPoint(x: 330, y: 215), color: Palette.swatches[2], fontSize: 12), to: first)
                    commitNewNote("집결 시간 8시 50분으로 당길까요?", at: CGPoint(x: 540, y: 760), on: first)
                    tool = .highlight
                case "sign":
                    mode = .fillSign
                    if let signature = SavedSignature.typed("Yaho Kim", font: NSFont(name: "Snell Roundhand", size: 64) ?? .systemFont(ofSize: 64)) {
                        addSignature(signature)
                    }
                    if let last = document.page(at: 3) {
                        // Write each answer just under its label, on the form's line.
                        let doc = document
                        let label = { (text: String) -> CGRect? in
                            doc.findString(text, withOptions: []).first { $0.pages.first === last }?.bounds(for: last)
                        }
                        for (field, value) in [("이름", "김야호"), ("소속 팀", "디자인팀"), ("코스 선택", "백운대"), ("알레르기", "없음")] {
                            if let r = label(field) { commitNewText(value, at: CGPoint(x: r.minX + 4, y: r.minY - 3), on: last) }
                        }
                        if let r = label("서명") { placeSignature(at: CGPoint(x: r.minX + 95, y: r.minY - 14), on: last) }
                        goToPage(3)
                    }
                    select(nil)
                case "pages":
                    mode = .pages
                    selectedPages = [1, 2]
                default: break
                }
            }
        }
    }
}

extension EditorController {
    /// Plays a scripted session (edit, highlight, sign, pages) on the demo workshop PDF for a screen recording,
    /// logging each step with its time and window position (points, top-left origin) to /tmp/yaho-video/events.json.
    func runDemoQA(after delay: Double) {
        var events: [[String: Any]] = []
        func windowPoint(_ point: CGPoint, on page: PDFPage) -> CGPoint? {
            guard let view = pdfView, let window = view.window else { return nil }
            let p = view.convert(view.convert(point, from: page), to: nil)
            return CGPoint(x: p.x, y: window.frame.height - p.y)
        }
        func log(_ name: String, _ point: CGPoint? = nil) {
            var event: [String: Any] = ["t": Date().timeIntervalSince1970, "name": name]
            if let point, point.x.isFinite, point.y.isFinite { event["x"] = point.x; event["y"] = point.y }
            events.append(event)
            if let data = try? JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/yaho-video/events.json"))
            }
        }
        func at(_ t: Double, _ body: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + delay + t, execute: body) }

        pdfView?.window?.setFrame(CGRect(x: 80, y: 60, width: 1440, height: 900), display: true)
        if let signature = SavedSignature.typed("Yaho Kim", font: NSFont(name: "Snell Roundhand", size: 64) ?? .systemFont(ofSize: 64)) {
            signatureLibrary = [signature]
            activeSignatureID = signature.id
        }
        guard let first = document.page(at: 0) else { return }
        at(-1.5) { [self] in
            zoom(to: 1.15)
            pdfView?.go(to: PDFDestination(page: first, at: CGPoint(x: 0, y: first.bounds(for: .cropBox).maxY)))
        }
        at(0) { log("start") }

        // 1. Edit a paragraph in place.
        at(1.6) { [self] in log("click-edit-tab"); mode = .edit }
        let typed = " 저녁에는 산장 마당에서 바비큐도 준비합니다."
        at(3.0) { [self] in
            loadContent(on: first, force: true)
            guard let block = contentBlocks.first(where: { $0.text.hasPrefix("한 해의") }) else { return }
            log("click-paragraph", windowPoint(CGPoint(x: block.bounds.maxX - 40, y: block.bounds.minY + 6), on: first))
            selectedContent = block
            pdfView?.beginContentEditing(block, on: first)
        }
        for (i, char) in typed.enumerated() {
            at(3.6 + Double(i) * 0.09) { [self] in
                if i == 0 { log("type-start") }
                (pdfView?.window?.firstResponder as? NSTextView)?.insertText(String(char), replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }
        let typedEnd = 3.6 + Double(typed.count) * 0.09
        at(typedEnd + 0.6) { [self] in
            log("click-away", windowPoint(CGPoint(x: 120, y: 120), on: first))
            pdfView?.commitInline()
            selectedContent = nil
        }

        // 2. Highlight and comment.
        let annotateAt = typedEnd + 2.0
        at(annotateAt) { [self] in log("click-annotate-tab"); mode = .annotate; tool = .highlight }
        for (k, phrase) in ["4월 4일까지", "등산화와 물은 꼭"].enumerated() {
            let t = annotateAt + 1.2 + Double(k) * 1.6
            at(t) { [self] in
                guard let match = document.findString(phrase, withOptions: []).first else { return }
                guard let page = match.pages.first else { return }
                let b = match.bounds(for: page)
                log("drag-start", windowPoint(CGPoint(x: b.minX, y: b.midY), on: page))
            }
            at(t + 0.7) { [self] in
                guard let match = document.findString(phrase, withOptions: []).first else { return }
                guard let page = match.pages.first else { return }
                let b = match.bounds(for: page)
                log("drag-end", windowPoint(CGPoint(x: b.maxX, y: b.midY), on: page))
                applyMarkup(.highlight, to: match)
            }
        }
        at(annotateAt + 4.8) { [self] in
            log("click-callout", windowPoint(CGPoint(x: 330, y: 215), on: first))
            add(CalloutAnnotation.make(text: "비 오면 실내 일정으로?", box: CGRect(x: 360, y: 250, width: 170, height: 30),
                                       anchor: CGPoint(x: 330, y: 215), color: Palette.swatches[2], fontSize: 12), to: first)
        }

        // 3. Fill in the form and sign.
        let signAt = annotateAt + 7.0
        at(signAt) { [self] in log("click-sign-tab"); mode = .fillSign; tool = .text; goToPage(3) }
        let fields = [("이름", "김야호"), ("소속 팀", "디자인팀"), ("코스 선택", "백운대")]
        for (k, field) in fields.enumerated() {
            at(signAt + 1.2 + Double(k) * 0.9) { [self] in
                guard let last = document.page(at: 3),
                      let r = document.findString(field.0, withOptions: []).first(where: { $0.pages.first === last })?.bounds(for: last)
                else { return }
                let point = CGPoint(x: r.minX + 4, y: r.minY - 3)
                log("click-field", windowPoint(CGPoint(x: point.x + 20, y: point.y - 8), on: last))
                commitNewText(field.1, at: point, on: last)
                select(nil)
            }
        }
        at(signAt + 4.4) { [self] in
            guard let last = document.page(at: 3),
                  let r = document.findString("서명", withOptions: []).first(where: { $0.pages.first === last })?.bounds(for: last)
            else { return }
            let point = CGPoint(x: r.minX + 95, y: r.minY - 14)
            log("click-signature", windowPoint(point, on: last))
            tool = .signature
            placeSignature(at: point, on: last)
            select(nil)
        }

        // 4. Organize pages.
        let pagesAt = signAt + 6.4
        at(pagesAt) { [self] in log("click-pages-tab"); mode = .pages; selectedPages = [] }
        at(pagesAt + 1.2) { [self] in log("click-page-2"); selectedPages = [1] }
        at(pagesAt + 1.9) { [self] in log("cmd-click-page-3"); selectedPages = [1, 2] }
        at(pagesAt + 2.8) { [self] in log("click-rotate"); rotate(90) }
        at(pagesAt + 4.2) { log("end") }
    }
}

@MainActor
enum WindowQA {
    /// PDFYAHO_QA_HOMECLOSE: closes Home 2 s after launch and logs which windows are visible afterwards.
    static func run() {
        guard ProcessInfo.processInfo.environment["PDFYAHO_QA_HOMECLOSE"] != nil else { return }
        let url = URL(fileURLWithPath: "/tmp/pdfyaho-qa.log")
        func log(_ line: String) {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? (text + line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        func visible() -> String { NSApp.windows.filter(\.isVisible).map { $0.title.isEmpty ? String(describing: type(of: $0)) : $0.title }.joined(separator: " | ") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            log("before close: \(visible())")
            NSApp.windows.first { $0.title == "Home" && $0.isVisible }?.performClose(nil)
        }
        for t in [3.0, 5.0, 8.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { log("t=\(t): \(visible())") }
        }
    }
}

/// PDFYAHO_QA_SCROLL=<seconds>: scrolls the document at a steady speed on the display's clock
/// and logs frame pacing, so scrolling smoothness can be measured without input events.
final class ScrollProbe: NSObject {
    private weak var editor: EditorController?
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var start: CFTimeInterval = 0
    private var intervals: [Double] = []
    private var duration: Double = 0
    private var expected: Double = 1.0 / 60
    private var direction: CGFloat = 1
    private static var current: ScrollProbe?

    @MainActor static func run(_ editor: EditorController, seconds: Double) {
        guard current == nil, editor.fileURL != nil, let view = editor.pdfView else { return }
        // Occluded windows get no display-link callbacks; show it without taking key focus.
        view.window?.orderFrontRegardless()
        let probe = ScrollProbe()
        probe.editor = editor
        probe.duration = seconds
        probe.link = view.displayLink(target: probe, selector: #selector(tick(_:)))
        probe.link?.add(to: .main, forMode: .common)
        current = probe
    }

    func note(_ line: String) {
        let url = URL(fileURLWithPath: "/tmp/pdfyaho-qa.log")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (text + line + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        expected = max(1.0 / 240, link.targetTimestamp - link.timestamp)
        if last == 0 { start = now } else { intervals.append(now - last) }
        last = now
        if now - start >= duration { finish(); return }
        guard let clip = editor?.pdfView?.scrollView?.contentView, let docView = clip.documentView else { return }
        // About two screens per second, bouncing at either end.
        var origin = clip.bounds.origin
        let step = 1800 * expected * direction
        origin.y += clip.isFlipped ? step : -step
        let maxY = docView.frame.height - clip.bounds.height
        if origin.y < 0 || origin.y > maxY { direction *= -1; origin.y = min(max(0, origin.y), maxY) }
        clip.scroll(to: origin)
        clip.superview.flatMap { $0 as? NSScrollView }?.reflectScrolledClipView(clip)
    }

    @MainActor private func finish() {
        link?.invalidate()
        let sorted = intervals.sorted()
        let budget = expected * 1.5
        let dropped = intervals.filter { $0 > budget }.count
        let missed = intervals.reduce(0) { $0 + max(0, Int(($1 / expected).rounded()) - 1) }
        let p = { (q: Double) in sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * q))] * 1000 }
        let line = String(format: "scroll: frames=%d slow=%d missed=%d target=%.1fms p50=%.1f p95=%.1f p99=%.1f max=%.1f",
                          intervals.count, dropped, missed, expected * 1000, p(0.5), p(0.95), p(0.99), (sorted.last ?? 0) * 1000)
        var elapsed = 0.0
        let slow = intervals.compactMap { i -> String? in
            elapsed += i
            return i > budget ? String(format: "%.2fs:%.0fms", elapsed, i * 1000) : nil
        }
        note(line)
        note("slow frames: " + slow.joined(separator: " "))
        ScrollProbe.current = nil
    }
}

extension EditorController {
    /// PDFYAHO_QA_SEARCH=<query>: searches 2.5 s after opening and logs when results arrive.
    func runSearchQA(_ query: String) {
        guard fileURL != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [self] in
            let start = Date()
            var firstAt: Double?
            searchText = query
            search(remember: false)
            @MainActor func poll() {
                if firstAt == nil, !searchResults.isEmpty { firstAt = Date().timeIntervalSince(start) }
                if searching { DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: poll); return }
                let line = String(format: "search %@: %d results, first after %.2fs, done after %.2fs",
                                  query, searchResults.count, firstAt ?? -1, Date().timeIntervalSince(start))
                let url = URL(fileURLWithPath: "/tmp/pdfyaho-qa.log")
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                try? (text + line + "\n").write(to: url, atomically: true, encoding: .utf8)
            }
            poll()
        }
    }

    /// PDFYAHO_QA_SELECT=<phrase>: selects the first match 2 s after opening so the text menu shows.
    func runSelectQA(_ phrase: String) {
        guard fileURL != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
            guard let match = document.findString(phrase, withOptions: []).first else { return }
            pdfView?.go(to: match)
            pdfView?.setCurrentSelection(match, animate: false)
            textSelectionActive = true
        }
    }
}
#endif
