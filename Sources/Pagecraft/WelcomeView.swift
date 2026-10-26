import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Start window: quick actions on the left, recent documents on the right. Shown when no document is open.
@MainActor
final class WelcomeWindowController {
    static let shared = WelcomeWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 860, height: 540),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WelcomeView())
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.orderOut(nil) }
}

struct WelcomeView: View {
    @State private var recents: [URL] = NSDocumentController.shared.recentDocumentURLs
    @State private var dropping = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                    .padding(.top, 44)
                Text("Pagecraft").font(.system(size: 28, weight: .bold))
                    .padding(.top, 10)
                Text("Free, open-source PDF editor").foregroundStyle(.secondary)
                    .padding(.top, 2)
                VStack(spacing: 6) {
                    ActionRow(symbol: "folder", title: "Open PDF…", shortcut: "⌘O") { run { NSDocumentController.shared.openDocument(nil) } }
                    ActionRow(symbol: "doc.badge.plus", title: "New Blank PDF", shortcut: "⌘N") { run { NSDocumentController.shared.newDocument(nil) } }
                    ActionRow(symbol: "photo.on.rectangle", title: "PDF from Images…", shortcut: nil) { run { Exporter.newFromImages() } }
                    ActionRow(symbol: "square.stack.3d.down.right", title: "Merge PDFs…", shortcut: nil) { run { Exporter.mergeFiles() } }
                }
                .padding(.top, 30)
                Spacer()
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") · MIT License")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 28)
            .frame(width: 300)
            .frame(maxHeight: .infinity)
            .background(.regularMaterial)

            VStack(alignment: .leading, spacing: 14) {
                Text("Recent").font(.title3.weight(.semibold)).padding(.top, 40)
                if recents.isEmpty {
                    DropZone(highlighted: dropping)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 18)], spacing: 20) {
                            ForEach(recents, id: \.self) { url in
                                RecentTile(url: url) { open(url) }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay {
                if dropping, !recents.isEmpty {
                    RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                        .padding(12)
                }
            }
        }
        .frame(width: 860, height: 540)
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            pdfs.forEach(open)
            return !pdfs.isEmpty
        } isTargeted: { dropping = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            recents = NSDocumentController.shared.recentDocumentURLs
        }
    }

    private func run(_ action: @escaping () -> Void) {
        WelcomeWindowController.shared.close()
        action()
    }

    private func open(_ url: URL) {
        WelcomeWindowController.shared.close()
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if error != nil { WelcomeWindowController.shared.show() }
        }
    }
}

private struct ActionRow: View {
    let symbol: String
    let title: String
    let shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                Text(title)
                Spacer()
                if let shortcut { Text(shortcut).font(.callout).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct RecentTile: View {
    let url: URL
    let action: () -> Void
    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05))
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                            .background(.white)
                            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                            .padding(12)
                    } else {
                        Image(systemName: "doc.richtext").font(.largeTitle).foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 160)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(hovering ? Color.accentColor : .clear, lineWidth: 2))
                Text(url.deletingPathExtension().lastPathComponent).font(.callout.weight(.medium)).lineLimit(1)
                Text(modified).font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(url.path)
        .task {
            thumbnail = PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: CGSize(width: 260, height: 300), for: .cropBox)
        }
    }

    private var modified: String {
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return "" }
        return date.formatted(.relative(presentation: .named))
    }
}

private struct DropZone: View {
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc").font(.system(size: 36, weight: .light)).foregroundStyle(Color.accentColor)
            Text("Drop a PDF here to open it").font(.title3)
            Text("Documents you open will appear here.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(highlighted ? Color.accentColor.opacity(0.08) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(highlighted ? Color.accentColor : Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
        .padding(.bottom, 28)
    }
}
