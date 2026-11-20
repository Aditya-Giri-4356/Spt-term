import SwiftUI

struct PlaylistDetailView: View {
    let playlistID: String
    let library: LibraryServiceProtocol
    let player: PlayerServiceProtocol
    let artworkProvider: ArtworkProviding

    @StateObject private var viewModel: PlaylistDetailViewModel
    @EnvironmentObject private var theme: TerminalTheme

    init(playlistID: String, library: LibraryServiceProtocol, player: PlayerServiceProtocol, artworkProvider: ArtworkProviding) {
        self.playlistID = playlistID
        self.library = library
        self.player = player
        self.artworkProvider = artworkProvider
        _viewModel = StateObject(wrappedValue: PlaylistDetailViewModel(library: library, player: player, playlistID: playlistID))
    }

    var body: some View {
        CollectionDetailView(
            title: viewModel.playlist?.name ?? "Playlist",
            subtitle: viewModel.playlist.map { "\($0.owner) • \($0.savesLabel) saves • \($0.tag)" } ?? "",
            artwork: artworkProvider.artwork(seed: "playlist|\(playlistID)", columns: 16),
            tracks: viewModel.tracks,
            player: player,
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.errorMessage,
            onPlayAll: { viewModel.playAll() },
            onShuffle: { viewModel.shuffle() },
            onTrackTap: { viewModel.play(track: $0) },
            onTrackContext: { viewModel.addToQueue(track: $0) }
        )
        .navigationTitle(viewModel.playlist?.name ?? "Playlist")
        .task { await viewModel.load() }
    }
}

struct PlaylistDetailView_Previews: PreviewProvider {
    static var previews: some View {
        TerminalAppPreview {
            PlaylistDetailPreview()
        }
    }

    private struct PlaylistDetailPreview: View {
        let player: PlayerServiceProtocol = MockPlayerService()
        var body: some View {
            PlaylistDetailView(
                playlistID: "p1",
                library: PreviewServices().library,
                player: player,
                artworkProvider: MockArtworkService()
            )
        }
    }
}
