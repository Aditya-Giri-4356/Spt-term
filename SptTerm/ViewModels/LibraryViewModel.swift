import Combine
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var albums: [Album] = []
    @Published private(set) var artists: [Artist] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var likedTracks: [Track] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let library: LibraryServiceProtocol

    init(library: LibraryServiceProtocol) {
        self.library = library
    }

    func load() async {
        isLoading = true
        errorMessage = nil
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
}
