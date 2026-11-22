import Foundation

/// Read-only catalog surface. Everything is async so a real backend or local
/// database can slot in later without touching view models.
protocol LibraryServiceProtocol: AnyObject {
    func fetchHomeSections() async throws -> [HomeSection]
    func fetchAlbums() async throws -> [Album]
    func fetchAlbum(id: String) async throws -> Album?
    func fetchPlaylists() async throws -> [Playlist]
    func fetchPlaylist(id: String) async throws -> Playlist?
    func fetchArtists() async throws -> [Artist]
    func fetchTracks(forAlbumID albumID: String) async throws -> [Track]
    func fetchTracks(forPlaylistID playlistID: String) async throws -> [Track]
    func fetchTracks(forArtistID artistID: String) async throws -> [Track]
    func fetchTracks(ids: [String]) async throws -> [Track]
    func fetchLikedTracks() async throws -> [Track]
    func search(query: String) async throws -> SearchResults

    // MARK: - On-screen Playlists Discovery (Tweak UI Hook)
    func scanPlaylists() async -> [STCachedPlaylist]
    func cachedPlaylists() -> [STCachedPlaylist]
    @MainActor
    func activatePlaylist(label: String) -> (success: Bool, message: String)
    func clearPlaylistCache()

    // MARK: - On-screen Opened-Playlist Tracks
    func openedPlaylistTracks() -> [String]
    @MainActor
    func activateTrack(label: String) -> (success: Bool, message: String)
    func clearOpenedPlaylistTracks()
}

extension LibraryServiceProtocol {
    func scanPlaylists() async -> [STCachedPlaylist] { [] }
    func cachedPlaylists() -> [STCachedPlaylist] { [] }
    @MainActor
    func activatePlaylist(label: String) -> (success: Bool, message: String) {
        (false, "NOT ON SCREEN - open Spotify Library")
    }
    func clearPlaylistCache() {}

    func openedPlaylistTracks() -> [String] { [] }
    @MainActor
    func activateTrack(label: String) -> (success: Bool, message: String) {
        (false, "NOT ON SCREEN - scroll Spotify to this track")
    }
    func clearOpenedPlaylistTracks() {}
}
