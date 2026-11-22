import Foundation

/// Persistent store for on-screen discovered Spotify playlists.
/// Stores names and accessibility labels only. Contains no user IDs, no tokens, no credentials.
final class STLibraryCache {
    static let shared = STLibraryCache()

    private let defaults: UserDefaults
    private let key = "sptterm.library.cached_playlists"
    private var cachedItems: [STCachedPlaylist] = []
    private let lock = NSLock()

    init(defaults: UserDefaults = UserDefaults(suiteName: "com.aditya.sptterm.tweak") ?? .standard) {
        self.defaults = defaults
        self.cachedItems = Self.load(from: defaults, key: key)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [STCachedPlaylist] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([STCachedPlaylist].self, from: data) else {
            return []
        }
        return decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cachedItems) {
            defaults.set(data, forKey: key)
        }
    }

    /// Returns all cached playlists, newest first.
    func allPlaylists() -> [STCachedPlaylist] {
        lock.lock()
        defer { lock.unlock() }
        return cachedItems
    }

    /// Merges newly scanned playlists into the cache.
    /// Dedupes by label; preserves original `firstSeen` for existing items; caps at 500 entries.
    @discardableResult
    func merge(playlists: [STCachedPlaylist]) -> Int {
        lock.lock()
        defer { lock.unlock() }

        var countAdded = 0
        for item in playlists {
            if let existingIndex = cachedItems.firstIndex(where: { $0.label == item.label }) {
                // Already in cache; update name if cleaner, but preserve firstSeen
                let existing = cachedItems[existingIndex]
                cachedItems[existingIndex] = STCachedPlaylist(
                    name: item.name.isEmpty ? existing.name : item.name,
                    label: existing.label,
                    firstSeen: existing.firstSeen
                )
            } else {
                // New playlist discovered
                cachedItems.insert(item, at: 0)
                countAdded += 1
            }
        }

        // Cap at 500 entries
        if cachedItems.count > 500 {
            cachedItems = Array(cachedItems.prefix(500))
        }

        save()
        STLog.log("SptTerm: library cache merged \(countAdded) new playlist(s), total in cache: \(cachedItems.count)")
        return countAdded
    }

    /// Clears all cached playlists from memory and UserDefaults.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cachedItems.removeAll()
        defaults.removeObject(forKey: key)
        STLog.log("SptTerm: library cache cleared")
    }
}
