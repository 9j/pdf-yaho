import PDFKit
import PagecraftCore
import SwiftUI

struct SheetButtons: View {
    let confirm: String
    var disabled = false
    let action: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button(confirm) {
                dismiss()
                // Let the sheet finish closing before the document changes underneath it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: action)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(disabled)
        }
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
            SheetHeader(symbol: editor.isPasswordProtected ? "lock.fill" : "lock.shield",
                        title: editor.isPasswordProtected ? "Change Password" : "Set Password",
                        subtitle: "Anyone opening this document will need the password. It is encrypted when you save.")
            VStack(spacing: 8) {
                SecureField(editor.isPasswordProtected ? "New password" : "Password", text: $password).textFieldStyle(.roundedBorder)
                SecureField("Verify", text: $confirm).textFieldStyle(.roundedBorder)
            }
            if mismatch { Label("Passwords do not match", systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.callout) }
            HStack {
                if editor.isPasswordProtected {
                    Button("Remove Password", role: .destructive) {
                        editor.setPassword(nil)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(editor.isPasswordProtected ? "Change" : "Set Password") {
                    editor.setPassword(password)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty || confirm != password)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}

struct ReduceSizeSheet: View {
    @ObservedObject var editor: EditorController
    @State private var compression: PDFOps.Compression = .medium

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "arrow.down.right.and.arrow.up.left", title: "Reduce File Size",
                        subtitle: "Current size: \(editor.currentFileSize.map { ByteCountFormatter().string(fromByteCount: Int64($0)) } ?? "unknown"). Saves a smaller copy; the original is not changed.")
            VStack(spacing: 6) {
                ForEach(PDFOps.Compression.allCases) { option in
                    OptionRow(title: option.rawValue, detail: option.detail, selected: compression == option) { compression = option }
                }
            }
            SheetButtons(confirm: "Save Copy…") { Exporter.reduceSize(editor, compression: compression) }
        }
        .padding(22)
        .frame(width: 440)
    }
}

struct ExportImagesSheet: View {
    @ObservedObject var editor: EditorController
    @State private var format: PDFOps.ImageFormat = .png
    @State private var dpi: CGFloat = 150
    @State private var range = 0

    private var indices: [Int] {
        switch range {
        case 1: editor.targetPageIndices
        case 2: [editor.currentPageIndex]
        default: Array(0..<editor.pageCount)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "photo.on.rectangle", title: "Export as Images", subtitle: "Each page becomes one image file.")
            Form {
                Picker("Format", selection: $format) {
                    ForEach(PDFOps.ImageFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Resolution", selection: $dpi) {
                    Text("72 dpi (screen)").tag(CGFloat(72))
                    Text("150 dpi").tag(CGFloat(150))
                    Text("300 dpi (print)").tag(CGFloat(300))
                    Text("600 dpi").tag(CGFloat(600))
                }
                Picker("Pages", selection: $range) {
                    Text("All pages (\(editor.pageCount))").tag(0)
                    if editor.selectedPages.count > 1 { Text("Selected pages (\(editor.selectedPages.count))").tag(1) }
                    Text("Current page").tag(2)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 170)
            SheetButtons(confirm: "Export…") { Exporter.images(editor, format: format, dpi: dpi, indices: indices) }
        }
        .padding(22)
        .frame(width: 440)
    }
}

struct OptionRow: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct FindRedactSheet: View {
    @ObservedObject var editor: EditorController
    @Environment(\.dismiss) private var dismiss
    @State private var terms = ""
    @State private var matchCase = false
    @State private var wholeWords = true
    @State private var style: Annotations.RedactionStyle = .blackout

    private var queries: [String] {
        terms.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var matchCount: Int {
        queries.reduce(0) { $0 + Search.find($1, in: editor.document, matchCase: matchCase, wholeWords: wholeWords).count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "eye.slash", title: "Find and Redact",
                        subtitle: "Marks every match for redaction. Review the marks, then choose Apply Redactions to remove the text for good.")
            VStack(alignment: .leading, spacing: 6) {
                Text("Words or phrases, one per line").font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $terms)
                    .font(.body)
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            }
            HStack(spacing: 18) {
                Toggle("Match case", isOn: $matchCase)
                Toggle("Whole words", isOn: $wholeWords)
            }
            Picker("Mark style", selection: $style) {
                ForEach(Annotations.RedactionStyle.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(queries.isEmpty ? " " : "\(matchCount) \(matchCount == 1 ? "match" : "matches") found")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Mark \(matchCount) for Redaction") {
                    editor.markForRedaction(queries, matchCase: matchCase, wholeWords: wholeWords, style: style)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(matchCount == 0)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}
