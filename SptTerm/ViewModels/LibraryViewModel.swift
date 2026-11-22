import Combine
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var albums: [Album] = []
    @Published private(set) var artists: [Artist] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var likedTracks: [Track] = []
    @Published private(set) var cachedPlaylists: [STCachedPlaylist] = []
    @Published private(set) var openedPlaylistTracks: [String] = []
    @Published private(set) var isScanning = false
    @Published var playlistStatus: String?
    @Published var trackStatus: String?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let library: LibraryServiceProtocol

    init(library: LibraryServiceProtocol) {
        self.library = library
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        cachedPlaylists = library.cachedPlaylists()
        openedPlaylistTracks = library.openedPlaylistTracks()
        do {
            async let albumsTask = library.fetchAlbums()
            async let artistsTask = library.fetchArtists()
            async let playlistsTask = library.fetchPlaylists()
            async let likedTask = library.fetchLikedTracks()
            let (a, ar, p, l) = try await (albumsTask, artistsTask, playlistsTask, likedTask)
            albums = a
            artists = ar
            playlists = p
            likedTracks = l
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func scanPlaylists() async {
        isScanning = true
        let updated = await library.scanPlaylists()
        cachedPlaylists = updated
        openedPlaylistTracks = library.openedPlaylistTracks()
        isScanning = false
    }

    func scanAll() async {
        isScanning = true
        let res = await library.scanAll()
        cachedPlaylists = library.cachedPlaylists()
        openedPlaylistTracks = library.openedPlaylistTracks()
        playlistStatus = "SCAN ALL: \(res.steps) steps, \(res.namesTotal) total names"
        isScanning = false
    }

    func selectPlaylist(_ playlist: STCachedPlaylist) {
        let res = library.activatePlaylist(label: playlist.label)
        playlistStatus = res.success ? nil : res.message
    }

    func selectTrack(_ label: String) {
        let res = library.activateTrack(label: label)
        trackStatus = res.success ? nil : res.message
    }

    func clearOpenedTracks() {
        library.clearOpenedPlaylistTracks()
        openedPlaylistTracks = []
        trackStatus = nil
    }

    func clearPlaylistStatus() {
        playlistStatus = nil
    }

    func clearTrackStatus() {
        trackStatus = nil
    }
}
