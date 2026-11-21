import Combine
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var sections: [HomeSection] = []
    @Published private(set) var albumsByID: [String: Album] = [:]
    @Published private(set) var playlistsByID: [String: Playlist] = [:]
    @Published private(set) var artistsByID: [String: Artist] = [:]
    @Published private(set) var tracksByID: [String: Track] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let player: PlayerServiceProtocol
    let library: LibraryServiceProtocol

    init(library: LibraryServiceProtocol, player: PlayerServiceProtocol) {
        self.library = library
        self.player = player
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let sectionsTask = library.fetchHomeSections()
            async let albumsTask = library.fetchAlbums()
            async let playlistsTask = library.fetchPlaylists()
            async let artistsTask = library.fetchArtists()
            let (sections, albums, playlists, artists) = try await (sectionsTask, albumsTask, playlistsTask, artistsTask)
            self.sections = sections
            albumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
            playlistsByID = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, $0) })
            artistsByID = Dictionary(uniqueKeysWithValues: artists.map { ($0.id, $0) })
            let trackIDs = sections.flatMap { $0.trackIDs }
            if !trackIDs.isEmpty {
                let tracks = try await library.fetchTracks(ids: trackIDs)
                tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func play(track: Track) {
        player.play(track, in: [track])
    }

    func playAlbum(_ album: Album) async {
        do {
            let tracks = try await library.fetchTracks(forAlbumID: album.id)
            if let first = tracks.first { player.play(first, in: tracks) }
        } catch { }
    }

    func playPlaylist(_ playlist: Playlist) async {
        do {
            let tracks = try await library.fetchTracks(forPlaylistID: playlist.id)
            if let first = tracks.first { player.play(first, in: tracks) }
        } catch { }
    }
}
