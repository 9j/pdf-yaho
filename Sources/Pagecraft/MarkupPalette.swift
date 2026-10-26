import PagecraftCore
import SwiftUI

/// Floating tool palette shown at the top of the page in Markup mode.
struct MarkupPalette: View {
    @ObservedObject var editor: EditorController
    @State private var showStyle = false

    var body: some View {
        HStack(spacing: 2) {
            group([.select])
            divider
            group([.highlight, .underline, .strikeout])
            divider
            menuButton(Tool.pens, current: editor.lastPen, label: "Pen")
            menuButton(Tool.shapes, current: editor.lastShape, label: "Shapes")
            group([.text, .note])
            divider
            signButton
            stampButton
            group([.image, .link])
            measureButton
            divider
            group([.redact, .eraser])
            divider
            styleButton
            divider
            PaletteButton(symbol: "arrow.uturn.backward", label: "Undo", help: "Undo (⌘Z)", selected: false) {
                editor.undoManager?.undo()
            }
            .disabled(!(editor.undoManager?.canUndo ?? false))
            PaletteButton(symbol: "arrow.uturn.forward", label: "Redo", help: "Redo (⇧⌘Z)", selected: false) {
                editor.undoManager?.redo()
            }
            .disabled(!(editor.undoManager?.canRedo ?? false))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        .id(editor.revision)
    }

    private var divider: some View {
        Divider().frame(height: 30).padding(.horizontal, 3)
    }

    private func tint(_ tool: Tool) -> Color? {
        tool.isStyled ? Color(nsColor: editor.style(for: tool).color) : nil
    }

    private func group(_ tools: [Tool]) -> some View {
        ForEach(tools) { tool in
            PaletteButton(symbol: tool.symbol, label: tool.label, help: tool.help, selected: editor.tool == tool, tint: tint(tool)) {
                editor.tool = tool
            }
            .contextMenu {
                if tool == .redact {
                    Picker("Mark Style", selection: $editor.redactionStyle) {
                        ForEach(Annotations.RedactionStyle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Button("Find and Redact…") { editor.showFindRedact = true }
                    if editor.hasRedactions { Button("Apply Redactions…") { editor.applyRedactions() } }
                }
            }
        }
    }

    /// A tool family (pens, shapes) behind one button that remembers the last choice.
    private func menuButton(_ tools: [Tool], current: Tool, label: String) -> some View {
        let active = tools.contains(editor.tool)
        let shown = active ? editor.tool : current
        return Menu {
            ForEach(tools) { tool in
                Button { editor.tool = tool } label: { Label(tool.help, systemImage: tool.symbol) }
            }
        } label: {
            PaletteLabel(symbol: shown.symbol, label: label, selected: active, tint: tint(shown), showsChevron: true)
        } primaryAction: {
            editor.tool = shown
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(label): \(tools.map(\.label).joined(separator: ", "))")
    }

    private var signButton: some View {
        let active = Tool.fillAndSign.contains(editor.tool)
        let shown = active ? editor.tool : editor.lastFillAndSign
        return Menu {
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
                if !editor.signatureLibrary.isEmpty {
                    Menu("Delete") {
                        ForEach(editor.signatureLibrary) { signature in
                            Button(signature.isInitials ? "Initials" : "Signature") { editor.deleteSignature(signature) }
                        }
                    }
                }
            }
            Section("Fill") {
                ForEach([Tool.checkmark, .cross, .date]) { tool in
                    Button { editor.tool = tool } label: { Label(tool.label, systemImage: tool.symbol) }
                }
                Button { editor.tool = .text } label: { Label("Text", systemImage: Tool.text.symbol) }
            }
            Section("Form Fields") {
                ForEach(Tool.formFields) { tool in
                    Button { editor.tool = tool } label: { Label(tool.label, systemImage: tool.symbol) }
                }
                Button("Clear Form") { editor.resetForm() }
            }
        } label: {
            PaletteLabel(symbol: shown.symbol, label: shown == .signature ? "Sign" : shown.label, selected: active,
                         tint: shown == .signature ? nil : tint(shown), showsChevron: true)
        } primaryAction: {
            editor.tool = shown
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Fill & Sign")
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

    private var measureButton: some View {
        let active = Tool.measures.contains(editor.tool)
        let shown = active ? editor.tool : editor.lastMeasure
        return Menu {
            ForEach(Tool.measures) { tool in
                Button { editor.tool = tool } label: { Label(tool.label, systemImage: tool.symbol) }
            }
            Divider()
            Button("Scale: \(editor.measureScale.ratio == 1 ? "1:1" : "1:\(editor.measureScale.ratio.formatted())") in \(editor.measureScale.unit.rawValue)…") {
                editor.showMeasureScale = true
            }
        } label: {
            PaletteLabel(symbol: shown.symbol, label: "Measure", selected: active, showsChevron: true)
        } primaryAction: {
            editor.tool = shown
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Measure distance, perimeter and area. Click points; double-click or Return to finish.")
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

struct PaletteLabel: View {
    let symbol: String
    let label: String
    let selected: Bool
    var tint: Color?
    var showsChevron = false
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(height: 20)
                if let tint, selected {
                    Capsule().fill(tint).frame(width: 10, height: 3).offset(x: 4, y: 4)
                }
            }
            HStack(spacing: 1) {
                Text(label).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.7)
                if showsChevron { Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold)) }
            }
            .foregroundStyle(selected ? Color.accentColor : .secondary)
        }
        .foregroundStyle(selected ? Color.accentColor : .primary)
        .frame(width: 50, height: 42)
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
                Picker("Line", selection: Binding(get: { editor.activeDash }, set: { editor.setDash($0) })) {
                    ForEach(Annotations.LineStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if editor.fillApplies {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fill").foregroundStyle(.secondary)
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
