import Foundation

/// Persistent store for on-screen discovered Spotify playlists (v2).
/// Stores names and last seen labels only. Contains no user IDs, no tokens, no credentials.
final class STLibraryCache {
    static let shared = STLibraryCache()

    private let defaults: UserDefaults
    private let key = "sptterm.library.cached_playlists.v2"
    private let legacyKey = "sptterm.library.cached_playlists"
    private var cachedItems: [STCachedPlaylist] = []
    private let lock = NSLock()

    init(defaults: UserDefaults = UserDefaults(suiteName: "com.aditya.sptterm.tweak") ?? .standard) {
        self.defaults = defaults
        // Purge legacy v1 cache on first load so polluted entries disappear
        defaults.removeObject(forKey: legacyKey)
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
    /// Dedupes by parsed name; updates lastLabel on every re-scan; preserves original `firstSeen`; caps at 500.
    @discardableResult
    func merge(playlists: [STCachedPlaylist]) -> Int {
        lock.lock()
        defer { lock.unlock() }

        var countAdded = 0
        for item in playlists {
            if let existingIndex = cachedItems.firstIndex(where: { $0.name == item.name }) {
                // Already in cache: update lastLabel, keep original firstSeen
                let existing = cachedItems[existingIndex]
                cachedItems[existingIndex] = STCachedPlaylist(
                    name: existing.name,
                    lastLabel: item.lastLabel,
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
