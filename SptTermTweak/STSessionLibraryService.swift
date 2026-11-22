import Foundation
import UIKit
import MediaPlayer

final class STSessionLibraryService: LibraryServiceProtocol {
    static let shared = STSessionLibraryService()

    static let header = "SESSION HISTORY - browse/search in Spotify"
    let headerTitle = "SESSION HISTORY - browse/search in Spotify"

    private let defaults: UserDefaults
    private let key = "sptterm.session.tracks"
    private var tracks: [Track] = []
    private let lock = NSLock()
    private var pollTimer: Timer?

    init(defaults: UserDefaults = UserDefaults(suiteName: "com.aditya.sptterm.tweak") ?? .standard) {
        self.defaults = defaults
        self.tracks = Self.loadTracks(from: defaults, key: key)
        startObserving()
    }

    deinit {
        pollTimer?.invalidate()
    }

    private static func loadTracks(from defaults: UserDefaults, key: String) -> [Track] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Track].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveTracks() {
        if let data = try? JSONEncoder().encode(tracks) {
            defaults.set(data, forKey: key)
        }
    }

    private func startObserving() {
        DispatchQueue.main.async { [weak self] in
            self?.pollNowPlaying()
            self?.pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.pollNowPlaying()
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleDidBecomeActive() {
        pollNowPlaying()
    }

    func recordTrack(_ track: Track) {
        lock.lock()
        var trackToStore = track

        // Preserve existing captured thumbnail if new track doesn't have one
        if let existing = tracks.first(where: { $0.id == track.id }),
           trackToStore.artworkMatrixRows == nil,
           let existingRows = existing.artworkMatrixRows {
            trackToStore.artworkMatrixRows = existingRows
            trackToStore.artworkAccentHex = existing.artworkAccentHex
        }

        // Deduplicate by URI (track.id), newest first, cap at 200
        tracks.removeAll { $0.id == track.id }
        tracks.insert(trackToStore, at: 0)
        if tracks.count > 200 {
            tracks = Array(tracks.prefix(200))
        }
        saveTracks()
        lock.unlock()

        if trackToStore.artworkMatrixRows == nil {
            captureArtworkForTrack(id: track.id, title: track.title)
        }
    }

    private func captureArtworkForTrack(id: String, title: String) {
        Task { [weak self] in
            var elapsed: TimeInterval = 0
            let interval: TimeInterval = 0.5
            let maxWait: TimeInterval = 5.0
            var captured: (rows: [String], hex: String)? = nil

            while elapsed <= maxWait {
                let info = await MainActor.run { MPNowPlayingInfoCenter.default().nowPlayingInfo }
                guard let info, !info.isEmpty else { break }

                let currentTitle = info[MPMediaItemPropertyTitle] as? String ?? ""
                let currentURI = (info["MPNowPlayingInfoPropertyExternalContentIdentifier"] as? String)
                    ?? (info[MPMediaItemPropertyPersistentID] as? String) ?? ""

                // Verify nowPlayingInfo STILL matches the track being captured (no stale cover)
                let matchesURI = currentURI.isEmpty || currentURI == id
                let matchesTitle = currentTitle == title
                if matchesURI && matchesTitle {
                    if let artwork = info[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork {
                        let img = await MainActor.run { artwork.image(at: CGSize(width: 64, height: 48)) }
                        if let img, let result = Self.rasterizeImageToMatrix(img, columns: 16) {
                            captured = result
                            STLog.log("SptTerm: captured history thumbnail for '\(title)' after \(String(format: "%.1f", elapsed))s")
                            break
                        }
                    }
                } else {
                    // Track changed before artwork arrived! Abort to prevent stale cover
                    STLog.log("SptTerm: aborted thumbnail capture for '\(title)' - track changed to '\(currentTitle)'")
                    break
                }

                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                elapsed += interval
            }

            if let (rows, hex) = captured {
                self?.updateTrackArtwork(id: id, rows: rows, accentHex: hex)
            } else {
                STLog.log("SptTerm: thumbnail capture timed out or nil for '\(title)', storing none")
            }
        }
    }

    private func updateTrackArtwork(id: String, rows: [String], accentHex: String) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = tracks.firstIndex(where: { $0.id == id }) {
            var updated = tracks[idx]
            updated.artworkMatrixRows = rows
            updated.artworkAccentHex = accentHex
            tracks[idx] = updated
            saveTracks()
        }
    }

    static func rasterizeImageToMatrix(_ image: UIImage, columns: Int = 16) -> (rows: [String], hex: String)? {
        guard let cgImage = image.cgImage else { return nil }

        let cols = max(columns, 8)
        let rows = max(Int((Double(cols) * 0.72).rounded()), 6)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [UInt8](repeating: 0, count: cols * rows * 4)
        guard let context = CGContext(
            data: &pixelData,
            width: cols,
            height: rows,
            bitsPerComponent: 8,
            bytesPerRow: cols * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cols, height: rows))

        let ramp = Array(" .:-=+*#%@")
        var lines: [String] = []

        var totalR: Double = 0
        var totalG: Double = 0
        var totalB: Double = 0
        var count: Double = 0

        for r in 0..<rows {
            var line = ""
            for c in 0..<cols {
                let offset = (r * cols + c) * 4
                let red = Double(pixelData[offset])
                let green = Double(pixelData[offset + 1])
                let blue = Double(pixelData[offset + 2])
                let a = Double(pixelData[offset + 3]) / 255.0

                let lum = (0.299 * red + 0.587 * green + 0.114 * blue) / 255.0
                let index = min(max(Int(lum * Double(ramp.count - 1)), 0), ramp.count - 1)
                line.append(ramp[index])

                if a > 0.3 {
                    totalR += red * a
                    totalG += green * a
                    totalB += blue * a
                    count += a
                }
            }
            lines.append(line)
        }

        let hex: String
        if count > 0 {
            let avgR = Int((totalR / count).rounded())
            let avgG = Int((totalG / count).rounded())
            let avgB = Int((totalB / count).rounded())
            hex = String(format: "#%02X%02X%02X", avgR, avgG, avgB)
        } else {
            hex = "#00FF66"
        }

        return (lines, hex)
    }

    func recordFromNowPlayingInfo(_ info: [String: Any]) {
        let title = info[MPMediaItemPropertyTitle] as? String ?? ""
        let artist = info[MPMediaItemPropertyArtist] as? String ?? ""
        let album = info[MPMediaItemPropertyAlbumTitle] as? String ?? ""
        let duration = (info[MPMediaItemPropertyPlaybackDuration] as? NSNumber)?.doubleValue ?? 0
        let uri = (info["MPNowPlayingInfoPropertyExternalContentIdentifier"] as? String)
            ?? (info[MPMediaItemPropertyPersistentID] as? String)
            ?? "\(title)|\(artist)"

        guard !title.isEmpty else { return }

        let track = Track(
            id: uri,
            title: title,
            artistID: "spotify:artist:unknown",
            artistName: artist,
            albumID: "spotify:album:unknown",
            albumTitle: album,
            year: Calendar.current.component(.year, from: Date()),
            trackNumber: 1,
            duration: duration,
            formatLabel: "STREAM",
            bitrateLabel: "320k",
            lyrics: []
        )
        recordTrack(track)
    }

    @objc func pollNowPlaying() {
        guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo, !info.isEmpty else {
            return
        }
        recordFromNowPlayingInfo(info)
    }

    func openTrack(_ track: Track) {
        let uri = track.id.hasPrefix("spotify:") || track.id.hasPrefix("http") ? track.id : "spotify:track:\(track.id)"
        guard let url = URL(string: uri) else { return }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { success in
                STLog.log("SptTerm: openURL completion: \(success ? 1 : 0) for \(uri)")
            }
        }
    }

    // MARK: - LibraryServiceProtocol Conformance

    func fetchHomeSections() async throws -> [HomeSection] {
        lock.lock()
        let currentTracks = tracks
        lock.unlock()

        guard !currentTracks.isEmpty else {
            return []
        }

        return [
            HomeSection(
                id: "session-history",
                title: "SESSION HISTORY - browse/search in Spotify",
                subtitle: "\(currentTracks.count) tracks observed",
                kind: .recentlyPlayed,
                trackIDs: currentTracks.map(\.id),
                albumIDs: [],
                playlistIDs: [],
                artistIDs: []
            )
        ]
    }

    func fetchAlbums() async throws -> [Album] {
        return [] // No fake albums
    }

    func fetchAlbum(id: String) async throws -> Album? {
        return nil
    }

    func fetchPlaylists() async throws -> [Playlist] {
        return [] // No fake playlists
    }

    func fetchPlaylist(id: String) async throws -> Playlist? {
        return nil
    }

    func fetchArtists() async throws -> [Artist] {
        return [] // No fake artists
    }

    func fetchTracks(forAlbumID albumID: String) async throws -> [Track] {
        return []
    }

    func fetchTracks(forPlaylistID playlistID: String) async throws -> [Track] {
        return []
    }

    func fetchTracks(forArtistID artistID: String) async throws -> [Track] {
        return []
    }

    func fetchTracks(ids: [String]) async throws -> [Track] {
        lock.lock()
        defer { lock.unlock() }
        let set = Set(ids)
        return tracks.filter { set.contains($0.id) }
    }

    func fetchLikedTracks() async throws -> [Track] {
        lock.lock()
        defer { lock.unlock() }
        return tracks
    }

    func search(query: String) async throws -> SearchResults {
        lock.lock()
        defer { lock.unlock() }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SearchResults(query: query, artists: [], albums: [], tracks: [], playlists: [])
        }
        let matching = tracks.filter { $0.matches(trimmed) }
        return SearchResults(query: trimmed, artists: [], albums: [], tracks: matching, playlists: [])
    }

    // MARK: - On-screen Playlists Discovery (Tweak UI Hook)

    func scanPlaylists() async -> [STCachedPlaylist] {
        return await MainActor.run {
            STSpotifyLibraryScanner.scanAndCachePlaylists()
        }
    }

    func cachedPlaylists() -> [STCachedPlaylist] {
        return STLibraryCache.shared.allPlaylists()
    }

    @MainActor
    func activatePlaylist(label: String) -> (success: Bool, message: String) {
        return STSpotifyLibraryScanner.activatePlaylist(nameOrLabel: label)
    }

    func clearPlaylistCache() {
        STLibraryCache.shared.clear()
    }

    // MARK: - On-screen Opened-Playlist Tracks

    func openedPlaylistTracks() -> [String] {
        return STOpenedPlaylistTracks.shared.allTracks()
    }

    @MainActor
    func activateTrack(label: String) -> (success: Bool, message: String) {
        return STSpotifyLibraryScanner.activateTrack(label: label)
    }

    func clearOpenedPlaylistTracks() {
        STOpenedPlaylistTracks.shared.clear()
    }

    // MARK: - Multi-step Batch Scanning

    func scanAll() async -> (steps: Int, namesTotal: Int) {
        return await STLibraryBatchScanner.runScanAll()
    }
}
