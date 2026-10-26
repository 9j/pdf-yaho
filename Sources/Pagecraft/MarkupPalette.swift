import PDFKit
import PagecraftCore
import SwiftUI

/// The floating tool bar for the active toolset. Each toolset shows only the tools for its task.
struct ToolsetBar: View {
    @ObservedObject var editor: EditorController
    @State private var showStyle = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content
            content.environment(\.paletteCompact, true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var content: some View {
        HStack(spacing: 2) {
            switch editor.mode {
            case .annotate:
                group([.select])
                divider
                group([.highlight, .underline, .squiggly, .strikeout])
                divider
                group([.text, .note, .callout])
                stampButton
                group([.image, .link])
                divider
                group([.eraser])
            case .draw:
                group([.select])
                divider
                group([.pen, .marker])
                divider
                group([.rectangle, .oval, .line, .arrow])
                shapeMenu
                divider
                group([.eraser])
            case .fillSign:
                group([.select])
                divider
                group([.text, .checkmark, .cross, .date])
                divider
                signButton
                stampButton
                divider
                formButton
                divider
                group([.eraser])
            case .measure:
                group([.select])
                divider
                group([.measureDistance, .measurePerimeter, .measureArea])
                divider
                scaleButton
                group([.eraser])
            case .redact:
                group([.select, .redact])
                divider
                redactStyleButton
                PaletteButton(symbol: "text.magnifyingglass", label: "Find", help: "Find and Redact… (⇧⌘F)", selected: false) {
                    editor.showFindRedact = true
                }
                divider
                applyRedactionsButton
            default:
                EmptyView()
            }
            if editor.mode != .redact {
                divider
                styleButton
            }
            divider
            PaletteButton(symbol: "arrow.uturn.backward", label: "Undo", help: "Undo (⌘Z)", selected: false) {
                editor.undoManager?.undo()
            }
            .disabled(!editor.canUndo)
            PaletteButton(symbol: "arrow.uturn.forward", label: "Redo", help: "Redo (⇧⌘Z)", selected: false) {
                editor.undoManager?.redo()
            }
            .disabled(!editor.canRedo)
        }
        .fixedSize()
    }

    private var divider: some View {
        Divider().frame(height: 26).padding(.horizontal, 3)
    }

    /// Ovals, arrows' variants, polygons and clouds behind one button showing the last one used.
    private var shapeMenu: some View {
        let extra: [Tool] = [.doubleArrow, .polygon, .polyline, .cloud, .cloudPolygon]
        let active = extra.contains(editor.tool)
        let shown = active ? editor.tool : (extra.contains(editor.lastShape) ? editor.lastShape : .polygon)
        return Menu {
            ForEach(extra) { tool in
                Button { editor.tool = tool } label: { Label(tool.label, systemImage: tool.symbol) }
            }
        } label: {
            PaletteLabel(symbol: shown.symbol, label: active ? shown.label : "More", selected: active, tint: tint(shown), showsChevron: true)
        } primaryAction: {
            editor.tool = shown
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More shapes: double arrow, polygon, polyline, clouds")
    }

    private func tint(_ tool: Tool) -> Color? {
        tool.isStyled ? Color(nsColor: editor.style(for: tool).color) : nil
    }

    private func group(_ tools: [Tool]) -> some View {
        ForEach(tools) { tool in
            PaletteButton(symbol: tool.symbol, label: tool.label, help: tool.help, selected: editor.tool == tool, tint: tint(tool)) {
                editor.tool = tool
            }
        }
    }

    private var signButton: some View {
        Menu {
            Section("Signatures") {
                ForEach(editor.signatureLibrary) { signature in
                    Button {
                        editor.activeSignatureID = signature.id
                        editor.tool = .signature
                    } label: {
                        Label(signature.isInitials ? "Initials" : "Signature",
                              systemImage: editor.activeSignature?.id == signature.id ? "checkmark" : "signature")
                    }
                }
                Button("New Signature…") { editor.signaturePadInitials = false; editor.showSignaturePad = true }
                Button("New Initials…") { editor.signaturePadInitials = true; editor.showSignaturePad = true }
            }
            if !editor.signatureLibrary.isEmpty {
                Menu("Delete") {
                    ForEach(editor.signatureLibrary) { signature in
                        Button(signature.isInitials ? "Initials" : "Signature") { editor.deleteSignature(signature) }
                    }
                }
            }
        } label: {
            PaletteLabel(symbol: Tool.signature.symbol, label: "Sign", selected: editor.tool == .signature, showsChevron: true)
        } primaryAction: {
            editor.tool = .signature
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(editor.signatureLibrary.isEmpty ? "Create a signature" : "Place your signature (G)")
    }

    private var formButton: some View {
        let active = Tool.formFields.contains(editor.tool)
        let shown = active ? editor.tool : .formText
        return Menu {
            ForEach(Tool.formFields) { tool in
                Button { editor.tool = tool } label: { Label(tool.label, systemImage: tool.symbol) }
            }
            Divider()
            Button("Clear Form") { editor.resetForm() }
        } label: {
            PaletteLabel(symbol: shown.symbol, label: "Fields", selected: active, showsChevron: true)
        } primaryAction: {
            editor.tool = shown
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add form fields: drag on the page")
    }

    private var stampButton: some View {
        Menu {
            ForEach(StampPreset.all) { preset in
                Button {
                    editor.stampChoice = .preset(preset)
                    editor.tool = .stamp
                } label: {
                    Label(preset.title, systemImage: editor.stampChoice == .preset(preset) ? "checkmark" : "seal")
                }
            }
            Divider()
            Button("Custom Text…") { editor.chooseCustomStamp() }
            Button("Image from File…") { editor.chooseImageStamp() }
        } label: {
            PaletteLabel(symbol: Tool.stamp.symbol, label: "Stamp", selected: editor.tool == .stamp, showsChevron: true)
        } primaryAction: {
            editor.tool = .stamp
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Tool.stamp.help)
    }

    private var scaleButton: some View {
        PaletteButton(symbol: "ruler", label: "Scale",
                      help: "Measurement scale and units (\(editor.measureScale.unit.rawValue))", selected: false) {
            editor.showMeasureScale = true
        }
    }

    private var redactStyleButton: some View {
        Menu {
            Picker("Mark Style", selection: $editor.redactionStyle) {
                ForEach(Annotations.RedactionStyle.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            PaletteLabel(symbol: editor.redactionStyle == .blackout ? "square.fill" : "square", label: "Mark Style",
                         selected: false, showsChevron: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Black box or white-out")
    }

    private var applyRedactionsButton: some View {
        let count = editor.redactionCount
        return Button { editor.applyRedactions() } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal")
                Text(count == 0 ? "Apply" : "Apply \(count)")
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(count == 0 ? Color.secondary.opacity(0.2) : Color.red))
            .foregroundStyle(count == 0 ? Color.secondary : Color.white)
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .padding(.horizontal, 4)
        .help("Permanently remove everything under the marks")
    }

    private var styleButton: some View {
        Button { showStyle.toggle() } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle().fill(Color(nsColor: editor.activeColor)).frame(width: 18, height: 18)
                    Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1).frame(width: 18, height: 18)
                }
                .frame(height: 20)
                Text("Style").font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 50, height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Colour, size and line style")
        .popover(isPresented: $showStyle, arrowEdge: .bottom) {
            StylePopover(editor: editor)
        }
        .disabled(!(editor.tool.isStyled || editor.selected != nil))
    }
}

/// Actions for scanned documents: text recognition and page clean-up.
struct ScanBar: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        HStack(spacing: 2) {
            PaletteButton(symbol: "text.viewfinder", label: "OCR", help: "Recognize text so scans become searchable", selected: false) {
                editor.recognizeText()
            }
            divider
            Menu {
                ForEach(EnhanceMode.allCases) { mode in
                    Button(mode.rawValue) { editor.enhancePages(mode) }
                }
                Divider()
                Button("All Pages: Black & White") { editor.enhancePages(.blackAndWhite, Array(0..<editor.pageCount)) }
                Button("All Pages: Color") { editor.enhancePages(.color, Array(0..<editor.pageCount)) }
            } label: {
                PaletteLabel(symbol: "wand.and.stars", label: "Enhance", selected: false, showsChevron: true)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Clean up scanned pages: whiter paper, crisper text")
            PaletteButton(symbol: "rectangle.dashed", label: "Margins", help: "Clear margins of the current or selected pages", selected: false) {
                editor.autoCrop()
            }
            PaletteButton(symbol: "crop", label: "Crop", help: "Crop pages (C)", selected: editor.tool == .crop) {
                editor.beginCrop()
            }
            PaletteButton(symbol: "rectangle.portrait.arrowtriangle.2.outward", label: "Size", help: "Change page size", selected: false) {
                editor.showPageSize = true
            }
            PaletteButton(symbol: "rectangle.split.2x1", label: "Split", help: "Split two-page scans (book spreads) into single pages", selected: false) {
                editor.splitSpreads()
            }
            divider
            PaletteButton(symbol: "rotate.left", label: "Left", help: "Rotate left (⌘L)", selected: false) { editor.rotate(-90) }
            PaletteButton(symbol: "rotate.right", label: "Right", help: "Rotate right (⌘R)", selected: false) { editor.rotate(90) }
            divider
            PaletteButton(symbol: "arrow.uturn.backward", label: "Undo", help: "Undo (⌘Z)", selected: false) {
                editor.undoManager?.undo()
            }
            .disabled(!editor.canUndo)
        }
        .fixedSize()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var divider: some View {
        Divider().frame(height: 30).padding(.horizontal, 3)
    }
}

struct PaletteButton: View {
    let symbol: String
    let label: String
    let help: String
    let selected: Bool
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PaletteLabel(symbol: symbol, label: label, selected: selected, tint: tint)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

extension EnvironmentValues {
    /// Icon-only tool buttons when the bar does not fit.
    @Entry var paletteCompact = false
}

struct PaletteLabel: View {
    let symbol: String
    let label: String
    let selected: Bool
    var tint: Color?
    var showsChevron = false
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.paletteCompact) private var compact

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .bottomTrailing) {
                HStack(spacing: 1) {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                        .frame(height: 20)
                    if compact, showsChevron { Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold)) }
                }
                if let tint, selected {
                    Capsule().fill(tint).frame(width: 10, height: 3).offset(x: 4, y: 4)
                }
            }
            if !compact {
                HStack(spacing: 1) {
                    Text(label).font(.system(size: 10)).lineLimit(1).fixedSize()
                    if showsChevron { Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold)) }
                }
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
        }
        .foregroundStyle(selected ? Color.accentColor : .primary)
        .padding(.horizontal, compact ? 4 : 6)
        .frame(minWidth: compact ? 30 : 50)
        .frame(height: compact ? 30 : 42)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.14) : hovering ? Color.primary.opacity(0.06) : .clear)
        }
        .opacity(isEnabled ? 1 : 0.35)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Colour, size, opacity, fill and line style. Applies to the selection if there is one,
/// otherwise to the active tool's defaults.
struct StylePopover: View {
    @ObservedObject var editor: EditorController
    private let columns = Array(repeating: GridItem(.fixed(26), spacing: 8), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editor.selected.map { Annotations.displayName($0.annotation) } ?? editor.tool.label)
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Palette.swatches, id: \.self) { swatch in
                    Swatch(color: swatch, selected: Palette.same(swatch, editor.activeColor)) { editor.setColor(swatch) }
                }
            }
            HStack {
                Text("Custom").foregroundStyle(.secondary)
                Spacer()
                ColorPicker("Custom", selection: Binding(
                    get: { Color(nsColor: editor.activeColor) },
                    set: { editor.setColor(NSColor($0)) }), supportsOpacity: false)
                    .labelsHidden()
            }
            if editor.textApplies {
                Divider()
                TextFormatControls(editor: editor)
            }
            if editor.tool == .date, editor.selected == nil {
                DateFormatPicker()
            }
            if editor.widthApplies {
                Divider()
                SliderRow(title: editor.widthIsFontSize ? "Font size" : "Thickness", value: editor.activeWidth,
                          range: editor.widthIsFontSize ? 8...48 : 1...24, format: { "\(Int($0.rounded())) pt" }) { editor.setWidth($0.rounded()) }
            }
            if editor.opacityApplies {
                SliderRow(title: "Opacity", value: editor.activeOpacity, range: 0.1...1, format: { "\(Int(($0 * 100).rounded()))%" }) {
                    editor.setOpacity(($0 * 20).rounded() / 20)
                }
            }
            if editor.dashApplies {
                Picker("Line style", selection: Binding(get: { editor.activeDash }, set: { editor.setDash($0) })) {
                    ForEach(Annotations.LineStyle.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            if editor.endingsApply {
                HStack {
                    Picker("Start", selection: Binding(get: { editor.activeEndings.start.rawValue }, set: { editor.setLineEndings(start: PDFLineStyle(rawValue: $0)) })) {
                        ForEach(Annotations.supportedLineEndings, id: \.style.rawValue) { Label($0.displayName, systemImage: $0.symbolName).tag($0.style.rawValue) }
                    }
                    Picker("End", selection: Binding(get: { editor.activeEndings.end.rawValue }, set: { editor.setLineEndings(end: PDFLineStyle(rawValue: $0)) })) {
                        ForEach(Annotations.supportedLineEndings, id: \.style.rawValue) { Label($0.displayName, systemImage: $0.symbolName).tag($0.style.rawValue) }
                    }
                }
            }
            if editor.fillApplies {
                VStack(alignment: .leading, spacing: 6) {
                    Text(editor.textApplies ? "Background" : "Fill").foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Button { editor.setFill(nil) } label: {
                            Image(systemName: "nosign").frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(editor.activeFill == nil ? Color.accentColor : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .help("No fill")
                        ForEach(Array(Palette.swatches.prefix(9)), id: \.self) { swatch in
                            Swatch(color: swatch, selected: editor.activeFill.map { Palette.same($0, swatch) } ?? false, size: 22) {
                                editor.setFill(swatch.withAlphaComponent(0.35))
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 270)
    }
}

private struct DateFormatPicker: View {
    @AppStorage("dateStampFormat") private var format = DateStampFormat.numeric.rawValue

    var body: some View {
        Picker("Date format", selection: $format) {
            ForEach(DateStampFormat.allCases) { Text($0.string(from: Date())).tag($0.rawValue) }
        }
    }
}

/// Font family, bold/italic and alignment for text boxes.
private struct TextFormatControls: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Font", selection: Binding(get: { editor.activeFontFamily ?? "" },
                                              set: { editor.setTextFormat(family: .some($0.isEmpty ? nil : $0)) })) {
                ForEach(TextFonts.families, id: \.self) { family in
                    Text(family ?? "System").font(.custom(family ?? NSFont.systemFont(ofSize: 13).fontName, size: 13)).tag(family ?? "")
                }
            }
            HStack(spacing: 8) {
                Toggle(isOn: Binding(get: { editor.activeBold }, set: { editor.setTextFormat(bold: $0) })) { Image(systemName: "bold") }
                    .toggleStyle(.button).help("Bold")
                Toggle(isOn: Binding(get: { editor.activeItalic }, set: { editor.setTextFormat(italic: $0) })) { Image(systemName: "italic") }
                    .toggleStyle(.button).help("Italic")
                Spacer()
                Picker("Alignment", selection: Binding(get: { editor.activeAlignment.rawValue }, set: { editor.setTextFormat(alignment: NSTextAlignment(rawValue: $0)) })) {
                    Image(systemName: "text.alignleft").tag(NSTextAlignment.left.rawValue)
                    Image(systemName: "text.aligncenter").tag(NSTextAlignment.center.rawValue)
                    Image(systemName: "text.alignright").tag(NSTextAlignment.right.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 110)
            }
        }
    }
}

private struct SliderRow: View {
    let title: String
    let value: CGFloat
    let range: ClosedRange<CGFloat>
    let format: (CGFloat) -> String
    let set: (CGFloat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(format(value)).monospacedDigit()
            }
            Slider(value: Binding(get: { value }, set: set), in: range)
        }
    }
}

struct Swatch: View {
    static func name(of color: NSColor) -> String {
        let names = ["Black", "Grey", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Indigo", "Purple", "Pink", "White"]
        return Palette.swatches.firstIndex { Palette.same($0, color) }.map { names[$0] } ?? "Custom colour"
    }

    let color: NSColor
    let selected: Bool
    var size: CGFloat = 26
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: color))
                .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1))
                .padding(selected ? 4 : 0)
                .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }
}
