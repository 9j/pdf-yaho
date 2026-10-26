import PDFKit
import PagecraftCore
import SwiftUI

struct DocumentView: View {
    @ObservedObject var file: PDFFile
    @StateObject private var editor: EditorController
    @Environment(\.undoManager) private var undoManager
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var columnsBeforePages: NavigationSplitViewVisibility = .all

    init(file: PDFFile) {
        self.file = file
        _editor = StateObject(wrappedValue: EditorController(file: file))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(editor: editor)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 340)
        } detail: {
            ZStack {
                PDFKitView(editor: editor)
                    .overlay { DocumentOverlays(editor: editor) }
                    .overlay(alignment: .top) {
                        if editor.mode == .markup {
                            MarkupPalette(editor: editor)
                                .padding(.top, 12)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .overlay(alignment: .bottom) { PageHUD(editor: editor).padding(.bottom, 16) }
                if editor.mode == .pages {
                    PageGridView(editor: editor)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if let toast = editor.toast {
                    ToastView(toast: toast)
                        .padding(.bottom, 72)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.22), value: editor.mode)
        }
        .navigationSubtitle(editor.pageCount == 1 ? "1 page" : "\(editor.pageCount) pages")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $editor.mode) {
                    ForEach(EditorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                .help("Read (⌘1) · Markup (⌘2) · Pages (⌘3)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
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
                    Label("Display", systemImage: "textformat.size")
                }
                .help("Page layout and reading theme")
                if let url = editor.fileURL {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                        .help("Share")
                }
            }
        }
        .searchable(text: $editor.searchText, placement: .toolbar, prompt: "Search")
        .onSubmit(of: .search) { editor.search() }
        .onChange(of: editor.searchText) { _, text in if text.isEmpty { editor.clearSearch() } }
        .onChange(of: editor.mode) { old, mode in
            if mode == .pages { columnsBeforePages = columns; withAnimation { columns = .detailOnly } }
            else if old == .pages { withAnimation { columns = columnsBeforePages } }
        }
        .focusedSceneValue(\.editor, editor)
        .onAppear {
            editor.undoManager = undoManager
            WelcomeWindowController.shared.close()
        }
        .onChange(of: undoManager) { _, manager in editor.undoManager = manager }
        .sheet(isPresented: $editor.showSignaturePad) { SignaturePad(editor: editor) }
        .sheet(isPresented: $editor.showProperties) { PropertiesView(editor: editor) }
        .sheet(isPresented: $editor.showPasswordSheet) { PasswordSheet(editor: editor) }
        .sheet(isPresented: $editor.needsPassword) { UnlockView(editor: editor) }
    }
}

struct SheetHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct UnlockView: View {
    @ObservedObject var editor: EditorController
    @State private var password = ""
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "lock.doc", title: "Password required", subtitle: "Enter the password to open this document.")
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(unlock)
            if failed { Label("Incorrect password", systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Close Document") { editor.pdfView?.window?.performClose(nil) }
                Button("Unlock", action: unlock).keyboardShortcut(.defaultAction).disabled(password.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 380)
        .interactiveDismissDisabled()
    }

    private func unlock() {
        failed = !editor.unlock(with: password)
        if !failed { dismiss() }
    }
}

struct PasswordSheet: View {
    @ObservedObject var editor: EditorController
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""

    private var mismatch: Bool { !confirm.isEmpty && confirm != password }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "lock.shield", title: "Protect with a password",
                        subtitle: "Saves an encrypted copy. Anyone opening it will need this password.")
            VStack(spacing: 8) {
                SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
                SecureField("Confirm password", text: $confirm).textFieldStyle(.roundedBorder)
            }
            if mismatch { Label("Passwords don’t match", systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Copy…") {
                    dismiss()
                    DispatchQueue.main.async { Exporter.passwordProtected(editor, password: password) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty || confirm != password)
            }
        }
        .padding(22)
        .frame(width: 400)
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
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "info.circle", title: "Document Properties", subtitle: editor.title)
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    TextField("Subject", text: $subject)
                    TextField("Keywords", text: $keywords, prompt: Text("Comma separated"))
                }
                Section {
                    LabeledContent("Pages", value: "\(editor.pageCount)")
                    LabeledContent("PDF version", value: "\(editor.document.majorVersion).\(editor.document.minorVersion)")
                    LabeledContent("Encrypted", value: editor.document.isEncrypted ? "Yes" : "No")
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
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
        .padding(22)
        .frame(width: 460, height: 470)
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
    private let size = CGSize(width: 480, height: 200)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "signature", title: "Your signature",
                        subtitle: "Draw with your trackpad or mouse. It is saved on this Mac only.")
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                VStack(spacing: 4) {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "xmark").font(.caption).foregroundStyle(.gray)
                        Rectangle().fill(.gray.opacity(0.4)).frame(height: 1)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
                }
                if strokes.isEmpty {
                    Text("Sign here").font(.title3).foregroundStyle(.gray.opacity(0.6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Canvas { context, _ in
                    for stroke in strokes where !stroke.isEmpty {
                        var path = Path()
                        path.addLines(stroke)
                        context.stroke(path, with: .color(Color(white: 0.1)),
                                       style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                    }
                }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if value.translation == .zero { strokes.append([value.location]) }
                        else if !strokes.isEmpty { strokes[strokes.count - 1].append(value.location) }
                    })
            }
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light)
            HStack {
                Button("Clear") { strokes = [] }.disabled(strokes.isEmpty)
                if SignatureStore.load() != nil {
                    Button("Delete Saved", role: .destructive) { SignatureStore.save(nil); dismiss() }
                }
                Spacer()
                Button("Cancel") {
                    if SignatureStore.load() == nil, editor.tool == .signature { editor.tool = .select }
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save Signature") {
                    SignatureStore.save(Signature(viewStrokes: strokes, viewHeight: size.height))
                    editor.tool = .signature
                    editor.showToast("Signature saved — click a page to place it")
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(strokes.isEmpty)
            }
        }
        .padding(22)
    }
}
