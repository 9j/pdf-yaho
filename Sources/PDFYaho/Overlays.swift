import PDFYahoCore
import SwiftUI

/// Everything drawn over the PDF: selection chrome, contextual menus, the page/zoom HUD and toasts.
struct DocumentOverlays: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if editor.mode == .read || editor.mode == .annotate, let page = editor.hoverPage, let frame = editor.hoverPageFrame {
                    let index = editor.document.index(for: page)
                    BookmarkRibbon(marked: editor.isBookmarked(index)) { editor.toggleBookmark(index) }
                        .position(x: frame.maxX - 22, y: max(frame.minY, 0) + 18)
                }
                if editor.mode == .edit {
                    ContentEditOverlay(editor: editor, size: geo.size)
                }
                if let frame = editor.cropFrame {
                    CropChrome(frame: frame, size: geo.size)
                    CropBar(editor: editor)
                        .fixedSize()
                        .position(x: min(max(frame.midX, 200), geo.size.width - 200),
                                  y: min(frame.maxY + 34, geo.size.height - 90))
                } else if editor.tool == .crop {
                    Text("Drag over the area of the page to keep · Esc to cancel")
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(.regularMaterial, in: Capsule())
                        .position(x: geo.size.width / 2, y: 30)
                }
                if let frame = editor.selectionFrame {
                    SelectionChrome(frame: frame, resizable: editor.selected.map { Annotations.isResizable($0.annotation) } ?? false)
                    AnnotationContextBar(editor: editor)
                        .fixedSize()
                        .position(barPosition(above: frame, in: geo.size))
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else if let frame = editor.textSelectionFrame {
                    TextSelectionMenu(editor: editor)
                        .fixedSize()
                        .position(barPosition(above: frame, in: geo.size))
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .animation(.snappy(duration: 0.18), value: editor.selected)
            .animation(.snappy(duration: 0.18), value: editor.textSelectionActive)
        }
    }

    private func barPosition(above frame: CGRect, in size: CGSize) -> CGPoint {
        let x = min(max(frame.midX, 140), size.width - 140)
        let y = frame.minY > 60 ? frame.minY - 30 : min(frame.maxY + 30, size.height - 80)
        return CGPoint(x: x, y: y)
    }
}

/// Bookmark toggle shown in the top corner of the page under the pointer.
struct BookmarkRibbon: View {
    let marked: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: marked ? "bookmark.fill" : "bookmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(marked ? Color.red : Color.secondary.opacity(hovering ? 0.9 : 0.5))
                .frame(width: 30, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(marked ? "Remove bookmark (⌘D)" : "Bookmark this page (⌘D)")
    }
}

struct CropChrome: View {
    let frame: CGRect
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(frame)
            }
            .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
            Rectangle()
                .strokeBorder(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
        }
        .allowsHitTesting(false)
    }
}

struct CropBar: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "crop").foregroundStyle(.secondary)
            Button("Cancel") { editor.cropDraft = nil; editor.tool = .select }
            Button(editor.selectedPages.count > 1 ? "Crop \(editor.selectedPages.count) Pages" : "Crop This Page") {
                editor.applyCrop(toAll: false)
            }
            Button("Crop All Pages") { editor.applyCrop(toAll: true) }
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .frame(height: 44)
        .floatingChrome(Capsule())
    }
}

struct SelectionChrome: View {
    let frame: CGRect
    let resizable: Bool

    var body: some View {
        let box = frame.insetBy(dx: -3, dy: -3)
        ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: box.width, height: box.height)
                .offset(x: box.minX, y: box.minY)
            if resizable {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(.white)
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                        .frame(width: 10, height: 10)
                        .shadow(color: .black.opacity(0.2), radius: 1)
                        .position(x: i % 2 == 0 ? frame.minX : frame.maxX, y: i < 2 ? frame.minY : frame.maxY)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Floating bar above a selected annotation.
struct AnnotationContextBar: View {
    @ObservedObject var editor: EditorController
    @State private var showStyle = false

    var body: some View {
        if let selected = editor.selected {
            let a = selected.annotation
            HStack(spacing: 2) {
                if Annotations.isRedaction(a) {
                    BarButton(symbol: "checkmark.seal", label: "Apply Redactions") { editor.applyRedactions() }
                } else {
                    Button { showStyle.toggle() } label: {
                        Circle().fill(Color(nsColor: editor.activeColor))
                            .overlay(Circle().strokeBorder(.primary.opacity(0.2)))
                            .frame(width: 16, height: 16)
                            .frame(width: 30, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Colour")
                    .popover(isPresented: $showStyle, arrowEdge: .top) { StylePopover(editor: editor) }
                }
                if a.type == "Text", let note = a.contents, !note.isEmpty {
                    Text(note).lineLimit(1).font(.callout).frame(maxWidth: 220).padding(.horizontal, 6)
                        .foregroundStyle(.secondary)
                }
                if ["FreeText", "Text"].contains(a.type ?? "") || a is CalloutAnnotation {
                    BarButton(symbol: "pencil", label: "Edit") { editor.beginEditingSelected() }
                } else if !Annotations.isRedaction(a), a.type != "Link" {
                    CommentButton(editor: editor, selection: selected)
                }
                if Annotations.isMovable(a) {
                    BarButton(symbol: "plus.square.on.square", label: "Duplicate") { editor.duplicateSelected() }
                }
                if a.type == "Link" {
                    Text(a.url?.absoluteString ?? a.destination?.page.map { "Page \(editor.document.index(for: $0) + 1)" } ?? "Link")
                        .lineLimit(1).font(.callout).foregroundStyle(.secondary).frame(maxWidth: 220).padding(.horizontal, 6)
                }
                if a is ImageAnnotation {
                    BarButton(symbol: "photo.on.rectangle", label: "Replace Image…") { editor.replaceSelectedImage() }
                }
                Menu {
                    if a is ImageAnnotation {
                        Button("Replace Image…") { editor.replaceSelectedImage() }
                        Button("Save Image…") { editor.saveSelectedImage() }
                        Divider()
                    }
                    Button("Copy") { editor.copySelectedAnnotation() }
                    Button("Cut") { editor.copySelectedAnnotation(cut: true) }
                    Divider()
                    Button("Bring to Front") { editor.reorderSelected(toFront: true) }
                    Button("Send to Back") { editor.reorderSelected(toFront: false) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).frame(width: 30, height: 28)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
                Divider().frame(height: 18).padding(.horizontal, 2)
                BarButton(symbol: "trash", label: "Delete", role: .destructive) { editor.deleteSelected() }
            }
            .padding(.horizontal, 6)
            .frame(height: 36)
            .floatingChrome(Capsule())
        }
    }
}

/// Floating menu above selected text in Read mode.
struct TextSelectionMenu: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        HStack(spacing: 2) {
            ForEach([Tool.highlight, .underline, .strikeout]) { tool in
                Button { editor.markSelection(with: tool) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tool.symbol)
                        Text(tool.label)
                    }
                    .font(.callout)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(alignment: .bottom) {
                        Capsule().fill(Color(nsColor: editor.style(for: tool).color)).frame(height: 3).padding(.horizontal, 10)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(HoverButtonStyle())
            }
            Divider().frame(height: 18).padding(.horizontal, 2)
            Button { editor.copySelection() } label: {
                Label("Copy", systemImage: "doc.on.doc").font(.callout).padding(.horizontal, 9).frame(height: 28)
            }
            .buttonStyle(HoverButtonStyle())
        }
        .padding(.horizontal, 4)
        .frame(height: 36)
        .floatingChrome(Capsule())
    }
}

/// Adds or edits the comment attached to a highlight, shape or stamp.
struct CommentButton: View {
    @ObservedObject var editor: EditorController
    let selection: SelectedAnnotation
    @State private var open = false
    @State private var draft = ""

    var body: some View {
        let hasComment = !(selection.annotation.contents ?? "").isEmpty
        BarButton(symbol: hasComment ? "text.bubble.fill" : "text.bubble", label: hasComment ? "Edit Comment" : "Add Comment") {
            draft = hasComment ? (selection.annotation.contents ?? "") : ""
            open = true
        }
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Comment").font(.headline)
                TextEditor(text: $draft)
                    .font(.body)
                    .frame(width: 260, height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                HStack {
                    if hasComment {
                        Button("Remove", role: .destructive) { editor.setComment("", of: selection.annotation, on: selection.page); open = false }
                    }
                    Spacer()
                    Button("Done") {
                        editor.setComment(draft.trimmingCharacters(in: .whitespacesAndNewlines), of: selection.annotation, on: selection.page)
                        open = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
    }
}

struct BarButton: View {
    let symbol: String
    let label: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(role == .destructive ? Color.red : .primary)
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

struct HoverButtonStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.14 : hovering ? 0.07 : 0)))
            .onHover { hovering = $0 }
    }
}

/// Bottom-centre capsule with page navigation and zoom.
struct PageHUD: View {
    @ObservedObject var editor: EditorController
    @State private var pageText = ""
    @FocusState private var pageFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            BarButton(symbol: "chevron.up", label: "Previous Page") { editor.goToPage(editor.currentPageIndex - 1) }
                .disabled(editor.currentPageIndex == 0)
            TextField("Page", text: $pageText)
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .frame(width: editor.hasPageLabels ? 52 : 34, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(pageFocused ? 0.1 : 0.05)))
                .focused($pageFocused)
                .onSubmit {
                    if let index = editor.pageIndex(forLabel: pageText) { editor.goToPage(index) }
                    pageFocused = false
                }
            Text(editor.hasPageLabels ? "(\(editor.currentPageIndex + 1) of \(editor.pageCount))" : "of \(editor.pageCount)")
                .foregroundStyle(.secondary).monospacedDigit()
            BarButton(symbol: "chevron.down", label: "Next Page") { editor.goToPage(editor.currentPageIndex + 1) }
                .disabled(editor.currentPageIndex + 1 >= editor.pageCount)
            Divider().frame(height: 18).padding(.horizontal, 4)
            BarButton(symbol: "minus", label: "Zoom Out (⌘-)") { editor.zoomOut() }
            Menu {
                Button("Fit Width") { editor.fitWidth() }
                Button("Fit Page") { editor.fitPage() }
                Divider()
                ForEach([50, 75, 100, 125, 150, 200, 300], id: \.self) { percent in
                    Button("\(percent)%") { editor.zoom(to: CGFloat(percent) / 100) }
                }
            } label: {
                Text("\(Int((editor.scale * 100).rounded()))%").monospacedDigit().frame(minWidth: 42)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            BarButton(symbol: "plus", label: "Zoom In (⌘+)") { editor.zoomIn() }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .frame(height: 38)
        .floatingChrome(Capsule())
        .onHover { editor.hudHovered = $0 }
        .onAppear { pageText = editor.pageLabel(editor.currentPageIndex) }
        .onChange(of: editor.currentPageIndex) { _, index in if !pageFocused { pageText = editor.pageLabel(index) } }
        .onChange(of: pageFocused) { _, focused in if !focused { pageText = editor.pageLabel(editor.currentPageIndex) } }
        .onChange(of: editor.pageLabels) { _, _ in if !pageFocused { pageText = editor.pageLabel(editor.currentPageIndex) } }
        .onChange(of: editor.focusPageField) { _, focus in
            if focus { pageFocused = true; editor.focusPageField = false }
        }
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Group {
                switch toast.kind {
                case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .info: Image(systemName: "info.circle.fill").foregroundStyle(Color.accentColor)
                case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            Text(toast.message)
            if let url = toast.url {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(.link)
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .floatingChrome(Capsule())
    }
}
