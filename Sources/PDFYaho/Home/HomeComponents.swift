import AppKit
import SwiftUI

enum HomePage: String, CaseIterable, Identifiable {
    case home, recents, favorites, tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .recents: "Recents"
        case .favorites: "Favorites"
        case .tools: "Tools"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .recents: "clock"
        case .favorites: "star"
        case .tools: "wrench.and.screwdriver"
        }
    }

    var filledSymbol: String {
        switch self {
        case .home: "house.fill"
        case .recents: "clock.fill"
        case .favorites: "star.fill"
        case .tools: "wrench.and.screwdriver.fill"
        }
    }
}

/// Native translucent sidebar material.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct HomeSidebar: View {
    @Binding var selection: HomePage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: Binding(get: { selection }, set: { if let page = $0 { selection = page } })) {
                ForEach(HomePage.allCases, id: \.self) { page in
                    Label(page.title, systemImage: selection == page ? page.filledSymbol : page.symbol)
                        .tag(page)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .padding(.top, 38)
            Text("PDF Yaho \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(SidebarMaterial())
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 0.5)
        }
        // ⌘1–⌘4 switch pages.
        .background {
            ForEach(Array(HomePage.allCases.enumerated()), id: \.element) { index, page in
                Button("") { selection = page }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .hidden()
            }
        }
    }
}

/// Centres page content in a column no wider than 880pt with at least 32pt gutters.
struct PageColumn<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 52)
                .padding(.bottom, 40)
                .frame(maxWidth: 944)
                .frame(maxWidth: .infinity)
        }
    }
}

struct PageHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .lineLimit(1)
            Spacer(minLength: 12)
            accessory
        }
    }
}

struct SectionHeader: View {
    let title: String
    var seeAll: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            if let seeAll {
                Button(action: seeAll) {
                    HStack(spacing: 3) {
                        Text("See All")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.callout)
                    .foregroundStyle(Color.accentColor.opacity(hovering ? 1 : 0.85))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .accessibilityLabel("See all \(title)")
            }
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
        )
    }
}

/// Full-window hint shown while files are dragged over the Home window.
struct DropOverlay: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            Color.accentColor.opacity(0.08)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [10, 7]))
                .padding(16)
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.accentColor)
                Text("Drop to open").font(.title2.weight(.semibold))
                Text("PDF files open in PDF Yaho").font(.callout).foregroundStyle(.secondary)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
