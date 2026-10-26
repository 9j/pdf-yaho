import PDFKit
import PagecraftCore
import SwiftUI

/// Create a signature or initials by drawing, typing, or importing an image.
struct SignaturePad: View {
    @ObservedObject var editor: EditorController
    @Environment(\.dismiss) private var dismiss
    @State private var method = 0
    @State private var strokes: [[CGPoint]] = []
    @State private var typed = ""
    @State private var fontName = SignaturePad.fonts.first ?? "Snell Roundhand"
    @State private var image: NSImage?
    private let size = CGSize(width: 480, height: 200)

    static let fonts = ["Snell Roundhand", "Bradley Hand", "Savoye LET", "Apple Chancery", "Zapfino", "Noteworthy"]
        .filter { NSFont(name: $0, size: 12) != nil }

    private var initials: Bool { editor.signaturePadInitials }

    private var result: SavedSignature? {
        switch method {
        case 0: Signature(viewStrokes: strokes, viewHeight: size.height).map { SavedSignature.drawn($0, initials: initials) }
        case 1: typed.isEmpty ? nil : SavedSignature.typed(typed, font: NSFont(name: fontName, size: 64) ?? .systemFont(ofSize: 64), initials: initials)
        default: image.flatMap { SavedSignature.image($0, initials: initials) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "signature", title: initials ? "New Initials" : "New Signature",
                        subtitle: "Saved on this Mac only. Choose it from the Sign menu, then click where it goes.")
            Picker("Method", selection: $method) {
                Text("Draw").tag(0)
                Text("Type").tag(1)
                Text("Image").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                switch method {
                case 0: drawPad
                case 1: typePad
                default: imagePad
                }
            }
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light)
            HStack {
                if method == 0 { Button("Clear") { strokes = [] }.disabled(strokes.isEmpty) }
                Spacer()
                Button("Cancel") {
                    if editor.signatureLibrary.isEmpty, editor.tool == .signature { editor.tool = .select }
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(initials ? "Save Initials" : "Save Signature") {
                    guard let result else { return }
                    editor.addSignature(result)
                    editor.tool = .signature
                    editor.showToast("Saved — click a page to place it")
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(result == nil)
            }
        }
        .padding(22)
    }

    private var drawPad: some View {
        ZStack(alignment: .bottomLeading) {
            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "xmark").font(.caption).foregroundStyle(.gray)
                    Rectangle().fill(.gray.opacity(0.4)).frame(height: 1)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 44)
            }
            if strokes.isEmpty {
                Text(initials ? "Draw your initials" : "Sign here").font(.title3).foregroundStyle(.gray.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Canvas { context, _ in
                for stroke in strokes where !stroke.isEmpty {
                    var path = Path()
                    path.addLines(stroke)
                    context.stroke(path, with: .color(Color(white: 0.1)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if value.translation == .zero { strokes.append([value.location]) }
                    else if !strokes.isEmpty { strokes[strokes.count - 1].append(value.location) }
                })
        }
    }

    private var typePad: some View {
        VStack(spacing: 14) {
            TextField(initials ? "Your initials" : "Your name", text: $typed)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            Text(typed.isEmpty ? (initials ? "AB" : "Your Name") : typed)
                .font(.custom(fontName, size: 44))
                .foregroundStyle(Color(red: 0.08, green: 0.1, blue: 0.3).opacity(typed.isEmpty ? 0.3 : 1))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: 440)
            Picker("Style", selection: $fontName) {
                ForEach(Self.fonts, id: \.self) { Text($0).font(.custom($0, size: 14)).tag($0) }
            }
            .frame(width: 260)
        }
        .padding()
    }

    private var imagePad: some View {
        VStack(spacing: 12) {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 130)
            } else {
                Image(systemName: "photo.badge.plus").font(.system(size: 36)).foregroundStyle(.gray)
                Text("A scan or photo of your signature on a white or transparent background").font(.callout)
                    .foregroundStyle(.gray).multilineTextAlignment(.center).frame(width: 320)
            }
            Button(image == nil ? "Choose Image…" : "Choose Another…") {
                if let url = Prompt.open([.image], multiple: false, title: "Choose a Signature Image").first {
                    image = NSImage(contentsOf: url)
                }
            }
        }
        .padding()
    }
}

struct LinkSheet: View {
    @ObservedObject var editor: EditorController
    @Environment(\.dismiss) private var dismiss
    @State private var toWeb = true
    @State private var address = "https://"
    @State private var page = 1

    private var url: URL? {
        guard toWeb, let url = URL(string: address.trimmingCharacters(in: .whitespaces)), url.scheme != nil, url.host != nil || url.scheme == "mailto" else { return nil }
        return url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "link", title: "Add Link", subtitle: "Clicking the area opens a web page or jumps to a page.")
            Picker("Link to", selection: $toWeb) {
                Text("Web Page").tag(true)
                Text("Page in This Document").tag(false)
            }
            .pickerStyle(.segmented)
            if toWeb {
                TextField("https://example.com", text: $address).textFieldStyle(.roundedBorder)
            } else {
                Stepper("Page \(page) of \(editor.pageCount)", value: $page, in: 1...max(1, editor.pageCount))
            }
            HStack {
                Spacer()
                Button("Cancel") { editor.pendingLink = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Link") {
                    editor.commitLink(url: toWeb ? url : nil, pageNumber: toWeb ? nil : page)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(toWeb && url == nil)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}

struct SettingsView: View {
    @AppStorage("authorName") private var author = ""

    var body: some View {
        Form {
            TextField("Author name", text: $author, prompt: Text(NSFullUserName()))
            Text("Shown as the author of your highlights, notes and stamps in other PDF apps.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 140)
    }
}
