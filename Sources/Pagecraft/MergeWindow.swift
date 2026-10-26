import AppKit
import PDFKit
import PagecraftCore
import SwiftUI
import UniformTypeIdentifiers

/// The Merge Files window: collect PDFs, documents and images, put them in order and combine them into one PDF.
@MainActor
enum MergeWindow {
    private static var window: NSWindow?
    private static let model = MergeModel()
    private static var closeObserver: NSObjectProtocol?

    /// Opens the window, or brings it forward, and adds `initial` to its list.
    static func show(initial: [URL] = []) {
        if window == nil { makeWindow() }
        model.add(initial)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    static func close() { window?.close() }

    private static func makeWindow() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Merge Files"
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 560, height: 420)
        window.contentView = NSHostingView(rootView: MergeView(model: model))
        window.center()
        model.onFinished = { close() }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                // A new window starts from an empty list.
                model.items = []
                model.selection = nil
                model.insertionIndex = nil
                model.isTargeted = false
                if let observer = closeObserver { NotificationCenter.default.removeObserver(observer) }
                closeObserver = nil
                Self.window = nil
            }
        }
        Self.window = window
    }
}

// MARK: - Layout constants

private enum Metrics {
    static let rowHeight: CGFloat = 64
    static let listInset: CGFloat = 8
    static let spacing: CGFloat = 8
}

// MARK: - Window content

private struct UnlockRequest: Identifiable {
    let id: UUID
    let name: String
}

private struct MergeView: View {
    @ObservedObject var model: MergeModel
    @State private var unlocking: UnlockRequest?
    @FocusState private var listFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .onDrop(of: [.fileURL], delegate: MergeDrop(model: model, listTopInset: nil))
            Divider()
            content
            Divider()
            footer
                .onDrop(of: [.fileURL], delegate: MergeDrop(model: model, listTopInset: nil))
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $unlocking) { request in
            UnlockSheet(name: request.name) { password in model.unlock(request.id, password: password) }
        }
        // Keyboard: ⌫ removes the selected row, ⌘O adds files, ⌘↩ merges.
        .background {
            Group {
                Button("Remove Selected File") { model.removeSelection() }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(model.selection == nil || model.isMerging)
                Button("Add Files") { addFiles() }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(model.isMerging)
            }
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            SheetHeader(symbol: "square.stack.3d.down.right", title: "Merge Files",
                        subtitle: model.items.isEmpty
                            ? "Combine PDFs, documents and images into one PDF."
                            : "Drag files to put them in order. They are merged from top to bottom.")
            Spacer(minLength: 0)
            Menu {
                Button("Name") { model.sortByName() }
                Button("Date Modified") { model.sortByDate() }
                Divider()
                Button("Reverse") { model.reverse() }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.button)
            .fixedSize()
            .disabled(model.items.count < 2 || model.isMerging)
            .help("Sort the files")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if model.items.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(model.isTargeted ? Color.accentColor : .secondary)
            Text("Drop files here").font(.title3.weight(.medium))
            Text("PDF, Word, RTF, HTML, Markdown, text and images")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Add Files…") { addFiles() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(model.isTargeted ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(model.isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 2, dash: model.isTargeted ? [] : [8, 6]))
        )
        .padding(24)
        .animation(.easeOut(duration: 0.15), value: model.isTargeted)
        .onDrop(of: [.fileURL], delegate: MergeDrop(model: model, listTopInset: nil))
    }

    private var list: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroller in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        LazyVStack(spacing: 0) {
                            ForEach(model.items) { item in
                                MergeRow(item: item, selected: model.selection == item.id,
                                         onSelect: { model.selection = item.id; listFocused = true },
                                         onRemove: { model.remove(item.id) },
                                         onUnlock: { unlocking = UnlockRequest(id: item.id, name: item.name) },
                                         onDragStart: { model.draggingID = item.id })
                                    .id(item.id)
                            }
                        }
                        .padding(.horizontal, Metrics.listInset)
                        .padding(.top, Metrics.listInset)
                        insertionIndicator
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture { model.selection = nil }
                    .onDrop(of: [.fileURL, .plainText], delegate: MergeDrop(model: model, listTopInset: Metrics.listInset))
                }
                .onChange(of: model.selection) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.12)) { scroller.scrollTo(id) } }
                }
            }
        }
        .overlay {
            if model.isTargeted && model.draggingID == nil {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.06)))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onMoveCommand { direction in
            switch direction {
            case .up: model.moveSelection(by: -1)
            case .down: model.moveSelection(by: 1)
            default: break
            }
        }
        .disabled(model.isMerging)
    }

    @ViewBuilder private var insertionIndicator: some View {
        if let index = model.insertionIndex, model.isTargeted {
            HStack(spacing: 0) {
                Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                Capsule().fill(Color.accentColor).frame(height: 3)
            }
            .padding(.horizontal, Metrics.listInset + 4)
            .offset(y: Metrics.listInset + CGFloat(index) * Metrics.rowHeight - 4)
            .allowsHitTesting(false)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            status
            Spacer(minLength: 12)
            Button("Add Files…") { addFiles() }
                .disabled(model.isMerging)
                .help("Add files (⌘O)")
            Button("Merge") { model.merge() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canMerge)
                .help("Merge into one PDF (⌘↩)")
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder private var status: some View {
        if model.isMerging {
            HStack(spacing: 10) {
                if let progress = model.progress {
                    ProgressView(value: progress).progressViewStyle(.linear).frame(width: 140)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(model.progressText).foregroundStyle(.secondary).monospacedDigit()
            }
        } else if model.lockedCount > 0 {
            Label("Unlock \(model.lockedCount) password-protected \(model.lockedCount == 1 ? "PDF" : "PDFs") to merge",
                  systemImage: "lock.fill")
                .foregroundStyle(.orange)
        } else if model.items.isEmpty {
            Text("No files").foregroundStyle(.secondary)
        } else {
            Text(summary).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var summary: String {
        let files = "\(model.items.count) \(model.items.count == 1 ? "file" : "files")"
        let pages = "\(model.knownPages) \(model.knownPages == 1 ? "page" : "pages")"
        return model.convertedCount > 0 ? "\(files) · \(pages) + converted files" : "\(files) · \(pages)"
    }

    private func addFiles() {
        let urls = Prompt.open(Convert.supportedTypes, multiple: true, title: "Add Files to Merge")
        model.add(urls)
    }
}

// MARK: - Rows

private struct MergeRow: View {
    let item: MergeItem
    let selected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onUnlock: () -> Void
    let onDragStart: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            MergeThumbnail(item: item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(item.error != nil || item.state == .failed ? Color.red : item.state == .locked ? Color.orange : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if item.state == .locked {
                Button("Unlock…", action: onUnlock)
                    .controlSize(.small)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .help("Remove from the list")
            .accessibilityLabel("Remove \(item.name)")
            .opacity(hovering || selected ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .frame(height: Metrics.rowHeight - Metrics.spacing)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.16) : hovering ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
        )
        .frame(height: Metrics.rowHeight)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
        .onDrag {
            onDragStart()
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Divider()
            Button("Remove", role: .destructive, action: onRemove)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MergeThumbnail: View {
    let item: MergeItem

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if item.state == .loading {
                    ProgressView().controlSize(.small)
                } else if let image = item.thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: item.thumbnailIsIcon ? 0 : 3, style: .continuous))
                        .shadow(color: .black.opacity(item.thumbnailIsIcon ? 0 : 0.25), radius: 1.5, y: 0.5)
                        .opacity(item.state == .locked ? 0.55 : 1)
                } else {
                    Image(systemName: "doc").font(.title2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 48)
            if item.state == .locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.orange))
                    .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                    .offset(x: 4, y: 3)
            }
        }
        .frame(width: 48, height: 52)
    }
}

// MARK: - Unlock

private struct UnlockSheet: View {
    let name: String
    let attempt: (String) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "lock.doc", title: "Password required",
                        subtitle: "Enter the password for “\(name)” to include it in the merge.")
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(unlock)
                .onChange(of: password) { _, _ in failed = false }
            if failed {
                Label("Incorrect password", systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Unlock", action: unlock)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        if attempt(password) { dismiss() } else { failed = true }
    }
}

// MARK: - Dropping

/// Accepts files from Finder (appended, or inserted where the highlight shows) and reorders rows dragged inside the list.
private struct MergeDrop: DropDelegate {
    let model: MergeModel
    /// Top padding of the list when the delegate sits on the list itself; nil appends at the end.
    let listTopInset: CGFloat?

    private func insertion(at location: CGPoint) -> Int {
        guard let inset = listTopInset else { return model.items.count }
        let raw = ((location.y - inset) / Metrics.rowHeight).rounded()
        return min(max(Int(raw), 0), model.items.count)
    }

    private func hasFiles(_ info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func validateDrop(info: DropInfo) -> Bool { hasFiles(info) || (model.draggingID != nil && listTopInset != nil) }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: hasFiles(info) ? .copy : .move)
    }

    func dropExited(info: DropInfo) {
        model.isTargeted = false
        model.insertionIndex = nil
    }

    private func update(_ info: DropInfo) {
        model.isTargeted = true
        guard listTopInset != nil, !model.items.isEmpty else { model.insertionIndex = nil; return }
        let index = insertion(at: info.location)
        // Dropping a row where it already is changes nothing, so show no highlight.
        if !hasFiles(info), let id = model.draggingID, let from = model.items.firstIndex(where: { $0.id == id }),
           index == from || index == from + 1 {
            model.insertionIndex = nil
        } else {
            model.insertionIndex = index
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let index = listTopInset == nil ? nil : insertion(at: info.location)
        defer {
            model.isTargeted = false
            model.insertionIndex = nil
            model.draggingID = nil
        }
        if hasFiles(info) {
            let providers = info.itemProviders(for: [.fileURL])
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    if let url = await Self.fileURL(from: provider) { urls.append(url) }
                }
                model.add(urls, at: index)
            }
            return true
        }
        if let id = model.draggingID, let index {
            model.move(id, toInsertion: index)
            return true
        }
        return false
    }

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }
}
