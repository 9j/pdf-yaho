import PDFKit
import PagecraftCore
import SwiftUI

/// Pages mode: every page as a large thumbnail. Click, ⌘-click and ⇧-click select; drag to reorder.
struct PageGridView: View {
    @ObservedObject var editor: EditorController
    @AppStorage("pageGridSize") private var size: Double = 190
    @State private var anchor: Int?
    @State private var dropTarget: Int?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: size, maximum: size * 1.25), spacing: 26, alignment: .top)],
                      spacing: 30) {
                ForEach(0..<editor.pageCount, id: \.self) { index in
                    PageCell(editor: editor, index: index, size: size,
                             selected: editor.selectedPages.contains(index), dropTarget: dropTarget == index)
                        .onTapGesture(count: 2) { open(index) }
                        .onTapGesture { click(index) }
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
            .padding(.top, 28)
            .padding(.bottom, 110)
            .id(editor.revision)
        }
        .background(Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1) : NSColor(srgbRed: 0.91, green: 0.91, blue: 0.92, alpha: 1) }))
        .contentShape(Rectangle())
        .onTapGesture { editor.selectedPages = [] }
        .overlay(alignment: .bottom) {
            PagesActionBar(editor: editor, size: $size).padding(.bottom, 18)
        }
        .onDeleteCommand { editor.deletePages() }
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
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .font(.system(size: 20))
                        .offset(x: 8, y: -8)
                }
            }
            .frame(height: size * 1.35 + 10, alignment: .bottom)
            Text("\(index + 1)")
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

private struct PagesActionBar: View {
    @ObservedObject var editor: EditorController
    @Binding var size: Double

    private var count: Int { editor.selectedPages.count }

    var body: some View {
        HStack(spacing: 4) {
            Text(count == 0 ? "\(editor.pageCount) pages" : "\(count) of \(editor.pageCount) selected")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 120)
            Divider().frame(height: 20)
            ActionButton(symbol: "rotate.left", label: "Rotate Left") { editor.rotate(-90) }.disabled(count == 0)
            ActionButton(symbol: "rotate.right", label: "Rotate Right") { editor.rotate(90) }.disabled(count == 0)
            ActionButton(symbol: "doc.badge.plus", label: "Insert Blank Page") { editor.insertBlankPage() }
            ActionButton(symbol: "square.and.arrow.down.on.square", label: "Insert from File…") { Exporter.insertFromFile(editor) }
            ActionButton(symbol: "square.and.arrow.up.on.square", label: "Extract…") {
                Exporter.extract(editor, indices: editor.targetPageIndices)
            }
            .disabled(count == 0)
            ActionButton(symbol: "trash", label: "Delete", destructive: true) { editor.deletePages() }
                .disabled(count == 0 || count == editor.pageCount)
            Menu {
                Section("Insert") {
                    Button("From Images…") { editor.insertImages() }
                    Button("From Clipboard") { editor.insertFromClipboard() }
                }
                Button("Duplicate") { editor.duplicatePages() }.disabled(count == 0)
                Button("Reverse Order") { editor.reversePages() }
                Divider()
                Button("Crop…") { editor.beginCrop() }
                Button("Clear Margins") { editor.autoCrop() }.disabled(count == 0)
                Button("Page Size…") { editor.showPageSize = true }
                Button("Split…") { editor.showSplit = true }
                Divider()
                Button("Page Numbers…") { editor.headerFooterPreset = .pageNumbers }
                Button("Header & Footer…") { editor.headerFooterPreset = .custom }
                Button("Bates Numbering…") { editor.headerFooterPreset = .bates }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 15, weight: .medium)).frame(width: 34, height: 32)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More page tools")
            Divider().frame(height: 20)
            Image(systemName: "square.grid.3x3").font(.caption).foregroundStyle(.secondary)
            Slider(value: $size, in: 120...320).frame(width: 90).controlSize(.small)
            Image(systemName: "square.grid.2x2").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    }
}

private struct ActionButton: View {
    let symbol: String
    let label: String
    var destructive = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(destructive && isEnabled ? Color.red : .primary)
                .frame(width: 34, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverButtonStyle())
        .opacity(isEnabled ? 1 : 0.35)
        .help(label)
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
        Button("Extract…") { Exporter.extract(editor, indices: indices) }
        Button("Add Bookmark") { editor.addBookmark(page: index) }
        Divider()
        Button(indices.count == 1 ? "Delete Page" : "Delete \(indices.count) Pages", role: .destructive) {
            editor.deletePages(indices)
        }
    }
}
