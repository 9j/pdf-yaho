import SwiftUI

/// A tool tile. `.compact` is the vertical card used in "Tools for You"; `.row` is the wide card on the Tools page.
struct ToolCard: View {
    enum Style { case compact, row }

    let tool: HomeTool
    var style: Style = .row
    @State private var hovering = false

    var body: some View {
        Button { Task { @MainActor in tool.run() } } label: {
            Group {
                switch style {
                case .compact:
                    VStack(alignment: .leading, spacing: 10) {
                        icon
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.title).font(.callout.weight(.semibold)).lineLimit(1)
                            Text(tool.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: 136, height: 124, alignment: .topLeading)
                case .row:
                    HStack(spacing: 12) {
                        icon
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.title).font(.callout.weight(.semibold)).lineLimit(1)
                            Text(tool.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(hovering ? 0.14 : 0.07), radius: hovering ? 6 : 2.5, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(hovering ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.08),
                                  lineWidth: hovering ? 1.5 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(tool.title)
        .accessibilityHint(tool.summary)
    }

    private var icon: some View {
        Image(systemName: tool.symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(tool.tint)
            .frame(width: 36, height: 36)
            .background(tool.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
