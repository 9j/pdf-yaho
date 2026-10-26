import AppKit
import Observation

extension URL {
    /// Canonical spelling of a file URL so `/var/...` and `/private/var/...` compare equal.
    var homeNormalized: URL { standardizedFileURL.resolvingSymlinksInPath() }
}

/// Recents (owned by NSDocumentController) and favorites (owned by us, kept in UserDefaults as file paths).
@MainActor
@Observable
final class HomeStore {
    static let favoritesKey = "HomeFavoritePaths"

    private(set) var recents: [URL] = []
    private(set) var favorites: [URL] = []
    /// Bumped on every refresh so cards re-read their "last opened" date.
    private(set) var revision = 0

    init() { refresh() }

    func refresh() {
        let recentURLs = Self.unique(NSDocumentController.shared.recentDocumentURLs.map(\.homeNormalized))
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if recentURLs != recents { recents = recentURLs }

        let stored = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? []
        let favoriteURLs = Self.unique(stored.map { URL(fileURLWithPath: $0).homeNormalized })
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if favoriteURLs != favorites { favorites = favoriteURLs }
        if favoriteURLs.map(\.path) != stored { saveFavorites() }
        revision += 1
    }

    // MARK: Favorites

    func isFavorite(_ url: URL) -> Bool { favorites.contains(url.homeNormalized) }

    func toggleFavorite(_ url: URL) {
        let url = url.homeNormalized
        if let index = favorites.firstIndex(of: url) {
            favorites.remove(at: index)
        } else {
            favorites.insert(url, at: 0)
        }
        saveFavorites()
    }

    private func saveFavorites() {
        UserDefaults.standard.set(favorites.map(\.path), forKey: Self.favoritesKey)
    }

    // MARK: Recents

    func clearRecents() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        recents = []
    }

    /// NSDocumentController cannot drop a single entry, so clear the list and re-add the others, oldest first.
    func removeFromRecents(_ url: URL) {
        let url = url.homeNormalized
        let kept = recents.filter { $0 != url }
        NSDocumentController.shared.clearRecentDocuments(nil)
        for other in kept.reversed() { NSDocumentController.shared.noteNewRecentDocumentURL(other) }
        recents = kept
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }
}
