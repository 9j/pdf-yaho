import PDFKit
import PagecraftCore
import SwiftUI

struct SidebarView: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(SidebarTab.allCases) { tab in
                    Button { editor.sidebarTab = tab } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(editor.sidebarTab == tab ? Color.accentColor : .secondary)
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(editor.sidebarTab == tab ? Color.accentColor.opacity(0.14) : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tab.rawValue)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Divider()
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
            List {
                ForEach(0..<editor.pageCount, id: \.self) { index in
                    let current = index == editor.currentPageIndex
                    VStack(spacing: 6) {
                        if let image = editor.thumbnail(for: index) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 170)
                                .background(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                                .padding(4)
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(current ? Color.accentColor : .clear, lineWidth: 2.5))
                        }
                        Text("\(index + 1)")
                            .font(.caption.weight(current ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(current ? Color.accentColor : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture { editor.goToPage(index) }
                    .id(index)
                    .contextMenu { PageMenu(editor: editor, index: index) }
                    .listRowSeparator(.hidden)
                }
                .onMove { editor.movePages(from: $0, to: $1) }
            }
            .listStyle(.sidebar)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proxy.scrollTo(editor.currentPageIndex, anchor: .top) }
            }
            .onChange(of: editor.currentPageIndex) { _, index in
                withAnimation { proxy.scrollTo(index) }
            }
        }
    }
}

struct OutlineNode: Identifiable {
    let id: ObjectIdentifier
    let item: PDFOutline
    let children: [OutlineNode]?

    init(_ outline: PDFOutline) {
        id = ObjectIdentifier(outline)
        item = outline
        let kids = (0..<outline.numberOfChildren).compactMap { outline.child(at: $0) }.map(OutlineNode.init)
        children = kids.isEmpty ? nil : kids
    }
}

struct OutlineList: View {
    @ObservedObject var editor: EditorController
    @State private var renaming: ObjectIdentifier?
    @State private var draft = ""

    var body: some View {
        let nodes = editor.document.outlineRoot.map { OutlineNode($0).children ?? [] } ?? []
        VStack(spacing: 0) {
            if nodes.isEmpty {
                ContentUnavailableView {
                    Label("No Bookmarks", systemImage: "bookmark")
                } description: {
                    Text("Bookmark pages you want to find again.")
                } actions: {
                    Button("Bookmark This Page") { editor.addBookmark() }
                }
            } else {
                List(nodes, children: \.children) { node in
                    row(node)
                }
                .listStyle(.sidebar)
                SidebarFooter {
                    Button { editor.addBookmark() } label: { Label("Bookmark This Page", systemImage: "plus") }
                }
            }
        }
        .id(editor.revision)
    }

    @ViewBuilder
    private func row(_ node: OutlineNode) -> some View {
        if renaming == node.id {
            TextField("Title", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { editor.rename(node.item, to: draft); renaming = nil }
                .onExitCommand { renaming = nil }
        } else {
            HStack {
                Text(node.item.label ?? "Untitled").lineLimit(2)
                Spacer()
                if let page = node.item.destination?.page {
                    Text("\(editor.document.index(for: page) + 1)").font(.caption).monospacedDigit().foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { draft = node.item.label ?? ""; renaming = node.id }
            .onTapGesture { if let destination = node.item.destination { editor.pdfView?.go(to: destination) } }
            .contextMenu {
                Button("Rename") { draft = node.item.label ?? ""; renaming = node.id }
            }
        }
    }
}

struct AnnotationList: View {
    @ObservedObject var editor: EditorController

    private struct Item: Identifiable {
        let id: ObjectIdentifier
        let page: PDFPage
        let annotation: PDFAnnotation
    }

    private var groups: [(index: Int, items: [Item])] {
        PDFOps.pages(of: editor.document).enumerated().compactMap { index, page in
            let items = page.annotations.filter(Annotations.isUserEditable)
                .filter { $0.userName != PDFOps.pageNumberTag }
                .map { Item(id: ObjectIdentifier($0), page: page, annotation: $0) }
            return items.isEmpty ? nil : (index, items)
        }
    }

    var body: some View {
        let groups = self.groups
        VStack(spacing: 0) {
            if groups.isEmpty {
                ContentUnavailableView("No Annotations", systemImage: "highlighter",
                                       description: Text("Highlights, notes and drawings appear here."))
            } else {
                List {
                    ForEach(groups, id: \.index) { group in
                        Section("Page \(group.index + 1)") {
                            ForEach(group.items) { item in
                                AnnotationRow(editor: editor, page: item.page, annotation: item.annotation)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                SidebarFooter {
                    Button { Exporter.annotationSummary(editor) } label: { Label("Export Summary…", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .id(editor.revision)
    }
}

private struct AnnotationRow: View {
    let editor: EditorController
    let page: PDFPage
    let annotation: PDFAnnotation

    var body: some View {
        let detail = Annotations.markedText(annotation, on: page) ?? annotation.contents ?? ""
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: Annotations.color(of: annotation)))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(Annotations.displayName(annotation)).font(.callout.weight(.medium))
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            editor.pdfView?.go(to: annotation.bounds.insetBy(dx: -40, dy: -80), on: page)
            editor.mode = editor.mode == .pages ? .read : editor.mode
            editor.tool = .select
            editor.select(SelectedAnnotation(annotation: annotation, page: page))
        }
        .contextMenu {
            Button("Delete", role: .destructive) { editor.remove(annotation, from: page) }
        }
    }
}

struct SearchResultList: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        if editor.searchResults.isEmpty {
            ContentUnavailableView.search(text: editor.searchText)
        } else {
            VStack(spacing: 0) {
                Text("\(editor.searchResults.count) results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                List(Array(editor.searchResults.enumerated()), id: \.offset) { index, result in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Page \((result.pages.first.map { editor.document.index(for: $0) } ?? 0) + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(context(result)).font(.callout).lineLimit(3)
                    }
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .listRowBackground(index == editor.searchIndex
                        ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15)).padding(.horizontal, 6) : nil)
                    .onTapGesture {
                        editor.searchIndex = index
                        editor.go(to: result)
                    }
                }
                .listStyle(.sidebar)
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
        bold.backgroundColor = Color.yellow.opacity(0.35)
        return AttributedString(before) + bold + AttributedString(after)
    }
}

private struct SidebarFooter<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack { content; Spacer() }
                .buttonStyle(.borderless)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }
}
