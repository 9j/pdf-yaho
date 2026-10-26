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
#endif

