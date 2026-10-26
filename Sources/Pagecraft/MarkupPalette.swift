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
            group([.pen])
            shapesButton
            group([.text, .note])
            divider
            group([.signature, .redact, .eraser])
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
        Divider().frame(height: 30).padding(.horizontal, 4)
    }

    private func group(_ tools: [Tool]) -> some View {
        ForEach(tools) { tool in
            PaletteButton(symbol: tool.symbol, label: tool.label, help: tool.help, selected: editor.tool == tool,
                          tint: tool.isStyled ? Color(nsColor: editor.style(for: tool).color) : nil) {
                editor.tool = tool
            }
            .contextMenu {
                if tool == .signature {
                    Button("Edit Signature…") { editor.showSignaturePad = true }
                }
                if tool == .redact, editor.hasRedactions {
                    Button("Apply Redactions…") { editor.applyRedactions() }
                }
            }
        }
    }

    private var shapesButton: some View {
        let current = editor.tool.shape != nil ? editor.tool : editor.lastShape
        return Menu {
            ForEach(Tool.shapes) { shape in
                Button { editor.tool = shape } label: { Label(shape.label, systemImage: shape.symbol) }
            }
        } label: {
            PaletteLabel(symbol: current.symbol, label: "Shapes", selected: editor.tool.shape != nil,
                         tint: Color(nsColor: editor.style(for: current).color), showsChevron: true)
        } primaryAction: {
            editor.tool = current
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Shapes (R, O, L, A)")
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
            .frame(width: 52, height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Colour and size")
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
                Text(label).font(.system(size: 10))
                if showsChevron { Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold)) }
            }
            .foregroundStyle(selected ? Color.accentColor : .secondary)
        }
        .foregroundStyle(selected ? Color.accentColor : .primary)
        .frame(width: 52, height: 42)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.14) : hovering ? Color.primary.opacity(0.06) : .clear)
        }
        .opacity(isEnabled ? 1 : 0.35)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Swatches, a custom colour well and a width/size slider. Applies to the selection if there is one,
/// otherwise to the active tool's default.
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
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(editor.widthIsFontSize ? "Font size" : "Thickness").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(editor.activeWidth.rounded())) pt").monospacedDigit()
                    }
                    Slider(value: Binding(get: { editor.activeWidth }, set: { editor.setWidth($0.rounded()) }),
                           in: editor.widthIsFontSize ? 8...48 : 1...12)
                    if !editor.widthIsFontSize {
                        RoundedRectangle(cornerRadius: editor.activeWidth / 2)
                            .fill(Color(nsColor: editor.activeColor))
                            .frame(height: editor.activeWidth)
                            .frame(maxWidth: .infinity)
                            .frame(height: 14)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 240)
    }
}

struct Swatch: View {
    let color: NSColor
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: color))
                .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1))
                .padding(selected ? 4 : 0)
                .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
    }
}
