import SwiftUI

struct AlbumDetailView: View {
    let albumID: String
    let library: LibraryServiceProtocol
    let player: PlayerServiceProtocol
    let artworkProvider: ArtworkProviding

    @StateObject private var viewModel: AlbumDetailViewModel
    @EnvironmentObject private var theme: TerminalTheme

    init(albumID: String, library: LibraryServiceProtocol, player: PlayerServiceProtocol, artworkProvider: ArtworkProviding) {
        self.albumID = albumID
        self.library = library
        self.player = player
        self.artworkProvider = artworkProvider
        _viewModel = StateObject(wrappedValue: AlbumDetailViewModel(library: library, player: player, albumID: albumID))
    }

    var body: some View {
        CollectionDetailView(
            title: viewModel.album?.title ?? "Album",
            subtitle: viewModel.album.map { "\($0.artistName) • \($0.year) • \($0.genre)" } ?? "",
            artwork: viewModel.album.map { artworkProvider.artwork(for: $0) } ?? artworkProvider.artwork(seed: "album|\(albumID)", columns: 16),
            tracks: viewModel.tracks,
            player: player,
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.errorMessage,
            onPlayAll: { viewModel.playAll() },
            onShuffle: { viewModel.shuffle() },
            onTrackTap: { viewModel.play(track: $0) },
            onTrackContext: { viewModel.addToQueue(track: $0) }
        )
        .navigationTitle(viewModel.album?.title ?? "Album")
        .task { await viewModel.load() }
    }
}

struct AlbumDetailView_Previews: PreviewProvider {
    static var previews: some View {
        TerminalAppPreview {
            AlbumDetailPreview()
        }
    }

    private struct AlbumDetailPreview: View {
        let player: PlayerServiceProtocol = MockPlayerService()
        var body: some View {
            AlbumDetailView(
                albumID: "a1",
                library: PreviewServices().library,
                player: player,
                artworkProvider: MockArtworkService()
            )
        }
    }
}
