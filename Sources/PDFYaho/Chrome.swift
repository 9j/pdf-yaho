import PDFKit
import PDFYahoCore
import SwiftUI

struct SplitState {
    var document: PDFDocument?
    var title: String?
    var vertical: Bool
    var swapped = false
    var sync = true

    init(vertical: Bool) { self.vertical = vertical }
}

/// App preferences, shared by the Settings window and document windows.
enum Preferences {
    enum PageIndicator: String, CaseIterable, Identifiable {
        case automatic = "Automatically", always = "Always", never = "Never"
        var id: String { rawValue }
    }

    private static var defaults: UserDefaults { .standard }

    static var openInTabs: Bool { defaults.object(forKey: "openInTabs") as? Bool ?? true }
    static var showSidebar: Bool { defaults.object(forKey: "showSidebar") as? Bool ?? true }
    static var showHomeWhenIdle: Bool { defaults.object(forKey: "showHomeWhenIdle") as? Bool ?? true }
    static var pageIndicator: PageIndicator {
        PageIndicator(rawValue: defaults.string(forKey: "pageIndicator") ?? "") ?? .automatic
    }
    static var defaultLayout: PageLayout {
        PageLayout(rawValue: defaults.string(forKey: "defaultLayout") ?? "") ?? .continuous
    }
    static var defaultTheme: ReadingTheme {
        ReadingTheme(rawValue: defaults.string(forKey: "defaultTheme") ?? "") ?? .day
    }
    static var hiddenToolsets: Set<EditorMode> {
        Set((defaults.string(forKey: "hiddenToolsets") ?? "").split(separator: ",").compactMap { EditorMode(rawValue: String($0)) })
    }
}

/// The toolset tabs in the toolbar: Read, Annotate, Draw, Fill & Sign, Measure, Redact, Scan, Pages.
struct ToolsetSwitcher: View {
    @ObservedObject var editor: EditorController
    @AppStorage("hiddenToolsets") private var hiddenRaw = ""
    @State private var customizing = false

    private var hidden: Set<EditorMode> {
        Set(hiddenRaw.split(separator: ",").compactMap { EditorMode(rawValue: String($0)) })
    }

    private var visible: [EditorMode] {
        EditorMode.allCases.filter { !hidden.contains($0) || $0 == editor.mode }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showLabels: true)
            row(showLabels: false)
        }
    }

    private func row(showLabels: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(visible) { mode in
                let selected = editor.mode == mode
                Button { editor.mode = mode } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.symbol).font(.system(size: 12, weight: .medium))
                        if showLabels { Text(mode.title).font(.system(size: 12, weight: selected ? .semibold : .regular)) }
                    }
                    .padding(.horizontal, showLabels ? 10 : 8)
                    .frame(height: 26)
                    .background(Capsule().fill(selected ? Color.accentColor.opacity(0.16) : .clear))
                    .foregroundStyle(selected ? Color.accentColor : .primary)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(shortcutHelp(mode))
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Button { customizing.toggle() } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .medium)).frame(width: 24, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Choose which toolsets appear")
            .popover(isPresented: $customizing, arrowEdge: .bottom) { customizePopover }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .fixedSize()
    }

    private func shortcutHelp(_ mode: EditorMode) -> String {
        let index = EditorMode.allCases.firstIndex(of: mode).map { $0 + 1 } ?? 0
        return "\(mode.title) — \(mode.subtitle) (⌘\(index))"
    }

    private var customizePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Toolsets").font(.headline)
            Text("Hide the ones you don’t use. They stay available from the menu bar.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(EditorMode.allCases.filter { $0 != .read }) { mode in
                Toggle(isOn: Binding(
                    get: { !hidden.contains(mode) },
                    set: { show in
                        var set = hidden
                        if show { set.remove(mode) } else { set.insert(mode) }
                        hiddenRaw = set.map(\.rawValue).sorted().joined(separator: ",")
                    })) {
                    Label(mode.title, systemImage: mode.symbol)
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}

/// Page layout, theme, zoom and split view in one popover.
struct DisplaySettingsButton: View {
    @ObservedObject var editor: EditorController
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Label("View", systemImage: "eyeglasses")
        }
        .help("Page layout, theme, zoom and split view")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            DisplaySettingsPopover(editor: editor)
        }
    }
}

struct DisplaySettingsPopover: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("Layout") {
                HStack(spacing: 8) {
                    layoutButton(.single, symbol: "doc", title: "Single")
                    layoutButton(.continuous, symbol: "doc.text", title: "Scroll")
                    layoutButton(.twoUp, symbol: "book.pages", title: "Two Pages")
                    layoutButton(.book, symbol: "book", title: "Book")
                }
            }
            section("Theme") {
                Picker("Theme", selection: $editor.theme) {
                    ForEach(ReadingTheme.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            section("Zoom") {
                HStack {
                    Button("Fit Width") { editor.fitWidth() }
                    Button("Fit Page") { editor.fitPage() }
                    Button("100%") { editor.actualSize() }
                }
                .controlSize(.small)
            }
            section("Split View") {
                HStack(spacing: 8) {
                    splitButton(nil, symbol: "rectangle", title: "Off")
                    splitButton(false, symbol: "rectangle.split.2x1", title: "Side by Side")
                    splitButton(true, symbol: "rectangle.split.1x2", title: "Stacked")
                }
                if editor.split != nil {
                    HStack {
                        Toggle("Sync scrolling", isOn: Binding(get: { editor.split?.sync ?? true }, set: { editor.split?.sync = $0 }))
                            .toggleStyle(.switch).controlSize(.small)
                        Spacer()
                        Button { editor.split?.swapped.toggle() } label: { Label("Swap Sides", systemImage: "arrow.left.arrow.right") }
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 330)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func layoutButton(_ layout: PageLayout, symbol: String, title: String) -> some View {
        TileButton(symbol: symbol, title: title, selected: editor.layout == layout) { editor.layout = layout }
    }

    private func splitButton(_ vertical: Bool?, symbol: String, title: String) -> some View {
        let selected = vertical == nil ? editor.split == nil : editor.split?.vertical == vertical
        return TileButton(symbol: symbol, title: title, selected: selected) {
            if let vertical {
                if editor.split == nil { editor.openSplit(vertical: vertical) } else { editor.split?.vertical = vertical }
            } else {
                editor.closeSplit()
            }
        }
    }
}

struct TileButton: View {
    let symbol: String
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 18, weight: .regular)).frame(height: 22)
                Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(hovering ? 0.08 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Shown after jumping through a link or the outline, to return to where you were.
/// Shared look for floating capsules and bars: Liquid Glass on macOS 26, material before.
extension View {
    @ViewBuilder
    func floatingChrome<S: InsettableShape>(_ shape: S) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
        }
    }
}

/// The surround behind pages, shared by the main view, split pane and Pages grid.
enum PageBackground {
    static let color = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1)
            : NSColor(srgbRed: 0.91, green: 0.91, blue: 0.92, alpha: 1)
    }
}

enum Radius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 10
    static let large: CGFloat = 14
}

struct BackToPagePill: View {
    @ObservedObject var editor: EditorController
    let page: Int

    var body: some View {
        HStack(spacing: 8) {
            Button { editor.returnToBackTarget() } label: {
                Label("Back to p. \(page + 1)", systemImage: "arrow.uturn.backward")
                    .font(.callout.weight(.medium))
            }
            .buttonStyle(.plain)
            Button { editor.backTarget = nil } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .floatingChrome(Capsule())
    }
}

/// "3 of 12" with previous/next, shown over the page while search results exist.
struct SearchResultsPill: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            Text("\(editor.searchIndex + 1) of \(editor.searchResults.count)").monospacedDigit().font(.callout.weight(.medium))
            Divider().frame(height: 16)
            Button { editor.findNext(-1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain).help("Previous match (⇧⌘G)").accessibilityLabel("Previous match")
            Button { editor.findNext() } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain).help("Next match (⌘G)").accessibilityLabel("Next match")
            Button { editor.searchText = ""; editor.clearSearch() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Clear search").accessibilityLabel("Clear search")
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .floatingChrome(Capsule())
    }
}

/// The second pane of split view: another document, or a chooser when empty.
struct SplitPaneView: View {
    @ObservedObject var editor: EditorController
    @State private var dropping = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.richtext").foregroundStyle(.secondary)
                Text(editor.split?.title ?? "Open a Document").font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Spacer()
                if editor.split?.document != nil {
                    Toggle("Sync", isOn: Binding(get: { editor.split?.sync ?? true }, set: { editor.split?.sync = $0 }))
                        .toggleStyle(.switch).controlSize(.mini)
                        .help("Scroll and zoom both documents together")
                    Button { editor.chooseSplitDocument() } label: { Image(systemName: "folder") }
                        .buttonStyle(.borderless).help("Open a different document here")
                }
                Button { editor.split?.swapped.toggle() } label: { Image(systemName: "arrow.left.arrow.right") }
                    .buttonStyle(.borderless).help("Swap sides")
                Button { editor.closeSplit() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("Close split view")
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(.bar)
            Divider()
            if let split = editor.split, let document = split.document {
                SplitPDFView(document: document, editor: editor)
                    .id(ObjectIdentifier(document))
            } else {
                chooser
            }
        }
    }

    private var chooser: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.split.2x1").font(.system(size: 34, weight: .light)).foregroundStyle(Color.accentColor)
            Text("Show a document side by side").font(.title3)
            HStack {
                Button("This Document") { editor.openSplitSameDocument() }.controlSize(.large)
                    .help("A second view of this document, to compare distant pages")
                Button("Choose Document…") { editor.chooseSplitDocument() }.controlSize(.large)
            }
            let recents = NSDocumentController.shared.recentDocumentURLs.filter { $0 != editor.fileURL }.prefix(6)
            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent").font(.caption).foregroundStyle(.secondary).padding(.leading, 8)
                    ForEach(Array(recents), id: \.self) { url in
                        Button { editor.openSplitDocument(url) } label: {
                            Label(url.deletingPathExtension().lastPathComponent, systemImage: "doc")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(HoverRowStyle())
                    }
                }
                .frame(maxWidth: 300)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(dropping ? Color.accentColor : .clear, style: StrokeStyle(lineWidth: 2, dash: [8, 5])).padding(10))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return false }
            editor.openSplitDocument(url)
            return true
        } isTargeted: { dropping = $0 }
    }
}

struct HoverRowStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.06 : 0)))
            .onHover { hovering = $0 }
    }
}

/// Read-only PDF view for the split pane, kept in step with the main document when sync is on.
struct SplitPDFView: NSViewRepresentable {
    let document: PDFDocument
    let editor: EditorController

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = PageBackground.color
        view.pageShadowsEnabled = true
        editor.attachSplitView(view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {}
}
