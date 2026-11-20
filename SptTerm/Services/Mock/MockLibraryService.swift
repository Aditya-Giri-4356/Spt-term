import Foundation

final class MockLibraryService: LibraryServiceProtocol {
    /// Optional artificial latency so loading states can be exercised later.
    private let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
    }

    func fetchHomeSections() async throws -> [HomeSection] {
        try await wait()
        return MockCatalog.homeSections
    }

    func fetchAlbums() async throws -> [Album] {
        try await wait()
        return MockCatalog.albums
    }

    func fetchAlbum(id: String) async throws -> Album? {
        try await wait()
        return MockCatalog.albumByID[id]
    }

    func fetchPlaylists() async throws -> [Playlist] {
        try await wait()
        return MockCatalog.playlists
    }

    func fetchPlaylist(id: String) async throws -> Playlist? {
        try await wait()
        return MockCatalog.playlistByID[id]
    }

    func fetchArtists() async throws -> [Artist] {
        try await wait()
        return MockCatalog.artists
    }

    func fetchTracks(forAlbumID albumID: String) async throws -> [Track] {
        try await wait()
        guard let album = MockCatalog.albumByID[albumID] else { return [] }
        return MockCatalog.tracks(for: album.trackIDs)
    }

    func fetchTracks(forPlaylistID playlistID: String) async throws -> [Track] {
        try await wait()
        guard let playlist = MockCatalog.playlistByID[playlistID] else { return [] }
        return MockCatalog.tracks(for: playlist.trackIDs)
    }

    func fetchTracks(forArtistID artistID: String) async throws -> [Track] {
        try await wait()
        return MockCatalog.tracks.filter { $0.artistID == artistID }
    }

    func fetchTracks(ids: [String]) async throws -> [Track] {
        try await wait()
        return MockCatalog.tracks(for: ids)
    }

    func fetchLikedTracks() async throws -> [Track] {
        try await wait()
        guard let playlist = MockCatalog.playlistByID["p5"] else { return [] }
        return MockCatalog.tracks(for: playlist.trackIDs)
    }

    func search(query: String) async throws -> SearchResults {
        try await wait()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SearchResults(query: query, artists: [], albums: [], tracks: [], playlists: [])
        }
        let needle = trimmed.lowercased()
        let artists = MockCatalog.artists.filter { $0.name.lowercased().contains(needle) }
        let albums = MockCatalog.albums.filter {
            $0.title.lowercased().contains(needle) || $0.artistName.lowercased().contains(needle)
        }
        let tracks = MockCatalog.tracks.filter { $0.matches(needle) }
        let playlists = MockCatalog.playlists.filter {
            $0.name.lowercased().contains(needle) || $0.summary.lowercased().contains(needle)
        }
        return SearchResults(query: trimmed, artists: artists, albums: albums, tracks: tracks, playlists: playlists)
    }

    private func wait() async throws {
        guard delayNanoseconds > 0 else { return }
        try await Task.sleep(nanoseconds: delayNanoseconds)
    }
}
