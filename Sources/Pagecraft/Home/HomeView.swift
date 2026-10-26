import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Home window: translucent sidebar on the left, a centred content column on the right.
struct HomeView: View {
    @State private var store = HomeStore()
    @State private var page: HomePage = .home
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            HomeSidebar(selection: $page)
            Group {
                switch page {
                case .home: HomePageView(page: $page)
                case .recents: RecentsPageView()
                case .favorites: FavoritesPageView()
                case .tools: ToolsPageView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .overlay { if dropTargeted { DropOverlay().transition(.opacity) } }
        .animation(.easeOut(duration: 0.15), value: dropTargeted)
        .environment(store)
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.isFileURL && (UTType(filenameExtension: $0.pathExtension)?.conforms(to: .pdf) ?? false) }
            pdfs.forEach { DocumentLauncher.open($0) }
            return !pdfs.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if (note.object as? NSWindow)?.title == "Home" { store.refresh() }
        }
        .onAppear { store.refresh() }
        .frame(minWidth: 720, minHeight: 480)
    }
}

// MARK: - Home

private let rowCardWidth: CGFloat = 168

private struct HomePageView: View {
    @Binding var page: HomePage
    @Environment(HomeStore.self) private var store

    var body: some View {
        PageColumn {
            PageHeader(title: "Home") {
                HStack(spacing: 8) {
                    Button { NSDocumentController.shared.openDocument(nil) } label: {
                        Label("Open…", systemImage: "folder")
                    }
                    .keyboardShortcut("o", modifiers: .command)
                    .buttonStyle(.borderedProminent)

                    Menu {
                        Button { NSDocumentController.shared.newDocument(nil) } label: { Label("Blank PDF", systemImage: "doc") }
                        Button { Exporter.newFromImages() } label: { Label("From Images…", systemImage: "photo.on.rectangle") }
                        Button { Exporter.convertFiles() } label: { Label("From File…", systemImage: "doc.badge.arrow.up") }
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .menuStyle(.button)
                    .fixedSize()
                }
                .controlSize(.large)
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Tools for You") { page = .tools }
                ArrowScrollRow(count: HomeTools.featured.count) {
                    HStack(spacing: 12) {
                        ForEach(Array(HomeTools.featured.enumerated()), id: \.offset) { index, tool in
                            ToolCard(tool: tool, style: .compact).id(index)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            documentRow(title: "Recent", urls: Array(store.recents.prefix(12)), target: .recents,
                        empty: EmptyState(symbol: "clock", title: "No recent documents",
                                          message: "Documents you open will show up here. Drop a PDF anywhere in this window to get started."))

            documentRow(title: "Favorites", urls: Array(store.favorites.prefix(12)), target: .favorites,
                        empty: EmptyState(symbol: "star", title: "No favorites yet",
                                          message: "Hover over a document and click its star to keep it close."))
        }
    }

    private func documentRow(title: String, urls: [URL], target: HomePage, empty: EmptyState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title) { page = target }
            if urls.isEmpty {
                empty
            } else {
                ArrowScrollRow(count: urls.count) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(Array(urls.enumerated()), id: \.element) { index, url in
                            DocumentCard(url: url).frame(width: rowCardWidth).id(index)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

// MARK: - Recents

private let gridColumns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 20, alignment: .top)]

private struct RecentsPageView: View {
    @Environment(HomeStore.self) private var store
    @State private var filter = ""

    private var shown: [URL] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.recents }
        return store.recents.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        PageColumn {
            PageHeader(title: "Recents") {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Filter", text: $filter)
                            .textFieldStyle(.plain)
                        if !filter.isEmpty {
                            Button { filter = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear filter")
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(width: 180, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))

                    Button("Clear Recents") {
                        if Prompt.confirm("Clear all recent documents?",
                                          message: "This only clears the list. Your files are not deleted.",
                                          button: "Clear Recents") {
                            store.clearRecents()
                        }
                    }
                    .disabled(store.recents.isEmpty)
                }
                .controlSize(.large)
            }

            if store.recents.isEmpty {
                EmptyState(symbol: "clock", title: "No recent documents",
                           message: "Documents you open will show up here. Drop a PDF anywhere in this window to get started.")
            } else if shown.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "No matches",
                           message: "No recent document is named “\(filter)”.")
            } else {
                LazyVGrid(columns: gridColumns, spacing: 24) {
                    ForEach(shown, id: \.self) { DocumentCard(url: $0) }
                }
            }
        }
    }
}

// MARK: - Favorites

private struct FavoritesPageView: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        PageColumn {
            PageHeader(title: "Favorites") { EmptyView() }
            if store.favorites.isEmpty {
                EmptyState(symbol: "star", title: "No favorites yet",
                           message: "Hover over a document and click the star in its corner to add it here. Favorites stay until you remove them.")
            } else {
                LazyVGrid(columns: gridColumns, spacing: 24) {
                    ForEach(store.favorites, id: \.self) { DocumentCard(url: $0) }
                }
            }
        }
    }
}

// MARK: - Tools

private struct ToolsPageView: View {
    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 12, alignment: .top)]

    var body: some View {
        PageColumn {
            PageHeader(title: "Tools") { EmptyView() }
            ForEach(HomeTools.categories) { category in
                VStack(alignment: .leading, spacing: 12) {
                    Text(category.title).font(.title3.weight(.semibold))
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(category.tools) { ToolCard(tool: $0, style: .row) }
                    }
                }
            }
        }
    }
}


/// A horizontal row without a scroll bar, with previous/next arrows that appear on hover.
struct ArrowScrollRow<Content: View>: View {
    let count: Int
    @ViewBuilder let content: Content
    @State private var hovering = false
    @State private var index = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) { content }
                .scrollIndicators(.never)
                .scrollClipDisabled()
                .overlay(alignment: .leading) {
                    arrow("chevron.left", visible: hovering && index > 0) { step(-3, proxy) }.offset(x: -14)
                }
                .overlay(alignment: .trailing) {
                    arrow("chevron.right", visible: hovering && index < count - 1) { step(3, proxy) }.offset(x: 14)
                }
                .onHover { hovering = $0 }
        }
    }

    private func step(_ delta: Int, _ proxy: ScrollViewProxy) {
        index = max(0, min(count - 1, index + delta))
        withAnimation(.snappy) { proxy.scrollTo(index, anchor: .leading) }
    }

    private func arrow(_ symbol: String, visible: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: visible)
        .allowsHitTesting(visible)
    }
}
