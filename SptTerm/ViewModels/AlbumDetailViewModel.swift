import Combine
import SwiftUI

@MainActor
final class AlbumDetailViewModel: ObservableObject {
    @Published private(set) var album: Album?
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let player: PlayerServiceProtocol
    private let library: LibraryServiceProtocol
    private let albumID: String

    init(library: LibraryServiceProtocol, player: PlayerServiceProtocol, albumID: String) {
        self.library = library
        self.player = player
        self.albumID = albumID
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let albumTask = library.fetchAlbum(id: albumID)
            async let tracksTask = library.fetchTracks(forAlbumID: albumID)
            let (album, tracks) = try await (albumTask, tracksTask)
            self.album = album
            self.tracks = tracks
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func playAll() {
        guard let first = tracks.first else { return }
        player.play(first, in: tracks)
    }

    func shuffle() {
        guard let first = tracks.first else { return }
        player.play(first, in: tracks.shuffled())
        if !player.state.isShuffled { player.toggleShuffle() }
    }

    func play(track: Track) {
        player.play(track, in: tracks)
    }

    func addToQueue(track: Track) {
        player.enqueue(track)
        TermHaptic.tap()
    }
}
