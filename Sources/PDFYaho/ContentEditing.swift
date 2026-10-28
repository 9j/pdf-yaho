import PDFKit
import PDFYahoCore
import SwiftUI
import UniformTypeIdentifiers

/// Edit mode: changing the text and images that make up a page, rather than annotating over it.
/// Each edit rewrites one page through PDFium and swaps it in, so undo restores the old page.
extension EditorController {
    func enterEditMode() {
        guard mode == .edit else { return }
        guard ContentEditor.isAvailable else {
            showToast("Editing page content needs PDFium — run scripts/fetch-pdfium.sh and rebuild", kind: .warning)
            return
        }
        if let page = document.page(at: currentPageIndex) { loadContent(on: page) }
        if contentBlocks.isEmpty, (document.page(at: currentPageIndex)?.string ?? "").isEmpty {
            showToast("This page has no editable text — scanned pages need Recognize Text first", kind: .info)
        }
    }

    func clearContent() {
        pdfView?.commitInline()
        contentBlocks = []
        contentPage = nil
        selectedContent = nil
        hoveredContent = nil
        contentDragFrame = nil
        editingContent = nil
    }

    /// Reads the blocks of `page` unless they are already loaded.
    func loadContent(on page: PDFPage, force: Bool = false) {
        guard mode == .edit, force || page !== contentPage else { return }
        contentPage = page
        selectedContent = nil
        hoveredContent = nil
        contentBlocks = PDFOps.singlePageData(page).map { ContentEditor.blocks(of: $0) } ?? []
    }

    /// The innermost block under `point`, loading the page's blocks first.
    func contentBlock(at point: CGPoint, on page: PDFPage) -> ContentBlock? {
        loadContent(on: page)
        // Wide enough around a paragraph to grab its outline and move it.
        let slack = 6 / max(scale, 0.1)
        return contentBlocks
            .filter { $0.bounds.insetBy(dx: -slack, dy: -slack).contains(point) }
            .min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }

    func contentFrame(_ block: ContentBlock) -> CGRect? {
        contentPage.flatMap { viewRect(block.bounds, on: $0) }
    }

    // MARK: Edits

    /// Runs `edit` on a fresh one-page copy of `page` and swaps the result in as one undoable step.
    @discardableResult
    private func editContent(_ actionName: String, on page: PDFPage, _ edit: (Data) -> Data?) -> PDFPage? {
        let index = document.index(for: page)
        guard index != NSNotFound, let data = PDFOps.singlePageData(page), let result = edit(data),
              let replacement = PDFOps.editablePage(fromPDFData: result)
        else {
            showToast("Couldn't change this part of the page", kind: .warning)
            return nil
        }
        replacePage(at: index, with: replacement, actionName: actionName)
        return replacement
    }

    /// Swaps one page for another, keeping the view where it was.
    func replacePage(at index: Int, with page: PDFPage, actionName: String) {
        guard let old = document.page(at: index) else { return }
        let visible = pdfView?.currentDestination
        select(nil)
        document.removePage(at: index)
        document.insert(page, at: index)
        registerUndo(actionName) { $0.replacePage(at: index, with: old, actionName: actionName) }
        changed([page])
        if let visible, visible.page === old || visible.page === page {
            pdfView?.go(to: PDFDestination(page: page, at: visible.point))
        }
        if mode == .edit { loadContent(on: page, force: true) }
    }

    /// Selects the block that now sits where `bounds` was, after the page was rebuilt.
    private func reselect(near bounds: CGRect) {
        selectedContent = contentBlocks
            .filter { $0.bounds.intersects(bounds) }
            .min { abs($0.bounds.minX - bounds.minX) + abs($0.bounds.maxY - bounds.maxY)
                < abs($1.bounds.minX - bounds.minX) + abs($1.bounds.maxY - bounds.maxY) }
    }

    func replaceContentText(_ block: ContentBlock, on page: PDFPage, with text: String, style: TextStyle? = nil) {
        let style = style ?? block.style
        guard text != block.text || style != block.style else { return }
        guard editContent(text.isEmpty ? "Delete Text" : "Edit Text", on: page, {
            ContentEditor.replaceText(of: block, with: text, style: style, of: $0)
        }) != nil else { return }
        if !text.isEmpty { reselect(near: block.bounds) }
    }

    /// Restyles the selected text block (font, size, colour) without changing its words.
    func restyleSelectedContent(_ change: (inout TextStyle) -> Void) {
        guard let block = selectedContent, block.kind == .text, let page = contentPage else {
            change(&contentTextStyle)
            return
        }
        var style = block.style
        change(&style)
        contentTextStyle = style
        replaceContentText(block, on: page, with: block.text, style: style)
    }

    func addContentText(_ text: String, at topLeft: CGPoint, on page: PDFPage) {
        guard !text.isEmpty else { return }
        let style = contentTextStyle
        guard editContent("Add Text", on: page, { ContentEditor.addText(text, style: style, at: topLeft, of: $0) }) != nil else { return }
        reselect(near: CGRect(x: topLeft.x, y: topLeft.y - style.fontSize, width: style.fontSize, height: style.fontSize))
    }

    func moveContent(_ block: ContentBlock, on page: PDFPage, to bounds: CGRect) {
        guard bounds != block.bounds else { return }
        guard editContent("Move", on: page, { ContentEditor.move(block, to: bounds, of: $0) }) != nil else { return }
        reselect(near: bounds)
    }

    func nudgeContent(dx: CGFloat, dy: CGFloat) {
        guard let block = selectedContent, let page = contentPage else { return }
        moveContent(block, on: page, to: block.bounds.offsetBy(dx: dx, dy: dy))
    }

    func deleteSelectedContent() {
        guard let block = selectedContent, let page = contentPage else { return }
        editContent(block.kind == .image ? "Delete Image" : "Delete Text", on: page) { ContentEditor.remove([block], of: $0) }
        selectedContent = nil
    }

    func replaceSelectedContentImage() {
        guard let block = selectedContent, block.kind == .image, let page = contentPage,
              let url = Prompt.open([.image], multiple: false, title: "Replace Image").first,
              let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        guard editContent("Replace Image", on: page, { ContentEditor.replaceImage(of: block, with: image, of: $0) }) != nil else { return }
        reselect(near: block.bounds)
    }

    func saveSelectedContentImage() {
        guard let block = selectedContent, block.kind == .image, let page = contentPage,
              let data = PDFOps.singlePageData(page), let image = ContentEditor.image(of: block, of: data),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
              let url = Prompt.save(.png, name: "\(title) image.png", title: "Save Image")
        else { return }
        guard (try? png.write(to: url)) != nil else { Prompt.error("Could not save the image."); return }
        showToast("Saved \(url.lastPathComponent)", url: url)
    }

    func copySelectedContentText() {
        guard let block = selectedContent, block.kind == .text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(block.text, forType: .string)
        showToast("Copied text", kind: .info)
    }

    /// Asks for an image and places it as page content in `rect` (or at its natural size at a point).
    func addContentImage(in rect: CGRect, on page: PDFPage) {
        guard let url = Prompt.open([.image], multiple: false, title: "Add Image").first,
              let nsImage = NSImage(contentsOf: url), let image = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        var target = rect
        if rect.width < 4 || rect.height < 4 {
            // A click places the image at up to 200pt wide, keeping its proportions.
            let width = min(200, nsImage.size.width)
            let height = width * nsImage.size.height / max(nsImage.size.width, 1)
            target = CGRect(x: rect.minX, y: rect.minY - height, width: width, height: height)
        } else {
            target = ContentEditorGeometry.aspectFit(CGSize(width: image.width, height: image.height), in: rect)
        }
        guard editContent("Add Image", on: page, { ContentEditor.addImage(image, in: target, of: $0) }) != nil else { return }
        tool = .editContent
        reselect(near: target)
    }
}

enum ContentEditorGeometry {
    static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        let scale = min(rect.width / max(size.width, 1), rect.height / max(size.height, 1))
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
    }
}
