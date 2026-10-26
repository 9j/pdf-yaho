import PDFKit
import PagecraftCore
import SwiftUI

struct SidebarView: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar", selection: $editor.sidebarTab) {
                ForEach(SidebarTab.allCases) { tab in
                    Image(systemName: tab.symbol).help(tab.rawValue.capitalized).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Group {
                switch editor.sidebarTab {
                case .thumbnails: ThumbnailList(editor: editor)
                case .outline: OutlineList(editor: editor)
                case .annotations: AnnotationList(editor: editor)
                case .search: SearchResultList(editor: editor)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ThumbnailList: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $editor.selectedPages) {
                ForEach(0..<editor.pageCount, id: \.self) { index in
                    VStack(spacing: 4) {
                        if let image = editor.thumbnail(for: index) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 180)
                                .shadow(radius: 1)
                                .overlay(Rectangle().stroke(Color.accentColor, lineWidth: index == editor.currentPageIndex ? 2 : 0))
                        }
                        Text("\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .tag(index)
                    .id(index)
                    .contextMenu { PageMenu(editor: editor, index: index) }
                }
                .onMove { editor.movePages(from: $0, to: $1) }
            }
            .onChange(of: editor.selectedPages) { _, selection in
                if selection.count == 1, let index = selection.first, index != editor.currentPageIndex {
                    editor.goToPage(index)
                }
            }
            .onChange(of: editor.currentPageIndex) { _, index in
                withAnimation { proxy.scrollTo(index) }
            }
            .onDeleteCommand { editor.deletePages() }
        }
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
        Divider()
        Button(indices.count == 1 ? "Delete Page" : "Delete \(indices.count) Pages", role: .destructive) {
            editor.deletePages(indices)
        }
    }
}

struct OutlineNode: Identifiable {
    let id = UUID()
    let label: String
    let destination: PDFDestination?
    let children: [OutlineNode]?

    init(_ outline: PDFOutline) {
        label = outline.label ?? "Untitled"
        destination = outline.destination
        let kids = (0..<outline.numberOfChildren).compactMap { outline.child(at: $0) }.map(OutlineNode.init)
        children = kids.isEmpty ? nil : kids
    }
}

struct OutlineList: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        let nodes = editor.document.outlineRoot.map { OutlineNode($0).children ?? [] } ?? []
        VStack(spacing: 0) {
            if nodes.isEmpty {
                ContentUnavailableView("No Outline", systemImage: "list.bullet.indent",
                                       description: Text("Use Page ▸ Add Bookmark to create one."))
            } else {
                List(nodes, children: \.children) { node in
                    Text(node.label)
                        .lineLimit(2)
                        .contentShape(Rectangle())
                        .onTapGesture { if let destination = node.destination { editor.pdfView?.go(to: destination) } }
                }
            }
            Divider()
            Button {
                if let label = Prompt.text("Add Bookmark", message: "Bookmark title:", defaultValue: "Page \(editor.currentPageIndex + 1)") {
                    editor.addBookmark(label: label, page: editor.currentPageIndex)
                }
            } label: {
                Label("Add Bookmark", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .id(editor.revision)
    }
}

struct AnnotationList: View {
    @ObservedObject var editor: EditorController

    private struct Item: Identifiable {
        let id: ObjectIdentifier
        let page: PDFPage
        let pageIndex: Int
        let annotation: PDFAnnotation
    }

    private var items: [Item] {
        PDFOps.pages(of: editor.document).enumerated().flatMap { index, page in
            page.annotations.filter(Annotations.isUserEditable).map {
                Item(id: ObjectIdentifier($0), page: page, pageIndex: index, annotation: $0)
            }
        }
    }

    var body: some View {
        let items = self.items
        VStack(spacing: 0) {
            if items.isEmpty {
                ContentUnavailableView("No Annotations", systemImage: "pencil.tip.crop.circle")
            } else {
                List(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Circle().fill(Color(nsColor: item.annotation.color)).frame(width: 8, height: 8)
                            Text(Annotations.displayName(item.annotation)).font(.callout.weight(.medium))
                            Spacer()
                            Text("p. \(item.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
                        }
                        let detail = Annotations.markedText(item.annotation, on: item.page) ?? item.annotation.contents ?? ""
                        if !detail.isEmpty {
                            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editor.pdfView?.go(to: item.annotation.bounds, on: item.page)
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) { editor.remove(item.annotation, from: item.page) }
                    }
                }
            }
            Divider()
            Button {
                Exporter.annotationSummary(editor)
            } label: {
                Label("Export Summary…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .padding(8)
            .disabled(items.isEmpty)
        }
        .id(editor.revision)
    }
}

struct SearchResultList: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        if editor.searchResults.isEmpty {
            ContentUnavailableView.search(text: editor.searchText)
        } else {
            List(Array(editor.searchResults.enumerated()), id: \.offset) { index, result in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Page \((result.pages.first.map { editor.document.index(for: $0) } ?? 0) + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(context(result)).font(.callout).lineLimit(3)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .listRowBackground(index == editor.searchIndex ? Color.accentColor.opacity(0.2) : nil)
                .onTapGesture {
                    editor.searchIndex = index
                    editor.go(to: result)
                }
            }
        }
    }

    /// The match with some surrounding words, cut at word boundaries and with the match in bold.
    private func context(_ result: PDFSelection) -> AttributedString {
        let match = result.string ?? ""
        guard let extended = result.copy() as? PDFSelection else { return AttributedString(match) }
        extended.extend(atStart: 30)
        extended.extend(atEnd: 40)
        let full = (extended.string ?? match).replacingOccurrences(of: "\n", with: " ")
        guard let range = full.range(of: match, options: [.caseInsensitive, .diacriticInsensitive]) else { return AttributedString(full) }
        var before = String(full[..<range.lowerBound])
        var after = String(full[range.upperBound...])
        if before.count >= 30, let space = before.firstIndex(of: " ") { before = "…" + before[before.index(after: space)...] }
        if after.count >= 40, let space = after.lastIndex(of: " ") { after = after[..<space] + "…" }
        var bold = AttributedString(String(full[range]))
        bold.font = .callout.bold()
        return AttributedString(before) + bold + AttributedString(after)
    }
}
