import PDFKit
import PDFYahoCore
import SwiftUI

/// Two documents side by side with synchronised scrolling and zoom (PDF Expert's Split View).
@MainActor
enum CompareWindow {
    private static var windows: [NSWindow] = []

    static func open(left: PDFDocument, leftTitle: String, right: PDFDocument, rightTitle: String) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1400, height: 900),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "\(leftTitle) ↔ \(rightTitle)"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CompareView(left: (left, leftTitle), right: (right, rightTitle)))
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { windows.removeAll { $0 === window } }
        }
    }

    /// Compare two files picked by the user.
    static func chooseFiles() {
        let urls = Prompt.open([.pdf], multiple: true, title: "Choose Two PDFs to Compare")
        guard urls.count == 2, let a = PDFDocument(url: urls[0]), let b = PDFDocument(url: urls[1]) else {
            if !urls.isEmpty { Prompt.error("Choose exactly two PDF documents (hold ⌘ to select both).") }
            return
        }
        open(left: a, leftTitle: urls[0].deletingPathExtension().lastPathComponent,
             right: b, rightTitle: urls[1].deletingPathExtension().lastPathComponent)
    }

    /// Compare the given editor's document with a file picked by the user.
    static func compare(_ editor: EditorController) {
        guard let url = Prompt.open([.pdf], multiple: false, title: "Compare “\(editor.title)” With…").first,
              let other = PDFDocument(url: url) else { return }
        open(left: editor.document, leftTitle: editor.title, right: other, rightTitle: url.deletingPathExtension().lastPathComponent)
    }
}

/// Keeps two PDF views on the same page, position and zoom.
@MainActor
final class ScrollSync: ObservableObject {
    @Published var enabled = true
    private(set) var left: PDFView?
    private(set) var right: PDFView?
    private var updating = false
    private var observers: [NSObjectProtocol] = []

    func attach(_ view: PDFView, isLeft: Bool) {
        if isLeft { left = view } else { right = view }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .PDFViewScaleChanged, object: view, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow(view) }
        })
        DispatchQueue.main.async { [weak self] in
            guard let clip = view.documentView?.enclosingScrollView?.contentView else { return }
            clip.postsBoundsChangedNotifications = true
            self?.observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.follow(view) }
            })
        }
    }

    private func follow(_ source: PDFView) {
        guard enabled, !updating, let target = source === left ? right : left,
              let destination = source.currentDestination, let page = destination.page,
              let sourceDoc = source.document, let targetDoc = target.document else { return }
        let index = sourceDoc.index(for: page)
        guard let targetPage = targetDoc.page(at: min(index, targetDoc.pageCount - 1)) else { return }
        updating = true
        if abs(target.scaleFactor - source.scaleFactor) > 0.001 { target.autoScales = false; target.scaleFactor = source.scaleFactor }
        target.go(to: PDFDestination(page: targetPage, at: destination.point))
        DispatchQueue.main.async { self.updating = false }
    }
}

private struct ComparePane: NSViewRepresentable {
    let document: PDFDocument
    let isLeft: Bool
    let sync: ScrollSync

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .underPageBackgroundColor
        sync.attach(view, isLeft: isLeft)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}

struct CompareView: View {
    @State var left: (PDFDocument, String)
    @State var right: (PDFDocument, String)
    @StateObject private var sync = ScrollSync()
    @State private var vertical = false
    @State private var generation = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(left.1).font(.headline).lineLimit(1)
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                Text(right.1).font(.headline).lineLimit(1)
                Spacer()
                Toggle("Sync Scroll and Zoom", isOn: $sync.enabled).toggleStyle(.switch).controlSize(.small)
                Picker("Layout", selection: $vertical) {
                    Image(systemName: "rectangle.split.2x1").tag(false)
                    Image(systemName: "rectangle.split.1x2").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 90)
                .help("Side by side or stacked")
                Button { swap(&left, &right); generation += 1 } label: { Label("Swap Sides", systemImage: "arrow.left.arrow.right.square") }
                Button("Change Right Document…") {
                    if let url = Prompt.open([.pdf], multiple: false, title: "Change Right Document").first, let doc = PDFDocument(url: url) {
                        right = (doc, url.deletingPathExtension().lastPathComponent)
                        generation += 1
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 30)
            .padding(.bottom, 10)
            .background(.bar)
            Divider()
            Group {
                if vertical {
                    VSplitView { panes }
                } else {
                    HSplitView { panes }
                }
            }
            .id(generation)
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    @ViewBuilder private var panes: some View {
        ComparePane(document: left.0, isLeft: true, sync: sync)
        ComparePane(document: right.0, isLeft: false, sync: sync)
    }
}
