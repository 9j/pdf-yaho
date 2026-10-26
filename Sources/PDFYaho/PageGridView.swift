import PDFKit
import PDFYahoCore
import SwiftUI

/// Pages mode: every page as a large thumbnail. Click, ⌘-click and ⇧-click select; drag to reorder.
struct PageGridView: View {
    @ObservedObject var editor: EditorController
    @AppStorage("pageGridSize") private var size: Double = 190
    @State private var anchor: Int?
    @State private var dropTarget: Int?

    var body: some View {
        GeometryReader { geo in
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: size, maximum: size * 1.25), spacing: 26, alignment: .top)],
                      spacing: 30) {
                ForEach(0..<editor.pageCount, id: \.self) { index in
                    PageCell(editor: editor, index: index, size: size,
                             selected: editor.selectedPages.contains(index), dropTarget: dropTarget == index)
                        .onTapGesture(count: 2) { open(index) }
                        .simultaneousGesture(TapGesture().onEnded { click(index) })
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Page \(index + 1)")
                        .accessibilityAddTraits(editor.selectedPages.contains(index) ? [.isButton, .isSelected] : .isButton)
                        .draggable(PageDrag(indices: dragIndices(for: index))) {
                            PageDragPreview(editor: editor, indices: dragIndices(for: index))
                        }
                        .dropDestination(for: PageDrag.self) { items, _ in
                            guard let drag = items.first else { return false }
                            drop(drag.indices, on: index)
                            return true
                        } isTargeted: { dropTarget = $0 ? index : (dropTarget == index ? nil : dropTarget) }
                        .contextMenu { PageMenu(editor: editor, index: index) }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .onAppear { editor.pagesPerRow = columns(for: geo.size.width) }
        .onChange(of: geo.size.width) { _, width in editor.pagesPerRow = columns(for: width) }
        .onChange(of: size) { _, _ in editor.pagesPerRow = columns(for: geo.size.width) }
        }
        .background(Color(nsColor: PageBackground.color))
        .contentShape(Rectangle())
        .onTapGesture { editor.selectedPages = [] }
        // Keys (⌫, ⌘C/⌘X/⌘V, arrows, Return) are handled by the document view, which keeps focus.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                PagesActionBar(editor: editor, size: $size).background(.bar)
                Divider()
            }
        }
    }

    private func columns(for width: CGFloat) -> Int {
        max(1, Int((width - 72 + 26) / (size + 26)))
    }

    private func dragIndices(for index: Int) -> [Int] {
        editor.selectedPages.contains(index) ? editor.selectedPages.sorted() : [index]
    }

    private func click(_ index: Int) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if editor.selectedPages.contains(index) { editor.selectedPages.remove(index) } else { editor.selectedPages.insert(index) }
            anchor = index
        } else if flags.contains(.shift), let anchor {
            editor.selectedPages = Set(min(anchor, index)...max(anchor, index))
        } else {
            editor.selectedPages = [index]
            anchor = index
        }
    }

    private func open(_ index: Int) {
        editor.mode = .read
        DispatchQueue.main.async { editor.goToPage(index) }
    }

    private func drop(_ indices: [Int], on target: Int) {
        dropTarget = nil
        guard !indices.contains(target) else { return }
        let forward = (indices.max() ?? 0) < target
        editor.movePages(from: IndexSet(indices), to: forward ? target + 1 : target)
    }
}

struct PageDrag: Codable, Transferable {
    let indices: [Int]
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

private struct PageCell: View {
    @ObservedObject var editor: EditorController
    let index: Int
    let size: Double
    let selected: Bool
    let dropTarget: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                if let image = editor.thumbnail(for: index, side: size * 2) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: size, maxHeight: size * 1.35)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .shadow(color: .black.opacity(hovering ? 0.28 : 0.16), radius: hovering ? 8 : 4, y: 2)
                        .padding(5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : dropTarget ? Color.accentColor.opacity(0.6) : .clear,
                                              style: StrokeStyle(lineWidth: 3, dash: dropTarget && !selected ? [6, 4] : []))
                        )
                }
                if editor.isBookmarked(index) {
                    Image(systemName: "bookmark.fill").font(.system(size: 16)).foregroundStyle(.red)
                        .padding(.trailing, 14)
                }
            }
            .frame(height: size * 1.35 + 10, alignment: .bottom)
            Text(editor.pageLabel(index))
                .font(.callout.weight(selected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(selected ? .white : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(selected ? Color.accentColor : .clear))
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.15), value: hovering)
    }
}

private struct PageDragPreview: View {
    let editor: EditorController
    let indices: [Int]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let first = indices.first, let image = editor.thumbnail(for: first) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 90)
                    .background(.white).shadow(radius: 4)
            }
            if indices.count > 1 {
                Text("\(indices.count)").font(.caption.bold()).foregroundStyle(.white)
                    .padding(6).background(Circle().fill(Color.accentColor)).offset(x: 8, y: -8)
            }
        }
    }
}

/// Page actions for Pages mode, in the same labelled style as the toolset bars.
private struct PagesActionBar: View {
    @ObservedObject var editor: EditorController
    @Binding var size: Double

    private var count: Int { editor.selectedPages.count }

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
            Text(count == 0 ? "\(editor.pageCount) pages" : "\(count) of \(editor.pageCount) selected")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                .frame(minWidth: 120)
            Divider().frame(height: 26).padding(.horizontal, 3)
            Menu {
                Button("Blank Page") { editor.insertBlankPage() }
                Button("From File…") { Exporter.insertFromFile(editor) }
                Button("From Images…") { editor.insertImages() }
                Button("From Clipboard") { editor.insertFromClipboard() }
            } label: {
                PaletteLabel(symbol: "plus.rectangle.on.rectangle", label: "Insert", selected: false, showsChevron: true)
            } primaryAction: {
                editor.insertBlankPage()
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Insert a blank page after the selection; more options in the menu")
            PaletteButton(symbol: "rotate.left", label: "Left", help: "Rotate left (⌘L)", selected: false) { editor.rotate(-90) }
                .disabled(count == 0)
            PaletteButton(symbol: "rotate.right", label: "Right", help: "Rotate right (⌘R)", selected: false) { editor.rotate(90) }
                .disabled(count == 0)
            PaletteButton(symbol: "plus.square.on.square", label: "Duplicate", help: "Duplicate selected pages", selected: false) { editor.duplicatePages() }
                .disabled(count == 0)
            PaletteButton(symbol: "doc.on.doc", label: "Copy", help: "Copy pages (⌘C)", selected: false) { editor.copyPages() }
                .disabled(count == 0)
            PaletteButton(symbol: "doc.on.clipboard", label: "Paste", help: "Paste pages after the selection (⌘V)", selected: false) { editor.insertFromClipboard() }
            PaletteButton(symbol: "rectangle.portrait.and.arrow.right", label: "Extract", help: "Save the selected pages as a new PDF", selected: false) {
                Exporter.extract(editor, indices: editor.targetPageIndices)
            }
            .disabled(count == 0)
            PaletteButton(symbol: "trash", label: "Delete", help: "Delete selected pages (⌫)", selected: false) { editor.deletePages() }
                .disabled(count == 0 || count == editor.pageCount)
            Menu {
                Button("Reverse Order") { editor.reversePages() }
                Divider()
                Button("Crop…") { editor.beginCrop() }
                Button("Clear Margins") { editor.autoCrop() }.disabled(count == 0)
                Button("Page Size…") { editor.showPageSize = true }
                Button("Split Document…") { editor.showSplit = true }
                Button("Page Labels…") { editor.showPageLabels = true }
                Divider()
                Button("Page Numbers…") { editor.headerFooterPreset = .pageNumbers }
                Button("Header & Footer…") { editor.headerFooterPreset = .custom }
                Button("Bates Numbering…") { editor.headerFooterPreset = .bates }
            } label: {
                PaletteLabel(symbol: "ellipsis.circle", label: "More", selected: false, showsChevron: true)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            Divider().frame(height: 26).padding(.horizontal, 3)
            Image(systemName: "square.grid.3x3").font(.caption).foregroundStyle(.secondary)
            Slider(value: $size, in: 120...320).frame(width: 90).controlSize(.small)
                .accessibilityLabel("Thumbnail size")
            Image(systemName: "square.grid.2x2").foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}

struct PageMenu: View {
    let editor: EditorController
    let index: Int

    private var indices: [Int] {
        editor.selectedPages.contains(index) ? editor.selectedPages.sorted() : [index]
    }

    var body: some View {
        Button("Rotate Left") { editor.rotate(-90, pages: indices) }
        Button("Rotate Right") { editor.rotate(90, pages: indices) }
        Divider()
        Button("Insert Blank Page After") { editor.insertBlankPage(after: index) }
        Button("Copy") { editor.selectedPages = Set(indices); editor.copyPages() }
        Button("Paste After") { editor.selectedPages = [index]; editor.insertFromClipboard() }
        Button("Extract…") { Exporter.extract(editor, indices: indices) }
        Button(editor.isBookmarked(index) ? "Remove Bookmark" : "Bookmark Page") { editor.toggleBookmark(index) }
        Button("Add to Outline") { editor.addOutlineItem(page: index) }
        Divider()
        Button(indices.count == 1 ? "Delete Page" : "Delete \(indices.count) Pages", role: .destructive) {
            editor.deletePages(indices)
        }
    }
}
