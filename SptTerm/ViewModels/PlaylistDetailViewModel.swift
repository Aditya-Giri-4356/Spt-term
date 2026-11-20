import Combine
import SwiftUI

@MainActor
final class PlaylistDetailViewModel: ObservableObject {
    @Published private(set) var playlist: Playlist?
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let player: PlayerServiceProtocol
    private let library: LibraryServiceProtocol
    private let playlistID: String

    init(library: LibraryServiceProtocol, player: PlayerServiceProtocol, playlistID: String) {
        self.library = library
        self.player = player
        self.playlistID = playlistID
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let playlistTask = library.fetchPlaylist(id: playlistID)
            async let tracksTask = library.fetchTracks(forPlaylistID: playlistID)
            let (playlist, tracks) = try await (playlistTask, tracksTask)
            self.playlist = playlist
            self.tracks = tracks
        } catch {
            errorMessage = "FETCH_FAILED: \(error.localizedDescription)"
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
