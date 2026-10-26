import PDFKit
import PagecraftCore
import SwiftUI

struct DocumentView: View {
    @ObservedObject var file: PDFFile
    @StateObject private var editor: EditorController
    @Environment(\.undoManager) private var undoManager

    init(file: PDFFile) {
        self.file = file
        _editor = StateObject(wrappedValue: EditorController(file: file))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(editor: editor)
                .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 340)
        } detail: {
            VStack(spacing: 0) {
                ToolStrip(editor: editor)
                Divider()
                PDFKitView(editor: editor)
                Divider()
                StatusBar(editor: editor)
            }
        }
        .toolbar { MainToolbar(editor: editor) }
        .searchable(text: $editor.searchText, placement: .toolbar, prompt: "Search")
        .onSubmit(of: .search) { editor.search() }
        .onChange(of: editor.searchText) { _, text in if text.isEmpty { editor.clearSearch() } }
        .focusedSceneValue(\.editor, editor)
        .onAppear { editor.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in editor.undoManager = manager }
        .sheet(isPresented: $editor.showSignaturePad) { SignaturePad(editor: editor) }
        .sheet(isPresented: $editor.showProperties) { PropertiesView(editor: editor) }
        .sheet(isPresented: $editor.needsPassword) { UnlockView(editor: editor) }
    }
}

struct ToolStrip: View {
    @ObservedObject var editor: EditorController
    private let swatches: [Color] = [.yellow, .green, .blue, .pink, .red, .black]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tool.allCases) { tool in
                Button { editor.tool = tool } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 26, height: 22)
                        .background(editor.tool == tool ? Color.accentColor.opacity(0.25) : .clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(tool.label)
                if tool == .select || tool == .strikeout || tool == .note || tool == .arrow {
                    Divider().frame(height: 18).padding(.horizontal, 4)
                }
            }
            Divider().frame(height: 18).padding(.horizontal, 4)
            ForEach(swatches, id: \.self) { swatch in
                Circle()
                    .fill(swatch)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.primary.opacity(editor.color == swatch ? 0.8 : 0.15), lineWidth: 2))
                    .onTapGesture { editor.color = swatch }
            }
            ColorPicker("Color", selection: $editor.color).labelsHidden()
            Menu {
                ForEach([1, 2, 3, 5, 8], id: \.self) { width in
                    Button("\(width) pt") { editor.lineWidth = CGFloat(width) }
                }
            } label: {
                Image(systemName: "lineweight")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 40)
            .help("Line Width")
            Spacer()
            if editor.hasRedactions {
                Button("Apply Redactions") { editor.applyRedactions() }
                    .controlSize(.small)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

struct StatusBar: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        HStack {
            Button { editor.goToPage(editor.currentPageIndex - 1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .disabled(editor.currentPageIndex == 0)
            Text("Page \(editor.currentPageIndex + 1) of \(editor.pageCount)")
                .monospacedDigit()
            Button { editor.goToPage(editor.currentPageIndex + 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .disabled(editor.currentPageIndex + 1 >= editor.pageCount)
            Spacer()
            if !editor.searchResults.isEmpty {
                Text("\(editor.searchIndex + 1) of \(editor.searchResults.count) matches")
                    .foregroundStyle(.secondary)
            }
            Text("\(Int((editor.scale * 100).rounded()))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
    }
}

struct MainToolbar: ToolbarContent {
    @ObservedObject var editor: EditorController

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Button { editor.zoomOut() } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
                Button { editor.zoomIn() } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }
            }
            Menu {
                Picker("Layout", selection: $editor.layout) {
                    ForEach(PageLayout.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                Picker("Theme", selection: $editor.theme) {
                    ForEach(ReadingTheme.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("View", systemImage: "doc.richtext")
            }
            Button { editor.rotate(-90) } label: { Label("Rotate Left", systemImage: "rotate.left") }
            Button { editor.rotate(90) } label: { Label("Rotate Right", systemImage: "rotate.right") }
        }
    }
}

struct UnlockView: View {
    @ObservedObject var editor: EditorController
    @State private var password = ""
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("This document is password protected", systemImage: "lock.doc")
                .font(.headline)
            SecureField("Password", text: $password)
                .onSubmit(unlock)
            if failed { Text("Incorrect password.").foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Unlock", action: unlock).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .interactiveDismissDisabled()
    }

    private func unlock() {
        failed = !editor.unlock(with: password)
        if !failed { dismiss() }
    }
}

struct PropertiesView: View {
    @ObservedObject var editor: EditorController
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var author = ""
    @State private var subject = ""
    @State private var keywords = ""

    var body: some View {
        Form {
            TextField("Title", text: $title)
            TextField("Author", text: $author)
            TextField("Subject", text: $subject)
            TextField("Keywords", text: $keywords)
            LabeledContent("Pages", value: "\(editor.pageCount)")
            LabeledContent("PDF version", value: "\(editor.document.majorVersion).\(editor.document.minorVersion)")
            LabeledContent("Encrypted", value: editor.document.isEncrypted ? "Yes" : "No")
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    var attributes = editor.document.documentAttributes ?? [:]
                    attributes[PDFDocumentAttribute.titleAttribute] = title
                    attributes[PDFDocumentAttribute.authorAttribute] = author
                    attributes[PDFDocumentAttribute.subjectAttribute] = subject
                    attributes[PDFDocumentAttribute.keywordsAttribute] = keywords
                        .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    editor.setAttributes(attributes)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            let attributes = editor.document.documentAttributes ?? [:]
            title = attributes[PDFDocumentAttribute.titleAttribute] as? String ?? ""
            author = attributes[PDFDocumentAttribute.authorAttribute] as? String ?? ""
            subject = attributes[PDFDocumentAttribute.subjectAttribute] as? String ?? ""
            keywords = (attributes[PDFDocumentAttribute.keywordsAttribute] as? [String])?.joined(separator: ", ")
                ?? attributes[PDFDocumentAttribute.keywordsAttribute] as? String ?? ""
        }
    }
}

struct SignaturePad: View {
    @ObservedObject var editor: EditorController
    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [[CGPoint]] = []
    private let height: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Draw your signature").font(.headline)
            Canvas { context, _ in
                for stroke in strokes where !stroke.isEmpty {
                    var path = Path()
                    path.addLines(stroke)
                    context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: 440, height: height)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if value.translation == .zero { strokes.append([value.location]) } else { strokes[strokes.count - 1].append(value.location) }
                })
            Text("Saved on this Mac only. Pick the Signature tool and click a page to place it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Clear") { strokes = [] }
                if SignatureStore.load() != nil {
                    Button("Delete Saved Signature") { SignatureStore.save(nil); dismiss() }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    SignatureStore.save(Signature(viewStrokes: strokes, viewHeight: height))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(strokes.isEmpty)
            }
        }
        .padding(20)
    }
}
