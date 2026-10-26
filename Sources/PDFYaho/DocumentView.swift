import PDFKit
import PDFYahoCore
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
                .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 360)
        } detail: {
            detail
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
                ToolsetSwitcher(editor: editor)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                DisplaySettingsButton(editor: editor)
                Menu {
                    Button("Share Document…") { Exporter.share(editor, flattened: false) }
                    Button("Share Flattened…") { Exporter.share(editor, flattened: true) }
                    Divider()
                    Button("Mail Document") { Exporter.mail(editor, flattened: false) }
                    Button("Mail Flattened") { Exporter.mail(editor, flattened: true) }
                    Divider()
                    Button("Save As Flattened…") { Exporter.flattened(editor) }
                    Button("Export as Word…") { Exporter.rich(editor, .word) }
                    Button("Export as Images…") { editor.showExportImages = true }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share, mail or export this document")
            }
        }
        .searchable(text: $editor.searchText, placement: .toolbar, prompt: "Search")
        .searchSuggestions {
            if editor.searchText.isEmpty {
                ForEach(editor.searchHistory, id: \.self) { query in
                    Label(query, systemImage: "clock.arrow.circlepath").searchCompletion(query)
                }
            }
        }
        .onSubmit(of: .search) { editor.search() }
        // Live search: run shortly after typing stops.
        .task(id: editor.searchText) {
            guard editor.searchText.trimmingCharacters(in: .whitespaces).count >= 2 else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            editor.search(remember: false)
        }
        .onChange(of: editor.revealSidebar) { _, reveal in
            if reveal, editor.mode != .pages, columns == .detailOnly { withAnimation { columns = .all } }
            editor.revealSidebar = false
        }
        .onChange(of: editor.searchText) { _, text in if text.isEmpty { editor.clearSearch() } }
        .onChange(of: editor.mode) { old, mode in
            if mode == .pages { columnsBeforePages = columns; withAnimation { columns = .detailOnly } }
            else if old == .pages { withAnimation { columns = columnsBeforePages } }
        }
        .focusedSceneValue(\.editor, editor)
        .onAppear {
            editor.undoManager = undoManager
            WelcomeWindowController.shared.close()
            if !Preferences.showSidebar { columns = .detailOnly }
            #if DEBUG
            if ProcessInfo.processInfo.environment["PDFYAHO_QA_NOSIDEBAR"] != nil { columns = .detailOnly }
            #endif
            // The window is attached a moment after the view appears.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard let window = editor.pdfView?.window else { return }
                EditorRegistry.register(editor, window: window)
                editor.loadBookmarks()
                window.tabbingIdentifier = "PDFYahoDocuments"
                window.tabbingMode = Preferences.openInTabs ? .preferred : .disallowed
                if let url = editor.fileURL, let action = DocumentLauncher.take(for: url) { editor.perform(action) }
                #if DEBUG
                // Lets automated screenshots start in a given toolset without input events.
                if let raw = ProcessInfo.processInfo.environment["PDFYAHO_QA_MODE"], let mode = EditorMode(rawValue: raw) { editor.mode = mode }
                if ProcessInfo.processInfo.environment["PDFYAHO_QA_SPLIT"] != nil { editor.openSplit() }
                if ProcessInfo.processInfo.environment["PDFYAHO_QA_DEMO"] != nil { editor.placeQADemo() }
                if let raw = ProcessInfo.processInfo.environment["PDFYAHO_QA_SIDEBAR"], let tab = SidebarTab(rawValue: raw) { editor.sidebarTab = tab }
                if let step = ProcessInfo.processInfo.environment["PDFYAHO_QA_CONTENT"] { editor.runContentQA(step) }
                if let sheet = ProcessInfo.processInfo.environment["PDFYAHO_QA_SHEET"] { editor.openSheetQA(sheet) }
                if let steps = ProcessInfo.processInfo.environment["PDFYAHO_QA_STEPS"] { editor.runStepsQA(steps) }
                if let shot = ProcessInfo.processInfo.environment["PDFYAHO_QA_SHOT"] { editor.stageShotQA(shot) }
                #endif
            }
        }
        .onChange(of: undoManager) { _, manager in editor.undoManager = manager }
        .modifier(DocumentSheets(editor: editor))
    }

    /// The document, optionally beside a second document in split view.
    @ViewBuilder private var detail: some View {
        if let split = editor.split {
            if split.vertical {
                VSplitView { splitChildren(split) }
            } else {
                HSplitView { splitChildren(split) }
            }
        } else {
            documentArea
        }
    }

    @ViewBuilder private func splitChildren(_ split: SplitState) -> some View {
        if split.swapped {
            SplitPaneView(editor: editor).frame(minWidth: 280, minHeight: 200)
            documentArea.frame(minWidth: 360, minHeight: 240)
        } else {
            documentArea.frame(minWidth: 360, minHeight: 240)
            SplitPaneView(editor: editor).frame(minWidth: 280, minHeight: 200)
        }
    }

    private var documentArea: some View {
        ZStack {
            PDFKitView(editor: editor)
                .overlay { DocumentOverlays(editor: editor) }
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        if !editor.searchResults.isEmpty {
                            SearchResultsPill(editor: editor)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if let target = editor.backTarget {
                            BackToPagePill(editor: editor, page: target)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.top, 12)
                    .animation(.snappy(duration: 0.2), value: editor.backTarget)
                    .animation(.snappy(duration: 0.2), value: editor.searchResults.isEmpty)
                }
                .overlay(alignment: .bottom) {
                    PageHUD(editor: editor)
                        .padding(.bottom, 16)
                        .opacity(editor.hudVisible ? 1 : 0)
                        .animation(.easeInOut(duration: 0.25), value: editor.hudVisible)
                }
            if editor.mode == .pages {
                PageGridView(editor: editor)
                    .transition(.opacity)
            }
        }
        // The toolset's tools sit in a bar above the page, so they never cover content.
        .safeAreaInset(edge: .top, spacing: 0) {
            if editor.mode.isMarkup || editor.mode == .scan || editor.mode == .edit {
                VStack(spacing: 0) {
                    Group {
                        switch editor.mode {
                        case .scan: ScanBar(editor: editor)
                        case .edit: ContentEditBar(editor: editor)
                        default: ToolsetBar(editor: editor)
                        }
                    }
                    .background(.bar)
                    Divider()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

/// Every sheet a document window can show, plus the blocking progress overlay.
private struct DocumentSheets: ViewModifier {
    @ObservedObject var editor: EditorController

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $editor.showSignaturePad) { SignaturePad(editor: editor) }
            .sheet(isPresented: $editor.showProperties) { PropertiesView(editor: editor) }
            .sheet(isPresented: $editor.showPasswordSheet) { PasswordSheet(editor: editor) }
            .sheet(isPresented: $editor.showReduceSize) { ReduceSizeSheet(editor: editor) }
            .sheet(isPresented: $editor.showExportImages) { ExportImagesSheet(editor: editor) }
            .modifier(MoreSheets(editor: editor))
            .overlay { if let message = editor.busy { BusyOverlay(message: message) } }
    }
}

private struct MoreSheets: ViewModifier {
    @ObservedObject var editor: EditorController

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $editor.showPageSize) { PageSizeSheet(editor: editor) }
            .sheet(isPresented: $editor.showSplit) { SplitSheet(editor: editor) }
            .sheet(isPresented: $editor.showPageLabels) { PageLabelsSheet(editor: editor) }
            .sheet(isPresented: $editor.showLinkSheet) { LinkSheet(editor: editor) }
            .sheet(isPresented: $editor.showFindRedact) { FindRedactSheet(editor: editor) }
            .sheet(isPresented: $editor.showMeasureScale) { MeasureScaleSheet(editor: editor) }
            .sheet(item: $editor.headerFooterPreset) { preset in HeaderFooterSheet(editor: editor, preset: preset) }
            .sheet(isPresented: $editor.needsPassword) { UnlockView(editor: editor) }
    }
}

private struct BusyOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.15)
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(message).font(.callout)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .ignoresSafeArea()
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

struct PropertiesView: View {
    @ObservedObject var editor: EditorController

    private func attribute(_ key: PDFDocumentAttribute) -> Any? { editor.document.documentAttributes?[key] }

    private var pageSize: String {
        guard let page = editor.document.page(at: editor.currentPageIndex) else { return "—" }
        let size = PageOps.displaySize(page)
        let mm = { (points: CGFloat) in Int((points / 72 * 25.4).rounded()) }
        let name = PageOps.PaperSize.all.first { abs($0.size.width - min(size.width, size.height)) < 3 && abs($0.size.height - max(size.width, size.height)) < 3 }?.name
        return "\(mm(size.width)) × \(mm(size.height)) mm" + (name.map { " (\($0))" } ?? "")
    }

    private var counts: (annotations: Int, fields: Int) {
        let all = PDFOps.pages(of: editor.document).flatMap(\.annotations)
        return (all.filter(Annotations.isUserEditable).count, all.filter { $0.type == "Widget" }.count)
    }
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
                Section("File") {
                    LabeledContent("Pages", value: "\(editor.pageCount)")
                    LabeledContent("Page size", value: pageSize)
                    if let size = editor.currentFileSize {
                        LabeledContent("File size", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                    LabeledContent("PDF version", value: "\(editor.document.majorVersion).\(editor.document.minorVersion)")
                    if let created = attribute(.creationDateAttribute) as? Date {
                        LabeledContent("Created", value: created.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let modified = attribute(.modificationDateAttribute) as? Date {
                        LabeledContent("Modified", value: modified.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let creator = attribute(.creatorAttribute) as? String, !creator.isEmpty { LabeledContent("Application", value: creator) }
                    if let producer = attribute(.producerAttribute) as? String, !producer.isEmpty { LabeledContent("PDF producer", value: producer) }
                }
                Section("Content and Security") {
                    LabeledContent("Annotations", value: "\(counts.annotations)")
                    LabeledContent("Form fields", value: "\(counts.fields)")
                    LabeledContent("Password to open", value: editor.isPasswordProtected ? "Yes" : "No")
                    LabeledContent("Encrypted", value: editor.document.isEncrypted ? "Yes" : "No")
                    LabeledContent("Printing", value: editor.document.allowsPrinting ? "Allowed" : "Not allowed")
                    LabeledContent("Copying text", value: editor.document.allowsCopying ? "Allowed" : "Not allowed")
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
        .frame(width: 480, height: 640)
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
