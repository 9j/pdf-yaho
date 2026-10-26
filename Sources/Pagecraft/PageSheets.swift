import PDFKit
import PagecraftCore
import SwiftUI

/// Which pages a page-level operation applies to.
private struct PageScopePicker: View {
    @ObservedObject var editor: EditorController
    @Binding var allPages: Bool

    var body: some View {
        Picker("Apply to", selection: $allPages) {
            Text("All pages (\(editor.pageCount))").tag(true)
            Text(editor.selectedPages.count > 1 ? "Selected pages (\(editor.selectedPages.count))" : "Current page (\(editor.targetPageIndices.first.map { $0 + 1 } ?? 1))").tag(false)
        }
    }
}

struct PageSizeSheet: View {
    @ObservedObject var editor: EditorController
    @State private var paper: PageOps.PaperSize = .a4
    @State private var custom = false
    @State private var widthMM: Double = 210
    @State private var heightMM: Double = 297
    @State private var orientation: EditorController.Orientation = .match
    @State private var scaleToFit = true
    @State private var allPages = true

    private var size: CGSize {
        custom ? CGSize(width: widthMM / 25.4 * 72, height: heightMM / 25.4 * 72) : paper.size
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "arrow.up.left.and.arrow.down.right", title: "Page Size",
                        subtitle: "Change the paper size. Text stays selectable and annotations move with the content.")
            Form {
                Picker("Size", selection: Binding(get: { custom ? "custom" : paper.id }, set: { id in
                    if id == "custom" { custom = true } else if let p = PageOps.PaperSize.all.first(where: { $0.id == id }) { custom = false; paper = p }
                })) {
                    ForEach(PageOps.PaperSize.all) { p in
                        Text("\(p.name) — \(Int((p.size.width / 72 * 25.4).rounded())) × \(Int((p.size.height / 72 * 25.4).rounded())) mm").tag(p.id)
                    }
                    Text("Custom").tag("custom")
                }
                if custom {
                    HStack {
                        TextField("Width", value: $widthMM, format: .number).frame(width: 70)
                        Text("×")
                        TextField("Height", value: $heightMM, format: .number).frame(width: 70)
                        Text("mm").foregroundStyle(.secondary)
                    }
                }
                Picker("Orientation", selection: $orientation) {
                    ForEach(EditorController.Orientation.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Scale content to fit", isOn: $scaleToFit)
                PageScopePicker(editor: editor, allPages: $allPages)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: custom ? 250 : 210)
            SheetButtons(confirm: "Apply") {
                editor.resizePages(allPages ? Array(0..<editor.pageCount) : editor.targetPageIndices,
                                   to: size, orientation: orientation, scaleToFit: scaleToFit)
            }
        }
        .padding(22)
        .frame(width: 480)
    }
}

struct SplitSheet: View {
    @ObservedObject var editor: EditorController
    @State private var mode = 0
    @State private var every = 1
    @State private var ranges = ""

    private var splitMode: PageOps.SplitMode? {
        switch mode {
        case 0: .everyPages(every)
        case 1: .oddEven
        default: PageOps.parseRanges(ranges, pageCount: editor.pageCount).map { .ranges($0) }
        }
    }

    private var preview: String {
        guard let splitMode else { return "Type ranges like 1-3, 5, 8-\(editor.pageCount)" }
        let parts = PageOps.split(editor.document, mode: splitMode)
        return "Creates \(parts.count) \(parts.count == 1 ? "file" : "files")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "rectangle.split.3x1", title: "Split Document", subtitle: "Saves each part as a separate PDF in a folder you choose.")
            VStack(spacing: 6) {
                OptionRow(title: "Every \(every) \(every == 1 ? "page" : "pages")", detail: "Fixed-size parts", selected: mode == 0) { mode = 0 }
                if mode == 0 {
                    Stepper("Pages per file: \(every)", value: $every, in: 1...max(1, editor.pageCount)).padding(.leading, 34)
                }
                OptionRow(title: "Odd and even pages", detail: "Two files, for duplex scanning", selected: mode == 1) { mode = 1 }
                OptionRow(title: "Custom ranges", detail: "One file per range", selected: mode == 2) { mode = 2 }
                if mode == 2 {
                    TextField("1-3, 5, 8-\(editor.pageCount)", text: $ranges).textFieldStyle(.roundedBorder).padding(.leading, 34)
                }
            }
            Text(preview).font(.callout).foregroundStyle(splitMode == nil ? .red : .secondary)
            SheetButtons(confirm: "Split…", disabled: splitMode == nil) {
                if let splitMode { Exporter.split(editor, mode: splitMode) }
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}

enum HeaderFooterPreset: String, Identifiable {
    case pageNumbers, bates, custom
    var id: String { rawValue }
}

struct HeaderFooterSheet: View {
    @ObservedObject var editor: EditorController
    let preset: HeaderFooterPreset
    @State private var stamp = PageOps.Stamp()
    @State private var allPages = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: preset == .bates ? "number.square" : "textformat.123",
                        title: preset == .bates ? "Bates Numbering" : preset == .pageNumbers ? "Page Numbers" : "Header & Footer",
                        subtitle: "Added as removable text on every page. Use Save As Flattened to make it permanent.")
            Form {
                TextField("Text", text: $stamp.template)
                HStack(spacing: 6) {
                    Text("Insert").foregroundStyle(.secondary).font(.caption)
                    ForEach(["{page}", "{total}", "{bates}", "{date}", "{file}"], id: \.self) { token in
                        Button(token.trimmingCharacters(in: CharacterSet(charactersIn: "{}")).capitalized) { stamp.template += token }
                            .controlSize(.small)
                    }
                }
                Picker("Position", selection: $stamp.position) {
                    ForEach(PageOps.Position.allCases) { Text($0.rawValue).tag($0) }
                }
                Stepper("Start numbering at \(stamp.firstNumber)", value: $stamp.firstNumber, in: 1...99_999)
                if stamp.template.contains("{bates}") {
                    HStack {
                        TextField("Prefix", text: $stamp.batesPrefix)
                        TextField("Suffix", text: $stamp.batesSuffix)
                    }
                    Stepper("Digits: \(stamp.batesDigits)", value: $stamp.batesDigits, in: 1...12)
                }
                Stepper("Font size: \(Int(stamp.fontSize)) pt", value: $stamp.fontSize, in: 6...36)
                Stepper("Margin: \(Int(stamp.margin)) pt", value: $stamp.margin, in: 6...144, step: 6)
                PageScopePicker(editor: editor, allPages: $allPages)
                LabeledContent("Preview") {
                    Text(stamp.text(pageIndex: 0, total: editor.pageCount, fileName: editor.title)).monospacedDigit()
                }
            }
            .formStyle(.grouped)
            .frame(height: stamp.template.contains("{bates}") ? 470 : 390)
            SheetButtons(confirm: "Add", disabled: stamp.template.isEmpty) {
                editor.addStamp(stamp, pages: allPages ? Array(0..<editor.pageCount) : editor.targetPageIndices)
            }
        }
        .padding(22)
        .frame(width: 500)
        .onAppear {
            switch preset {
            case .pageNumbers: stamp = PageOps.Stamp(template: "{page} of {total}", position: .bottomCenter)
            case .bates: stamp = PageOps.Stamp(template: "{bates}", position: .bottomRight, batesPrefix: "DOC")
            case .custom: stamp = PageOps.Stamp(template: "{file} · {date}", position: .topRight)
            }
        }
    }
}

/// Edits page label ranges: from page N on, number pages in a style with a prefix (e.g. i, ii … then 1, 2 …).
struct PageLabelsSheet: View {
    @ObservedObject var editor: EditorController
    @State private var ranges: [Row] = []
    @Environment(\.dismiss) private var dismiss

    struct Row: Identifiable, Equatable {
        let id = UUID()
        var range: PageLabelRange
    }

    private var sorted: [PageLabelRange] { ranges.map(\.range).sorted { $0.startPage < $1.startPage } }
    private var duplicateStart: Bool { Set(ranges.map(\.range.startPage)).count != ranges.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "textformat.123", title: "Page Labels",
                        subtitle: "Number pages the way they are printed, such as i, ii for the front matter and 1, 2 from chapter one.")
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("From page").frame(width: 80, alignment: .leading)
                    Text("Style").frame(width: 130, alignment: .leading)
                    Text("Prefix").frame(width: 90, alignment: .leading)
                    Text("Start at").frame(width: 60, alignment: .leading)
                    Spacer()
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                Divider()
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach($ranges) { $row in rangeRow($row) }
                        if ranges.isEmpty {
                            Text("No labels — pages show their numbers.").foregroundStyle(.secondary).padding(.vertical, 16)
                        }
                    }
                    .padding(10)
                }
                .frame(height: 170)
                Divider()
                HStack {
                    Button { addRange() } label: { Label("Add Range", systemImage: "plus") }
                        .buttonStyle(.borderless)
                        .disabled(ranges.count >= editor.pageCount)
                    Spacer()
                    if duplicateStart {
                        Label("Two ranges start on the same page", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))

            VStack(alignment: .leading, spacing: 6) {
                Text("Preview").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(0..<min(editor.pageCount, 40), id: \.self) { index in
                            VStack(spacing: 2) {
                                Text(PageLabels.label(forPage: index, in: sorted) ?? "\(index + 1)")
                                    .font(.callout.weight(.medium)).lineLimit(1)
                                Text("\(index + 1)").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                        }
                    }
                }
            }

            HStack {
                Button("Remove All", role: .destructive) { ranges = [] }
                    .disabled(ranges.isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") {
                    let result = sorted
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { editor.setPageLabels(result) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(duplicateStart)
            }
        }
        .padding(22)
        .frame(width: 560)
        .onAppear {
            ranges = editor.pageLabels.map { Row(range: $0) }
            if ranges.isEmpty { ranges = [Row(range: PageLabelRange(startPage: 0, style: .decimal))] }
        }
    }

    private func rangeRow(_ row: Binding<Row>) -> some View {
        HStack(spacing: 10) {
            TextField("", value: Binding(get: { row.wrappedValue.range.startPage + 1 },
                                         set: { row.wrappedValue.range.startPage = min(max($0, 1), editor.pageCount) - 1 }),
                      format: .number)
                .frame(width: 50)
                .accessibilityLabel("From page")
            Text("–\(endPage(of: row.wrappedValue.range))").foregroundStyle(.secondary).monospacedDigit().frame(width: 22, alignment: .leading)
            Picker("Style", selection: row.range.style) {
                ForEach(PageLabelRange.Style.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden().frame(width: 130)
            TextField("None", text: row.range.prefix).frame(width: 90).accessibilityLabel("Prefix")
            TextField("", value: Binding(get: { row.wrappedValue.range.firstNumber },
                                         set: { row.wrappedValue.range.firstNumber = max(1, $0) }),
                      format: .number)
                .frame(width: 60)
                .disabled(row.wrappedValue.range.style == .none)
                .accessibilityLabel("Start at")
            Spacer()
            Button { ranges.removeAll { $0.id == row.wrappedValue.id } } label: { Image(systemName: "minus.circle.fill") }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Remove this range")
        }
        .textFieldStyle(.roundedBorder)
    }

    /// The last page (1-based) a range covers before the next one starts.
    private func endPage(of range: PageLabelRange) -> Int {
        let next = sorted.map(\.startPage).filter { $0 > range.startPage }.min()
        return next ?? editor.pageCount
    }

    /// Adds a range at the selected page, or after the last range.
    private func addRange() {
        let taken = Set(ranges.map(\.range.startPage))
        let preferred = editor.targetPageIndices.first.flatMap { taken.contains($0) ? nil : $0 }
        let start = preferred ?? (0..<editor.pageCount).first { !taken.contains($0) && $0 > (taken.max() ?? -1) }
            ?? (0..<editor.pageCount).first { !taken.contains($0) } ?? 0
        ranges.append(Row(range: PageLabelRange(startPage: start, style: .decimal)))
    }
}
