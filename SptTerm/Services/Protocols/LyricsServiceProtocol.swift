import Foundation

/// Protocol for fetching and caching track lyrics.
protocol LyricsServiceProtocol: AnyObject {
    var isEnabled: Bool { get set }
    var cacheCount: Int { get }
    func fetchLyrics(for track: Track) async -> [LyricsLine]?
    func plainLyrics(for track: Track) async -> String?
    func cachedLyrics(for uri: String) -> [LyricsLine]?
    func cachedPlainLyrics(for uri: String) -> String?
    func cancelCurrentFetch()
}
