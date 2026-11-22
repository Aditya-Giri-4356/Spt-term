import Foundation

/// Mock implementation of LyricsServiceProtocol for previews and offline tests.
final class MockLyricsService: LyricsServiceProtocol {
    var isEnabled: Bool = false
    var cacheCount: Int { mockLyrics.count }

    private var mockLyrics: [String: [LyricsLine]] = [:]
    private var mockPlain: [String: String] = [:]

    init() {}

    func fetchLyrics(for track: Track) async -> [LyricsLine]? {
        guard isEnabled else { return nil }
        return mockLyrics[track.id] ?? track.lyrics
    }

    func plainLyrics(for track: Track) async -> String? {
        guard isEnabled else { return nil }
        return mockPlain[track.id]
    }

    func cachedLyrics(for uri: String) -> [LyricsLine]? {
        guard isEnabled else { return nil }
        return mockLyrics[uri]
    }

    func cachedPlainLyrics(for uri: String) -> String? {
        guard isEnabled else { return nil }
        return mockPlain[uri]
    }

    func cancelCurrentFetch() {}

    func setMockLyrics(for uri: String, synced: [LyricsLine], plain: String? = nil) {
        mockLyrics[uri] = synced
        if let plain {
            mockPlain[uri] = plain
        }
    }
}
