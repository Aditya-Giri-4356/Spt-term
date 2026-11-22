import SwiftUI

struct PlayerShellContent: View {
    @ObservedObject var viewModel: HomeViewModel
    let namespace: Namespace.ID
    @Binding var isNowPlayingExpanded: Bool
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme
    @Environment(\.artworkProvider) private var artworkProvider

    init(
        viewModel: HomeViewModel,
        namespace: Namespace.ID,
        isNowPlayingExpanded: Binding<Bool>,
        path: Binding<[AppRoute]> = .constant([])
    ) {
        self.viewModel = viewModel
        self.namespace = namespace
        self._isNowPlayingExpanded = isNowPlayingExpanded
        self._path = path
    }

    var body: some View {
        HomeDestination(
            viewModel: viewModel,
            namespace: namespace,
            isNowPlayingExpanded: $isNowPlayingExpanded,
            path: $path
        )
    }
}

struct HomeDestination: View {
    @ObservedObject var viewModel: HomeViewModel
    let namespace: Namespace.ID
    @Binding var isNowPlayingExpanded: Bool
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme
    @Environment(\.artworkProvider) private var artworkProvider

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: TermSpace.md) {
                    TerminalHeader(subtitle: "Home")
                    PlayTabLyricsView()

                    if viewModel.isLoading {
                        HomeLoadingState()
                    } else if let error = viewModel.errorMessage {
                        HomeErrorState(message: error)
                    } else {
                        HomeBodyContent(
                            viewModel: viewModel,
                            isNowPlayingExpanded: $isNowPlayingExpanded,
                            path: $path
                        )
                    }
                }
                .padding(.horizontal, TermSpace.gutter)
                .padding(.top, TermSpace.sm)
                .padding(.bottom, 140)
            }
        }
        .task { await viewModel.load() }
    }
}

struct HomeBodyContent: View {
    let viewModel: HomeViewModel
    @Binding var isNowPlayingExpanded: Bool
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme
    @Environment(\.artworkProvider) private var artworkProvider

    var body: some View {
        VStack(spacing: TermSpace.md) {
            ForEach(viewModel.sections) { section in
                HomeSectionBlock(
                    section: section,
                    viewModel: viewModel,
                    isNowPlayingExpanded: $isNowPlayingExpanded,
                    path: $path
                )
            }
        }
    }
}

struct HomeSectionBlock: View {
    let section: HomeSection
    let viewModel: HomeViewModel
    @Binding var isNowPlayingExpanded: Bool
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme
    @Environment(\.artworkProvider) private var artworkProvider

    var body: some View {
        VStack(alignment: .leading, spacing: TermSpace.xs) {
            SectionHeader(title: section.title, trailing: section.subtitle)

            switch section.kind {
            case .hero:
                HomeHeroShelf(section: section, viewModel: viewModel, path: $path)
            case .recentlyPlayed:
                HomeTrackShelf(section: section, viewModel: viewModel)
            case .newReleases:
                HomeAlbumShelf(section: section, viewModel: viewModel, path: $path)
            case .playlists:
                HomePlaylistShelf(section: section, viewModel: viewModel, path: $path)
            case .artists:
                HomeArtistShelf(section: section, viewModel: viewModel, path: $path)
            case .systemLog:
                HomeSystemLogPanel(section: section, viewModel: viewModel)
            }
        }
    }
}

struct HomeHeroShelf: View {
    let section: HomeSection
    let viewModel: HomeViewModel
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme
    @Environment(\.artworkProvider) private var artworkProvider

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TermSpace.sm) {
                ForEach(section.albumIDs, id: \.self) { id in
                    if let album = viewModel.albumsByID[id] {
                        HomeTile(
                            title: album.title,
                            subtitle: album.artistName,
                            artwork: artworkProvider.artwork(for: album)
                        ) {
                            path.append(.album(id: album.id))
                        }
                        .frame(width: 150)
                    }
                }
            }
        }
        .environmentObject(theme)
    }
}

struct HomeTrackShelf: View {
    let section: HomeSection
    let viewModel: HomeViewModel

    @EnvironmentObject private var theme: TerminalTheme
    @Environment(\.artworkProvider) private var artworkProvider

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TermSpace.sm) {
                ForEach(section.trackIDs, id: \.self) { id in
                    if let track = viewModel.tracksByID[id] {
                        HomeTile(
                            title: track.title,
                            subtitle: track.artistName,
                            artwork: artworkProvider.artwork(for: track)
                        ) {
                            viewModel.play(track: track)
                        }
                        .frame(width: 130)
                    }
                }
            }
        }
        .environmentObject(theme)
    }
}

struct HomeAlbumShelf: View {
    let section: HomeSection
    let viewModel: HomeViewModel
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme
    @Environment(\.artworkProvider) private var artworkProvider

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TermSpace.sm) {
                ForEach(section.albumIDs, id: \.self) { id in
                    if let album = viewModel.albumsByID[id] {
                        HomeTile(
                            title: album.title,
                            subtitle: "\(album.year) • \(album.genre)",
                            artwork: artworkProvider.artwork(for: album)
                        ) {
                            path.append(.album(id: album.id))
                        }
                        .frame(width: 130)
                    }
                }
            }
        }
        .environmentObject(theme)
    }
}

struct HomePlaylistShelf: View {
    let section: HomeSection
    let viewModel: HomeViewModel
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme
    @Environment(\.artworkProvider) private var artworkProvider

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TermSpace.sm) {
                ForEach(section.playlistIDs, id: \.self) { id in
                    if let playlist = viewModel.playlistsByID[id] {
                        HomeTile(
                            title: playlist.name,
                            subtitle: playlist.owner,
                            artwork: artworkProvider.artwork(seed: "playlist|\(playlist.id)", columns: 16)
                        ) {
                            path.append(.playlist(id: playlist.id))
                        }
                        .frame(width: 130)
                    }
                }
            }
        }
        .environmentObject(theme)
    }
}

struct HomeArtistShelf: View {
    let section: HomeSection
    let viewModel: HomeViewModel
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TermSpace.sm) {
                ForEach(section.artistIDs, id: \.self) { id in
                    if let artist = viewModel.artistsByID[id] {
                        HomeArtistTile(artist: artist, path: $path)
                    }
                }
            }
        }
        .environmentObject(theme)
    }
}

struct HomeArtistTile: View {
    let artist: Artist
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        Button {
            path.append(.artist(id: artist.id))
        } label: {
            ASCIIPanel(title: nil, contentPadding: TermSpace.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name)
                        .termType(TermType.bodySM, color: theme.palette.accent)
                        .lineLimit(1)
                    Text("\(artist.trackCount) tracks")
                        .termType(TermType.telemetryTight, color: theme.palette.textMuted)
                    Text("pop \(artist.popularityLabel)")
                        .termType(TermType.telemetryTight, color: theme.palette.textSecondary)
                }
            }
            .frame(width: 120)
        }
        .buttonStyle(TermPressStyle())
        .accessibilityLabel(Text(artist.name))
    }
}

struct HomeSystemLogPanel: View {
    let section: HomeSection
    let viewModel: HomeViewModel

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        ASCIIPanel(title: "SYSTEM LOG", trailing: "daemon") {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.subtitle ?? "")
                    .termType(TermType.telemetry, color: theme.palette.textSecondary)
                ForEach(section.trackIDs, id: \.self) { id in
                    if let track = viewModel.tracksByID[id] {
                        Text("> buffered \(track.title) (\(track.durationLabel))")
                            .termType(TermType.telemetryTight, color: theme.palette.textMuted)
                            .lineLimit(1)
                    }
                }
            }
        }
        .environmentObject(theme)
    }
}

struct HomeLoadingState: View {
    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        ASCIIPanel(title: "HOME", trailing: "loading") {
            Text("BUFFERING HOME SHELF…")
                .termType(TermType.bodySM, color: theme.palette.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .environmentObject(theme)
    }
}

struct HomeErrorState: View {
    let message: String

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        ASCIIPanel(title: "HOME", trailing: "error") {
            Text(message)
                .termType(TermType.bodySM, color: theme.palette.amber)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .environmentObject(theme)
    }
}

struct HomeTile: View {
    let title: String
    let subtitle: String
    let artwork: TrackArtwork
    let action: () -> Void

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        Button(action: action) {
            ASCIIPanel(title: nil, contentPadding: TermSpace.xs) {
                VStack(alignment: .leading, spacing: TermSpace.xs) {
                    ASCIIArtworkView(matrix: artwork.matrix, fontSize: 5, tint: artwork.accent)
                        .frame(height: 72)
                    Text(title)
                        .termType(TermType.bodySM, color: theme.palette.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .termType(TermType.telemetryTight, color: theme.palette.textMuted)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(TermPressStyle())
        .accessibilityLabel(Text(title))
    }
}

struct PlayTabLyricsView: View {
    @Environment(\.playerService) private var playerService
    @EnvironmentObject private var theme: TerminalTheme
    @State private var lyrics: [LyricsLine] = []

    var body: some View {
        if STLyricsService.shared.isEnabled, let track = playerService.state.currentTrack, !lyrics.isEmpty {
            let progress = playerService.state.progress
            let currentIndex = lyrics.lastIndex(where: { $0.time <= progress }) ?? -1
            let prevText = (currentIndex > 0 && currentIndex < lyrics.count) ? linesText(at: currentIndex - 1) : ""
            let currText = (currentIndex >= 0 && currentIndex < lyrics.count) ? linesText(at: currentIndex) : linesText(at: 0)
            let nextText = (currentIndex >= 0 && currentIndex + 1 < lyrics.count) ? linesText(at: currentIndex + 1) : linesText(at: 1)

            ASCIIPanel(title: "LYRICS :: synced", trailing: "[LRCLIB]") {
                VStack(alignment: .leading, spacing: 3) {
                    if !prevText.isEmpty {
                        Text("  " + prevText)
                            .termType(TermType.bodySM, color: theme.palette.textMuted)
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Text("> " + currText)
                            .termType(TermType.bodySM, color: theme.palette.accent)
                            .lineLimit(1)
                        BlinkingCursor(width: 6, height: 12)
                    }
                    if !nextText.isEmpty {
                        Text("  " + nextText)
                            .termType(TermType.bodySM, color: theme.palette.textMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task(id: track.id) {
                await loadLyrics(for: track)
            }
        } else {
            EmptyView()
                .task(id: playerService.state.currentTrack?.id) {
                    guard STLyricsService.shared.isEnabled else { return }
                    if let track = playerService.state.currentTrack {
                        await loadLyrics(for: track)
                    } else {
                        lyrics = []
                    }
                }
        }
    }

    private func linesText(at index: Int) -> String {
        guard index >= 0 && index < lyrics.count else { return "" }
        return lyrics[index].text
    }

    @MainActor
    private func loadLyrics(for track: Track) async {
        guard STLyricsService.shared.isEnabled else {
            lyrics = []
            return
        }
        if let fetched = await STLyricsService.shared.fetchLyrics(for: track) {
            lyrics = fetched
        } else {
            lyrics = []
        }
    }
}
