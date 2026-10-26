import AppKit
import SwiftUI

/// A recent or favorite document: first-page thumbnail, name and last-opened date.
struct DocumentCard: View {
    let url: URL
    @Environment(HomeStore.self) private var store
    @State private var preview: DocumentPreview?
    @State private var hovering = false

    private static let plateHeight: CGFloat = 148

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    private struct LoadKey: Hashable {
        let url: URL
        let revision: Int
    }

    var body: some View {
        let favorite = store.isFavorite(url)
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Button(action: open) { plate }
                    .buttonStyle(.plain)
                    .accessibilityLabel(url.lastPathComponent)
                    .accessibilityHint("Opens the document")
                if hovering || favorite {
                    starButton(favorite: favorite)
                        .padding(6)
                        .transition(.opacity)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: favorite)
        .help(url.path)
        .contextMenu { contextMenu(favorite: favorite) }
        .task(id: LoadKey(url: url, revision: store.revision)) {
            preview = await PreviewLoader.shared.preview(for: url)
        }
    }

    // MARK: Pieces

    private var plate: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.09 : 0.05))
            plateContent
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.plateHeight)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(hovering ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: hovering ? 2 : 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var plateContent: some View {
        switch preview?.state {
        case .ready:
            if let image = preview?.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                    .padding(14)
            }
        case .locked:
            placeholder(symbol: "lock.fill", text: "Password protected")
        case .unreadable:
            placeholder(symbol: "exclamationmark.triangle", text: "Can't preview")
        case nil:
            Image(systemName: "doc.richtext")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.quaternary)
        }
    }

    private func placeholder(symbol: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light))
            Text(text).font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    private func starButton(favorite: Bool) -> some View {
        Button { store.toggleFavorite(url) } label: {
            Image(systemName: favorite ? "star.fill" : "star")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(favorite ? Color.yellow : Color.secondary)
                .frame(width: 26, height: 26)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .help(favorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityLabel(favorite ? "Remove from Favorites" : "Add to Favorites")
    }

    @ViewBuilder
    private func contextMenu(favorite: Bool) -> some View {
        Button("Open", action: open)
        Button(favorite ? "Remove from Favorites" : "Add to Favorites") { store.toggleFavorite(url) }
        Divider()
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        if store.recents.contains(url.homeNormalized) {
            Button("Remove from Recents") { store.removeFromRecents(url) }
        }
    }

    private var dateText: String {
        preview?.date.map(Self.dateFormatter.string(from:)) ?? " "
    }

    private func open() {
        DocumentLauncher.open(url)
    }
}
