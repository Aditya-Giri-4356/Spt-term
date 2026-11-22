import Foundation

/// Entry stored in the in-memory lyrics cache.
private struct LyricsCacheEntry {
    let synced: [LyricsLine]?
    let plain: String?
    let timestamp: Date
}

/// Live lyrics service interfacing with lrclib.net via URLSession.
final class STLyricsService: LyricsServiceProtocol {
    static let shared = STLyricsService()

    private let defaults = UserDefaults(suiteName: "com.aditya.sptterm.tweak") ?? .standard
    private let session: URLSession
    private var cache: [String: LyricsCacheEntry] = [:]
    private var cacheKeys: [String] = []
    private var currentFetchTask: Task<[LyricsLine]?, Never>?
    private let lock = NSLock()

    var isEnabled: Bool {
        get { defaults.bool(forKey: "sptterm.tweak.lyrics_enabled") }
        set { defaults.set(newValue, forKey: "sptterm.tweak.lyrics_enabled") }
    }

    var cacheCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 8.0
        config.httpAdditionalHeaders = ["User-Agent": "SptTerm/0.1"]
        self.session = URLSession(configuration: config)
    }

    func cancelCurrentFetch() {
        currentFetchTask?.cancel()
        currentFetchTask = nil
    }

    func cachedLyrics(for uri: String) -> [LyricsLine]? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = cache[uri] else { return nil }
        if let synced = entry.synced {
            return synced
        }
        // Negative cache: check if within 24h
        if Date().timeIntervalSince(entry.timestamp) < 86400 {
            return []
        }
        return nil
    }

    func cachedPlainLyrics(for uri: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cache[uri]?.plain
    }

    func fetchLyrics(for track: Track) async -> [LyricsLine]? {
        guard isEnabled else { return nil }
        let uri = track.id

        // Check cache first
        if let cached = cachedLyrics(for: uri) {
            return cached.isEmpty ? nil : cached
        }

        cancelCurrentFetch()

        let task = Task<[LyricsLine]?, Never> { () -> [LyricsLine]? in
            guard !Task.isCancelled else { return nil }

            var components = URLComponents(string: "https://lrclib.net/api/get")
            var items: [URLQueryItem] = [
                URLQueryItem(name: "track_name", value: track.title),
                URLQueryItem(name: "artist_name", value: track.artistName)
            ]
            if !track.albumTitle.isEmpty {
                items.append(URLQueryItem(name: "album_name", value: track.albumTitle))
            }
            if track.duration > 0 {
                items.append(URLQueryItem(name: "duration", value: "\(Int(track.duration.rounded()))"))
            }
            components?.queryItems = items

            guard let url = components?.url else { return nil }

            do {
                let (data, response) = try await session.data(from: url)
                guard !Task.isCancelled else { return nil }

                if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                    recordCache(uri: uri, synced: nil, plain: nil)
                    return nil
                }

                struct LRCLIBResponse: Decodable {
                    let syncedLyrics: String?
                    let plainLyrics: String?
                }

                let decoded = try JSONDecoder().decode(LRCLIBResponse.self, from: data)
                let plain = decoded.plainLyrics

                if let syncedStr = decoded.syncedLyrics, !syncedStr.isEmpty {
                    let parsed = STLRCParser.parseToLyricsLines(syncedStr)
                    recordCache(uri: uri, synced: parsed, plain: plain)
                    return parsed
                } else {
                    recordCache(uri: uri, synced: nil, plain: plain)
                    return nil
                }
            } catch {
                return nil
            }
        }

        currentFetchTask = task
        let result = await task.value
        return result
    }

    func plainLyrics(for track: Track) async -> String? {
        if let plain = cachedPlainLyrics(for: track.id) {
            return plain
        }
        _ = await fetchLyrics(for: track)
        return cachedPlainLyrics(for: track.id)
    }

    private func recordCache(uri: String, synced: [LyricsLine]?, plain: String?) {
        lock.lock()
        defer { lock.unlock() }

        if cache[uri] == nil {
            cacheKeys.append(uri)
            if cacheKeys.count > 100 {
                let oldest = cacheKeys.removeFirst()
                cache.removeValue(forKey: oldest)
            }
        }
        cache[uri] = LyricsCacheEntry(synced: synced, plain: plain, timestamp: Date())
    }
}
