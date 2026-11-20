import SwiftUI

struct SearchShellContent: View {
    @StateObject private var viewModel: SearchViewModel
    @State private var path: [AppRoute] = []

    init(viewModel: SearchViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SearchContent(viewModel: viewModel, path: $path)
    }
}

struct SearchContent: View {
    @ObservedObject var viewModel: SearchViewModel
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme
    @Environment(\.artworkProvider) private var artworkProvider
    @Environment(\.playerService) private var player

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: TermSpace.md) {
                    TerminalHeader(subtitle: "Search")

                    SearchPromptSection(viewModel: viewModel)

                    SearchBodyContent(viewModel: viewModel, path: $path)
                }
                .padding(.horizontal, TermSpace.gutter)
                .padding(.top, TermSpace.sm)
                .padding(.bottom, 140)
            }
        }
        .background(theme.palette.background.ignoresSafeArea())
    }
}

struct SearchPromptSection: View {
    @ObservedObject var viewModel: SearchViewModel

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        ASCIIPanel(title: "QUERY :: stdin", trailing: "300ms debounce") {
            HStack(spacing: TermSpace.xs) {
                Text(">")
                    .termType(TermType.telemetry, color: theme.palette.cyan)
                TextField("query", text: $viewModel.query)
                    .termType(TermType.telemetry, color: theme.palette.accent)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                BlinkingCursor()
            }
        }
        .environmentObject(theme)
    }
}

struct SearchBodyContent: View {
    @ObservedObject var viewModel: SearchViewModel
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme
    @Environment(\.artworkProvider) private var artworkProvider
    @Environment(\.playerService) private var player

    var body: some View {
        VStack(spacing: TermSpace.md) {
            if viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty {
                SearchRecentQueriesSection(viewModel: viewModel)
            } else if viewModel.isSearching && viewModel.results == nil {
                SearchLoadingState()
            } else if let results = viewModel.results {
                if results.isEmpty {
                    SearchNoResultsState(query: viewModel.query)
                } else {
                    SearchResultsSections(
                        results: results,
                        path: $path,
                        artworkProvider: artworkProvider,
                        player: player
                    )
                }
            }
        }
    }
}

struct SearchRecentQueriesSection: View {
    @ObservedObject var viewModel: SearchViewModel

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: TermSpace.xs) {
            SectionHeader(title: "Recent Queries", trailing: viewModel.recentSearches.isEmpty ? nil : "clear")

            if viewModel.recentSearches.isEmpty {
                Text("NO RECENT QUERIES IN BUFFER")
                    .termType(TermType.bodySM, color: theme.palette.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(TermSpace.sm)
            } else {
                ASCIIPanel(title: nil, contentPadding: TermSpace.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.recentSearches, id: \.self) { term in
                            Button {
                                viewModel.query = term
                            } label: {
                                HStack {
                                    Text("└──")
                                        .termType(TermType.telemetryTight, color: theme.palette.textMuted)
                                    Text(term)
                                        .termType(TermType.bodySM, color: theme.palette.textPrimary)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(TermPressStyle())
                        }
                        Button {
                            viewModel.clearRecent()
                        } label: {
                            Text("[ clear buffer ]")
                                .termType(TermType.labelSM, color: theme.palette.textMuted)
                        }
                        .buttonStyle(TermPressStyle())
                    }
                }
            }
        }
        .environmentObject(theme)
    }
}

struct SearchLoadingState: View {
    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        ASCIIPanel(title: "SEARCH", trailing: "loading") {
            Text("QUERYING INDEX…")
                .termType(TermType.bodySM, color: theme.palette.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .environmentObject(theme)
    }
}

struct SearchNoResultsState: View {
    let query: String

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        ASCIIPanel(title: "SEARCH", trailing: "empty") {
            Text("NO MATCHES FOR \"\(query)\"")
                .termType(TermType.bodySM, color: theme.palette.amber)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .environmentObject(theme)
    }
}

struct SearchResultsSections: View {
    let results: SearchResults
    @Binding var path: [AppRoute]
    let artworkProvider: ArtworkProviding
    let player: PlayerServiceProtocol

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: TermSpace.md) {
            if !results.tracks.isEmpty {
                SearchResultsTracksSection(tracks: results.tracks, player: player)
            }
            if !results.albums.isEmpty {
                SearchResultsAlbumsSection(albums: results.albums, artworkProvider: artworkProvider, path: $path)
            }
            if !results.artists.isEmpty {
                SearchResultsArtistsSection(artists: results.artists, path: $path)
            }
            if !results.playlists.isEmpty {
                SearchResultsPlaylistsSection(playlists: results.playlists, path: $path)
            }
        }
    }
}

struct SearchResultsTracksSection: View {
    let tracks: [Track]
    let player: PlayerServiceProtocol

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: TermSpace.xs) {
            SectionHeader(title: "Tracks", trailing: "\(tracks.count)")
            ASCIIPanel(title: nil, contentPadding: TermSpace.xs) {
                VStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { _, track in
                        SearchResultTrackRow(track: track, player: player)
                    }
                }
            }
        }
        .environmentObject(theme)
    }
}

struct SearchResultTrackRow: View {
    let track: Track
    let player: PlayerServiceProtocol

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        Button {
            player.play(track, in: [])
        } label: {
            HStack {
                Text("♫")
                    .termType(TermType.glyphSM, color: theme.palette.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .termType(TermType.bodySM, color: theme.palette.textPrimary)
                        .lineLimit(1)
                    Text(track.artistName)
                        .termType(TermType.telemetryTight, color: theme.palette.textMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(track.durationLabel)
                    .termType(TermType.telemetryTight, color: theme.palette.textSecondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(TermPressStyle())
        .accessibilityLabel(Text(track.title))
    }
}

struct SearchResultsAlbumsSection: View {
    let albums: [Album]
    let artworkProvider: ArtworkProviding
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: TermSpace.xs) {
            SectionHeader(title: "Albums", trailing: "\(albums.count)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TermSpace.sm) {
                    ForEach(Array(albums.enumerated()), id: \.element.id) { _, album in
                        SearchResultAlbumTile(album: album, artworkProvider: artworkProvider, path: $path)
                    }
                }
            }
        }
        .environmentObject(theme)
    }
}

struct SearchResultAlbumTile: View {
    let album: Album
    let artworkProvider: ArtworkProviding
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme

    var artwork: TrackArtwork { artworkProvider.artwork(for: album) }

    var body: some View {
        Button {
            path.append(.album(id: album.id))
        } label: {
            ASCIIPanel(title: nil, contentPadding: TermSpace.xs) {
                VStack(alignment: .leading, spacing: TermSpace.xs) {
                    ASCIIArtworkView(matrix: artwork.matrix, fontSize: 5, tint: artwork.accent)
                        .frame(width: 96, height: 72)
                    Text(album.title)
                        .termType(TermType.bodySM, color: theme.palette.textPrimary)
                        .lineLimit(1)
                    Text(album.artistName)
                        .termType(TermType.telemetryTight, color: theme.palette.textMuted)
                        .lineLimit(1)
                }
            }
            .frame(width: 110)
        }
        .buttonStyle(TermPressStyle())
        .accessibilityLabel(Text(album.title))
    }
}

struct SearchResultsArtistsSection: View {
    let artists: [Artist]
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: TermSpace.xs) {
            SectionHeader(title: "Artists", trailing: "\(artists.count)")
            ASCIIPanel(title: nil, contentPadding: TermSpace.xs) {
                VStack(spacing: 0) {
                    ForEach(Array(artists.enumerated()), id: \.element.id) { _, artist in
                        SearchResultArtistRow(artist: artist, path: $path)
                    }
                }
            }
        }
        .environmentObject(theme)
    }
}

struct SearchResultArtistRow: View {
    let artist: Artist
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        Button {
            path.append(.artist(id: artist.id))
        } label: {
            HStack {
                Text(" ")
                    .termType(TermType.glyphSM, color: theme.palette.accent)
                Text(artist.name)
                    .termType(TermType.bodySM, color: theme.palette.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("\(artist.trackCount) tracks")
                    .termType(TermType.telemetryTight, color: theme.palette.textMuted)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(TermPressStyle())
        .accessibilityLabel(Text(artist.name))
    }
}

struct SearchResultsPlaylistsSection: View {
    let playlists: [Playlist]
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: TermSpace.xs) {
            SectionHeader(title: "Playlists", trailing: "\(playlists.count)")
            ASCIIPanel(title: nil, contentPadding: TermSpace.xs) {
                VStack(spacing: 0) {
                    ForEach(Array(playlists.enumerated()), id: \.element.id) { _, playlist in
                        SearchResultPlaylistRow(playlist: playlist, path: $path)
                    }
                }
            }
        }
        .environmentObject(theme)
    }
}

struct SearchResultPlaylistRow: View {
    let playlist: Playlist
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        Button {
            path.append(.playlist(id: playlist.id))
        } label: {
            HStack {
                Text("♫")
                    .termType(TermType.glyphSM, color: theme.palette.accent)
                Text(playlist.name)
                    .termType(TermType.bodySM, color: theme.palette.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("\(playlist.trackIDs.count) tracks")
                    .termType(TermType.telemetryTight, color: theme.palette.textMuted)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(TermPressStyle())
        .accessibilityLabel(Text(playlist.name))
    }
}
