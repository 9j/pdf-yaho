import PDFKit
import PagecraftCore
import SwiftUI

/// Outlines of the editable text and images on the page, the selected block's handles and its action bar.
struct ContentEditOverlay: View {
    @ObservedObject var editor: EditorController
    let size: CGSize

    var body: some View {
        let _ = editor.overlayTick
        ZStack(alignment: .topLeading) {
            ForEach(editor.contentBlocks) { block in
                if block != editor.editingContent, block != editor.selectedContent, let frame = editor.contentFrame(block) {
                    let hovered = block == editor.hoveredContent
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.accentColor.opacity(hovered ? 0.85 : 0.3), style: StrokeStyle(lineWidth: 1, dash: hovered ? [] : [4, 3]))
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(hovered ? 0.06 : 0)))
                        .frame(width: frame.width + 6, height: frame.height + 6)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                }
            }
            if let drag = editor.contentDragFrame, let page = editor.contentPage, let frame = editor.viewRect(drag, on: page) {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.08)))
                    .frame(width: frame.width + 6, height: frame.height + 6)
                    .position(x: frame.midX, y: frame.midY)
                    .allowsHitTesting(false)
            }
            if let block = editor.selectedContent, block != editor.editingContent, editor.contentDragFrame == nil,
               let frame = editor.contentFrame(block) {
                SelectionChrome(frame: frame.insetBy(dx: -2, dy: -2), resizable: block.kind == .image)
                ContentContextBar(editor: editor, block: block)
                    .fixedSize()
                    .position(x: min(max(frame.midX, 140), size.width - 140),
                              y: frame.minY > 60 ? frame.minY - 30 : min(frame.maxY + 30, size.height - 80))
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(.snappy(duration: 0.15), value: editor.selectedContent)
    }
}

/// Actions for the selected text paragraph or image.
private struct ContentContextBar: View {
    @ObservedObject var editor: EditorController
    let block: ContentBlock

    var body: some View {
        HStack(spacing: 2) {
            if block.kind == .text {
                BarButton(symbol: "character.cursor.ibeam", label: "Edit Text") {
                    if let page = editor.contentPage { editor.pdfView?.beginContentEditing(block, on: page) }
                }
                BarButton(symbol: "doc.on.doc", label: "Copy Text") { editor.copySelectedContentText() }
            } else {
                BarButton(symbol: "photo.on.rectangle", label: "Replace…") { editor.replaceSelectedContentImage() }
                BarButton(symbol: "square.and.arrow.down", label: "Save Image…") { editor.saveSelectedContentImage() }
            }
            Divider().frame(height: 18).padding(.horizontal, 2)
            BarButton(symbol: "trash", label: "Delete", role: .destructive) { editor.deleteSelectedContent() }
        }
        .padding(.horizontal, 6)
        .frame(height: 36)
        .floatingChrome(Capsule())
    }
}

/// Edit mode's tool bar: the three tools and the font, size and colour of the selected (or next) text.
struct ContentEditBar: View {
    @ObservedObject var editor: EditorController

    private var style: TextStyle {
        if let block = editor.selectedContent, block.kind == .text { return block.style }
        return editor.contentTextStyle
    }

    private var isBold: Bool { style.font.fontDescriptor.symbolicTraits.contains(.bold) }
    private var isItalic: Bool { style.font.fontDescriptor.symbolicTraits.contains(.italic) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content
            content.environment(\.paletteCompact, true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var content: some View {
        HStack(spacing: 2) {
            ForEach([Tool.editContent, .addContentText, .addContentImage]) { tool in
                PaletteButton(symbol: tool.symbol, label: tool.label, help: help(tool), selected: editor.tool == tool) { editor.tool = tool }
            }
            Divider().frame(height: 26).padding(.horizontal, 6)
            fontMenu
            sizeControl
            Toggle(isOn: Binding(get: { isBold }, set: { bold in restyle(bold: bold) })) { Image(systemName: "bold") }
                .toggleStyle(.button).help("Bold")
            Toggle(isOn: Binding(get: { isItalic }, set: { italic in restyle(italic: italic) })) { Image(systemName: "italic") }
                .toggleStyle(.button).help("Italic")
            colorMenu
            Divider().frame(height: 26).padding(.horizontal, 6)
            PaletteButton(symbol: "arrow.uturn.backward", label: "Undo", help: "Undo (⌘Z)", selected: false) { editor.undoManager?.undo() }
                .disabled(!editor.canUndo)
            PaletteButton(symbol: "arrow.uturn.forward", label: "Redo", help: "Redo (⇧⌘Z)", selected: false) { editor.undoManager?.redo() }
                .disabled(!editor.canRedo)
        }
        .fixedSize()
        .disabled(!ContentEditor.isAvailable)
    }

    private func help(_ tool: Tool) -> String {
        switch tool {
        case .editContent: "Click text to edit it, drag text or images to move them"
        case .addContentText: "Click to add text to the page"
        default: "Click or drag to place an image on the page"
        }
    }

    private var fontMenu: some View {
        Menu {
            ForEach(TextFonts.families, id: \.self) { family in
                Button(family ?? "System") {
                    let font = TextFonts.font(family: family, size: style.fontSize, bold: isBold, italic: isItalic)
                    editor.restyleSelectedContent { $0.fontName = family == nil ? Self.systemName(bold: isBold, italic: isItalic) : font.fontName }
                }
            }
        } label: {
            Text(style.displayName).lineLimit(1).frame(width: 130, alignment: .leading)
        }
        .fixedSize()
        .help("Font")
    }

    private var sizeControl: some View {
        HStack(spacing: 0) {
            TextField("Size", value: Binding(get: { Double(style.fontSize) }, set: { value in
                editor.restyleSelectedContent { $0.fontSize = CGFloat(min(max(value, 4), 200)) }
            }), format: .number.precision(.fractionLength(0...1)))
            .frame(width: 40)
            .multilineTextAlignment(.trailing)
            Stepper("", value: Binding(get: { Double(style.fontSize) }, set: { value in
                editor.restyleSelectedContent { $0.fontSize = CGFloat(min(max(value, 4), 200)) }
            }), step: 1)
            .labelsHidden()
        }
        .help("Font size")
    }

    private var colorMenu: some View {
        Menu {
            ForEach(Array(Palette.swatches.enumerated()), id: \.offset) { _, color in
                Button {
                    editor.restyleSelectedContent { $0.color = color }
                } label: {
                    Label(Swatch.name(of: color), systemImage: Palette.same(color, style.color) ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        } label: {
            Circle().fill(Color(nsColor: style.color)).overlay(Circle().strokeBorder(.primary.opacity(0.25)))
                .frame(width: 16, height: 16)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: 30, height: 28)
        .help("Text colour")
    }

    private func restyle(bold: Bool? = nil, italic: Bool? = nil) {
        let wantBold = bold ?? isBold, wantItalic = italic ?? isItalic
        editor.restyleSelectedContent { style in
            if style.fontName.hasPrefix(ContentEditor.systemFontPrefix) {
                style.fontName = Self.systemName(bold: wantBold, italic: wantItalic)
                return
            }
            let manager = NSFontManager.shared
            var font = style.font
            font = wantBold ? manager.convert(font, toHaveTrait: .boldFontMask) : manager.convert(font, toNotHaveTrait: .boldFontMask)
            font = wantItalic ? manager.convert(font, toHaveTrait: .italicFontMask) : manager.convert(font, toNotHaveTrait: .italicFontMask)
            style.fontName = font.fontName
        }
    }

    private static func systemName(bold: Bool, italic: Bool) -> String {
        ContentEditor.systemFontPrefix + (bold ? "Bold" : "Regular") + (italic ? "Italic" : "")
    }
}
