import PDFKit
import PDFYahoCore
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
                case .bookmarks: BookmarkList(editor: editor)
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

    // The body reads only the page count and revision. The current page is read by each visible row,
    // so turning a page doesn't rebuild a list of thousands of rows.
    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(0..<editor.pageCount, id: \.self) { index in
                    ThumbnailRow(editor: editor, index: index)
                        .contentShape(Rectangle())
                        .onTapGesture { editor.goToPage(index) }
                        .id(index)
                        .contextMenu { PageMenu(editor: editor, index: index) }
                        .listRowSeparator(.hidden)
                }
                .onMove { editor.movePages(from: $0, to: $1) }
            }
            .listStyle(.sidebar)
            .background { FollowCurrentPage(editor: editor, proxy: proxy) }
        }
    }
}

/// Keeps the current page's thumbnail in view.
private struct FollowCurrentPage: View {
    let editor: EditorController
    let proxy: ScrollViewProxy

    var body: some View {
        Color.clear
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proxy.scrollTo(editor.currentPageIndex, anchor: .top) }
            }
            .onChange(of: editor.currentPageIndex) { _, index in
                withAnimation { proxy.scrollTo(index) }
            }
    }
}

private struct ThumbnailRow: View {
    let editor: EditorController
    let index: Int

    var body: some View {
        let current = index == editor.currentPageIndex
        VStack(spacing: 6) {
            PageThumbnail(editor: editor, index: index, side: 240)
                .frame(maxHeight: 170)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(current ? Color.accentColor : .clear, lineWidth: 2.5))
                .overlay(alignment: .topTrailing) {
                    if editor.isBookmarked(index) {
                        Image(systemName: "bookmark.fill").font(.system(size: 12)).foregroundStyle(.red).padding(.trailing, 10)
                    }
                }
            Text(editor.pageLabel(index))
                .font(.caption.weight(current ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(current ? Color.accentColor : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
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
                    Label("No Outline", systemImage: "list.bullet.indent")
                } description: {
                    Text("The outline is the document’s table of contents, saved inside the PDF.")
                } actions: {
                    Button("Add Item for This Page") { editor.addOutlineItem() }
                }
            } else {
                List(nodes, children: \.children) { node in
                    row(node)
                }
                .listStyle(.sidebar)
                SidebarFooter {
                    Button { editor.addOutlineItem() } label: { Label("Add Item", systemImage: "plus") }
                        .help("Add an outline item for the current page (⌥⌘D)")
                }
            }
        }
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
                Button("Point to Current Page") { editor.retarget(node.item) }
                Divider()
                Button("Delete", role: .destructive) { editor.deleteOutlineItem(node.item) }
            }
        }
    }
}

/// Personal bookmarks: quick links to pages, kept on this Mac.
struct BookmarkList: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        VStack(spacing: 0) {
            if editor.bookmarks.isEmpty {
                ContentUnavailableView {
                    Label("No Bookmarks", systemImage: "bookmark")
                } description: {
                    Text("Hover over a page and click the ribbon in its corner, or press ⌘D.")
                } actions: {
                    Button("Bookmark This Page") { editor.toggleBookmark() }
                }
            } else {
                List {
                    ForEach(editor.bookmarks, id: \.self) { index in
                        HStack(spacing: 10) {
                            if let image = editor.thumbnail(for: index) {
                                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 34, height: 44)
                                    .background(.white).shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Page \(index + 1)").font(.callout.weight(.medium))
                                Text(snippet(index)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture { editor.goToPage(index) }
                        .contextMenu {
                            Button("Remove Bookmark", role: .destructive) { editor.toggleBookmark(index) }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func snippet(_ index: Int) -> String {
        let text = editor.document.page(at: index)?.string ?? ""
        return text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}

struct AnnotationList: View {
    @ObservedObject var editor: EditorController
    @State private var typeFilter: Set<String> = []
    @State private var colorFilter: String?
    @State private var authorFilter: String?
    @State private var query = ""

    private struct Item: Identifiable {
        let id: ObjectIdentifier
        let page: PDFPage
        let annotation: PDFAnnotation
    }

    private static func colorKey(_ c: NSColor) -> String {
        let c = Palette.srgb(c)
        return String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }

    private var all: [(index: Int, items: [Item])] {
        PDFOps.pages(of: editor.document).enumerated().compactMap { index, page in
            let items = page.annotations.filter(Annotations.isUserEditable)
                .filter { $0.userName != PDFOps.pageNumberTag && $0.userName != PageOps.stampTag }
                .map { Item(id: ObjectIdentifier($0), page: page, annotation: $0) }
            return items.isEmpty ? nil : (index, items)
        }
    }

    private func matches(_ item: Item) -> Bool {
        let a = item.annotation
        if !typeFilter.isEmpty, !typeFilter.contains(Annotations.displayName(a)) { return false }
        if let colorFilter, Self.colorKey(Annotations.color(of: a)) != colorFilter { return false }
        if let authorFilter, a.userName != authorFilter { return false }
        if !query.isEmpty {
            let text = (Annotations.markedText(a, on: item.page) ?? "") + " " + (a.contents ?? "")
            if !text.localizedCaseInsensitiveContains(query) { return false }
        }
        return true
    }

    var body: some View {
        let all = self.all
        let groups = all.compactMap { group -> (index: Int, items: [Item])? in
            let items = group.items.filter(matches)
            return items.isEmpty ? nil : (group.index, items)
        }
        let flat = all.flatMap(\.items)
        let types = Array(Set(flat.map { Annotations.displayName($0.annotation) })).sorted()
        let colors = Array(Set(flat.map { Self.colorKey(Annotations.color(of: $0.annotation)) })).sorted()
        let authors = Array(Set(flat.compactMap { $0.annotation.userName }.filter { !$0.hasPrefix("org.pagecraft") })).sorted()
        let filtering = !typeFilter.isEmpty || colorFilter != nil || authorFilter != nil || !query.isEmpty
        VStack(spacing: 0) {
            if flat.isEmpty {
                ContentUnavailableView("No Annotations", systemImage: "highlighter",
                                       description: Text("Highlights, notes and drawings appear here."))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                    TextField("Filter", text: $query).textFieldStyle(.plain).font(.callout)
                    Menu {
                        Section("Type") {
                            ForEach(types, id: \.self) { type in
                                Toggle(type, isOn: Binding(get: { typeFilter.contains(type) },
                                                           set: { if $0 { typeFilter.insert(type) } else { typeFilter.remove(type) } }))
                            }
                        }
                        if colors.count > 1 {
                            Picker("Colour", selection: $colorFilter) {
                                Text("Any Colour").tag(String?.none)
                                ForEach(colors, id: \.self) { key in
                                    Label("#" + key, systemImage: "circle.fill").tag(Optional(key))
                                }
                            }
                        }
                        if authors.count > 1 {
                            Picker("Author", selection: $authorFilter) {
                                Text("Anyone").tag(String?.none)
                                ForEach(authors, id: \.self) { Text($0).tag(Optional($0)) }
                            }
                        }
                        if filtering {
                            Divider()
                            Button("Clear Filters") { typeFilter = []; colorFilter = nil; authorFilter = nil; query = "" }
                        }
                    } label: {
                        Image(systemName: filtering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Filter by type, colour or author")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                if groups.isEmpty {
                    ContentUnavailableView("No Matches", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("No annotations match the filter."))
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
                }
                SidebarFooter {
                    Text(filtering ? "\(groups.reduce(0) { $0 + $1.items.count }) of \(flat.count)" : "\(flat.count) annotations")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Button("Summary (Markdown)…") { Exporter.annotationSummary(editor) }
                        Button("XFDF…") { Exporter.xfdf(editor) }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
    }
}

private struct AnnotationRow: View {
    let editor: EditorController
    let page: PDFPage
    let annotation: PDFAnnotation

    var body: some View {
        let quote = Annotations.markedText(annotation, on: page) ?? ""
        let comment = annotation.contents ?? ""
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: Annotations.color(of: annotation)))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Annotations.displayName(annotation)).font(.callout.weight(.medium))
                    Spacer(minLength: 4)
                    if let date = annotation.modificationDate {
                        Text(date.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                if let author = annotation.userName, !author.hasPrefix("org.pagecraft") {
                    Text(author).font(.caption2).foregroundStyle(.tertiary)
                }
                if !quote.isEmpty {
                    Text("“\(quote)”").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                if !comment.isEmpty, comment != quote {
                    Label(comment, systemImage: "text.bubble").font(.caption).foregroundStyle(.primary).lineLimit(4)
                        .labelStyle(.titleAndIcon)
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
        if editor.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView {
                Label("Search This Document", systemImage: "magnifyingglass")
            } description: {
                Text("Type in the search field in the toolbar. Results appear here as you type.")
            }
        } else if editor.searchResults.isEmpty, editor.searching {
            ProgressView("Searching…").controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if editor.searchResults.isEmpty {
            ContentUnavailableView.search(text: editor.searchText)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text(editor.searching ? "\(editor.searchResults.count) results so far…" : "\(editor.searchResults.count) results")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    if editor.searching { ProgressView().controlSize(.mini) }
                    Spacer()
                    Menu {
                        Toggle("Match Case", isOn: $editor.searchMatchCase)
                        Toggle("Whole Words", isOn: $editor.searchWholeWords)
                        Divider()
                        Button("Redact All Matches…") {
                            editor.markForRedaction([editor.searchText], matchCase: editor.searchMatchCase,
                                                    wholeWords: editor.searchWholeWords, style: editor.redactionStyle)
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Search options")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                // A lazy stack builds only the rows on screen; a List rebuilt all of them each time results arrived.
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(editor.searchResults) { result in
                            SearchResultRow(hit: result, page: editor.pageLabel(result.pageIndex), current: result.id == editor.searchIndex)
                                .onTapGesture {
                                    editor.searchIndex = result.id
                                    editor.go(to: result.selection)
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

private struct SearchResultRow: View, Equatable {
    let hit: SearchHit
    let page: String
    let current: Bool

    static func == (a: Self, b: Self) -> Bool { a.hit.id == b.hit.id && a.hit.selection === b.hit.selection && a.page == b.page && a.current == b.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Page \(page)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(context).font(.callout).lineLimit(3)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(current ? Color.accentColor.opacity(0.15) : .clear))
        .contentShape(Rectangle())
    }

    /// The match in bold, with the words around it.
    private var context: AttributedString {
        var bold = AttributedString(hit.snippet.match)
        bold.font = .callout.bold()
        bold.backgroundColor = Color.yellow.opacity(0.35)
        return AttributedString(hit.snippet.before) + bold + AttributedString(hit.snippet.after)
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
