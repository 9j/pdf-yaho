import PagecraftCore
import SwiftUI

/// Everything drawn over the PDF: selection chrome, contextual menus, the page/zoom HUD and toasts.
struct DocumentOverlays: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
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
                if ["FreeText", "Text"].contains(a.type ?? "") {
                    BarButton(symbol: "pencil", label: "Edit") { editor.beginEditingSelected() }
                }
                if Annotations.isMovable(a) {
                    BarButton(symbol: "plus.square.on.square", label: "Duplicate") { editor.duplicateSelected() }
                }
                Divider().frame(height: 18).padding(.horizontal, 2)
                BarButton(symbol: "trash", label: "Delete", role: .destructive) { editor.deleteSelected() }
            }
            .padding(.horizontal, 6)
            .frame(height: 36)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
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
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
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
            TextField("", text: $pageText)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .frame(width: 34, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(pageFocused ? 0.1 : 0.05)))
                .focused($pageFocused)
                .onSubmit {
                    if let n = Int(pageText) { editor.goToPage(n - 1) }
                    pageFocused = false
                }
            Text("of \(editor.pageCount)").foregroundStyle(.secondary).monospacedDigit()
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
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
        .onAppear { pageText = "\(editor.currentPageIndex + 1)" }
        .onChange(of: editor.currentPageIndex) { _, index in if !pageFocused { pageText = "\(index + 1)" } }
        .onChange(of: pageFocused) { _, focused in if !focused { pageText = "\(editor.currentPageIndex + 1)" } }
        .onChange(of: editor.focusPageField) { _, focus in
            if focus { pageFocused = true; editor.focusPageField = false }
        }
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(toast.message)
            if let url = toast.url {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(.link)
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
    }
}
