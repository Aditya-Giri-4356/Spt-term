import Foundation

/// In-memory, session-only store for tracks observed in an opened Spotify playlist.
/// Preserved only in memory during the app lifecycle; never written to disk or UserDefaults.
final class STOpenedPlaylistTracks {
    static let shared = STOpenedPlaylistTracks()

    private var tracks: [String] = []
    private let lock = NSLock()

    private init() {}

    /// Returns the ordered list of observed track labels.
    func allTracks() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return tracks
    }

    /// Merges freshly scanned track labels (ordered by frame.y).
    /// If there is at least one overlapping track, appends new unseen tracks.
    /// If there is zero overlap and the existing list is non-empty, replaces the list (new playlist opened).
    func merge(newScanLabels: [String]) {
        lock.lock()
        defer { lock.unlock() }

        guard !newScanLabels.isEmpty else { return }

        if tracks.isEmpty {
            tracks = newScanLabels
            if tracks.count > 300 { tracks = Array(tracks.prefix(300)) }
            return
        }

        let existingSet = Set(tracks)
        let hasOverlap = newScanLabels.contains { existingSet.contains($0) }

        if hasOverlap {
            for label in newScanLabels {
                if !existingSet.contains(label) {
                    tracks.append(label)
                }
            }
        } else {
            STLog.log("SptTerm: tracks list replaced (zero overlap, new playlist opened)")
            tracks = newScanLabels
        }

        if tracks.count > 300 {
            tracks = Array(tracks.prefix(300))
        }
    }

    /// Clears the track list.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        tracks.removeAll()
        STLog.log("SptTerm: opened-playlist tracks list cleared")
    }
}
