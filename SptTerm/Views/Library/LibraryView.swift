import SwiftUI

enum LibraryMode: String, CaseIterable {
    case list
    case grid
}

enum LibraryFilter: String, CaseIterable {
    case all
    case albums
    case artists
    case playlists
    case liked

    var label: String {
        switch self {
        case .all: return "all"
        case .albums: return "albums"
        case .artists: return "artists"
        case .playlists: return "playlists"
        case .liked: return "liked"
        }
    }
}

enum LibrarySort: String, CaseIterable {
    case recent
    case name

    var label: String { rawValue }
}

struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel
    @Binding var isNowPlayingExpanded: Bool
    @Binding var path: [AppRoute]

    @AppStorage("library.mode") private var modeRaw: String = LibraryMode.list.rawValue
    @AppStorage("library.filter") private var filterRaw: String = LibraryFilter.all.rawValue
    @AppStorage("library.sort") private var sortRaw: String = LibrarySort.recent.rawValue

    @EnvironmentObject private var theme: TerminalTheme
    @Environment(\.artworkProvider) private var artworkProvider
    @Environment(\.playerService) private var player

    @State private var expandedGroups: Set<String> = ["playlists", "albums", "artists", "liked"]

    init(
        viewModel: LibraryViewModel,
        isNowPlayingExpanded: Binding<Bool> = .constant(false),
        path: Binding<[AppRoute]> = .constant([])
    ) {
        self.viewModel = viewModel
        self._isNowPlayingExpanded = isNowPlayingExpanded
        self._path = path
    }

    private var mode: LibraryMode { LibraryMode(rawValue: modeRaw) ?? .list }
    private var filter: LibraryFilter { LibraryFilter(rawValue: filterRaw) ?? .all }
    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .recent }

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: TermSpace.md) {
                    TerminalHeader(subtitle: "Library")
                    telemetryPanel
                    filterBar
                    modeSortBar
                    if viewModel.isLoading {
                        loadingState
                    } else if let error = viewModel.errorMessage {
                        errorState(error)
                    } else if mode == .list {
                        listView
                    } else {
                        gridView
                    }
                }
                .padding(.horizontal, TermSpace.gutter)
                .padding(.top, TermSpace.sm)
                .padding(.bottom, 140)
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - Telemetry

    private var telemetryPanel: some View {
        ASCIIPanel(title: "FS :: /home/user/spotify_library", trailing: "[v2.4-stable]") {
            VStack(spacing: TermSpace.xs) {
                HStack(spacing: TermSpace.xs) {
                    StatusPill(text: "DISK: 18.4GB/64GB", tone: .accent)
                    StatusPill(text: "TRACKS: \(viewModel.likedTracks.count + viewModel.albums.reduce(0) { $0 + $1.trackIDs.count })", tone: .accent)
                    StatusPill(text: "SYNC: OK", tone: .cyan, filled: false)
                }
                ASCIIProgressBar(progress: 0.2875, width: 34)
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TermSpace.xs) {
                ForEach(LibraryFilter.allCases, id: \.self) { f in
                    Button {
                        filterRaw = f.rawValue
                        TermHaptic.tap()
                    } label: {
                        Text("[--\(f.label)]")
                            .termType(TermType.labelSM, color: filter == f ? theme.palette.onAccent : theme.palette.accent)
                            .padding(.horizontal, TermSpace.sm)
                            .padding(.vertical, 6)
                            .background(filter == f ? theme.palette.accent : theme.palette.background)
                            .overlay(Rectangle().strokeBorder(theme.palette.accent, lineWidth: 1))
                    }
                    .buttonStyle(TermPressStyle())
                }
                Button {
                    sortRaw = (sort == .recent ? LibrarySort.name : LibrarySort.recent).rawValue
                    TermHaptic.tap()
                } label: {
                    Text("[--sort:\(sort.label)]")
                        .termType(TermType.labelSM, color: theme.palette.accent)
                        .padding(.horizontal, TermSpace.sm)
                        .padding(.vertical, 6)
                        .background(theme.palette.background)
                        .overlay(Rectangle().strokeBorder(theme.palette.accentDeep, lineWidth: 1))
                }
                .buttonStyle(TermPressStyle())
            }
        }
    }

    // MARK: - Mode / sort

    private var modeSortBar: some View {
        HStack {
            BracketButton(
                title: mode == .list ? "Switch to GRID" : "Switch to LIST",
                glyph: "⇅",
                variant: .quiet
            ) {
                modeRaw = (mode == .list ? LibraryMode.grid : LibraryMode.list).rawValue
                TermHaptic.tap()
            }
            Spacer()
            Text("mode: \(mode.rawValue) • filter: \(filter.label)")
                .termType(TermType.telemetryTight, color: theme.palette.textMuted)
        }
    }

    // MARK: - List view

    private var listView: some View {
        VStack(spacing: TermSpace.sm) {
            if filter == .all || filter == .playlists {
                groupContainer(id: "playlists", title: "/Playlists", count: viewModel.playlists.count) {
                    ForEach(sortedPlaylists) { playlist in
                        LibraryRow(
                            glyph: "♫",
                            title: playlist.name,
                            subtitle: playlist.owner,
                            trailing: "\(playlist.trackIDs.count) tracks"
                        ) {
                            path.append(.playlist(id: playlist.id))
                        }
                    }
                }
            }
            if filter == .all || filter == .albums {
                groupContainer(id: "albums", title: "/Albums", count: viewModel.albums.count) {
                    ForEach(sortedAlbums) { album in
                        LibraryRow(
                            glyph: " ",
                            title: album.title,
                            subtitle: album.artistName,
                            trailing: "\(album.year)"
                        ) {
                            path.append(.album(id: album.id))
                        }
                    }
                }
            }
            if filter == .all || filter == .artists {
                groupContainer(id: "artists", title: "/Artists", count: viewModel.artists.count) {
                    ForEach(sortedArtists) { artist in
                        LibraryRow(
                            glyph: " ",
                            title: artist.name,
                            subtitle: "\(artist.trackCount) tracks",
                            trailing: artist.popularityLabel
                        ) {
                            path.append(.artist(id: artist.id))
                        }
                    }
                }
            }
            if filter == .all || filter == .liked {
                groupContainer(id: "liked", title: "/Liked_Songs", count: viewModel.likedTracks.count) {
                    ForEach(sortedLiked) { track in
                        LibraryRow(
                            glyph: "★",
                            title: track.title,
                            subtitle: track.artistName,
                            trailing: track.durationLabel
                        ) {
                            player.play(track, in: viewModel.likedTracks)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Grid view

    private var gridView: some View {
        let columns = [GridItem(.flexible(), spacing: TermSpace.sm), GridItem(.flexible(), spacing: TermSpace.sm)]
        return LazyVGrid(columns: columns, spacing: TermSpace.sm) {
            ForEach(gridItems) { item in
                GridTile(title: item.title, subtitle: item.subtitle, artwork: item.artwork) {
                    if let route = item.route { path.append(route) }
                    else if let track = item.track {
                        player.play(track, in: [track])
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var sortedAlbums: [Album] {
        switch sort {
        case .recent: return viewModel.albums.sorted { $0.year > $1.year }
        case .name: return viewModel.albums.sorted { $0.title < $1.title }
        }
    }

    private var sortedArtists: [Artist] {
        switch sort {
        case .recent: return viewModel.artists.sorted { $0.popularity > $1.popularity }
        case .name: return viewModel.artists.sorted { $0.name < $1.name }
        }
    }

    private var sortedPlaylists: [Playlist] {
        switch sort {
        case .recent: return viewModel.playlists.sorted { $0.saves > $1.saves }
        case .name: return viewModel.playlists.sorted { $0.name < $1.name }
        }
    }

    private var sortedLiked: [Track] {
        switch sort {
        case .recent: return viewModel.likedTracks
        case .name: return viewModel.likedTracks.sorted { $0.title < $1.title }
        }
    }

    private var filteredIsEmpty: Bool {
        switch filter {
        case .all:
            return viewModel.albums.isEmpty && viewModel.artists.isEmpty && viewModel.playlists.isEmpty && viewModel.likedTracks.isEmpty
        case .albums: return viewModel.albums.isEmpty
        case .artists: return viewModel.artists.isEmpty
        case .playlists: return viewModel.playlists.isEmpty
        case .liked: return viewModel.likedTracks.isEmpty
        }
    }

    private var gridItems: [GridItemModel] {
        switch filter {
        case .albums, .all:
            return sortedAlbums.map { GridItemModel(title: $0.title, subtitle: $0.artistName, artwork: artworkProvider.artwork(for: $0), route: .album(id: $0.id), track: nil) }
        case .playlists:
            return sortedPlaylists.map { GridItemModel(title: $0.name, subtitle: $0.owner, artwork: artworkProvider.artwork(seed: "playlist|\($0.id)", columns: 16), route: .playlist(id: $0.id), track: nil) }
        case .artists:
            return sortedArtists.map { GridItemModel(title: $0.name, subtitle: "\($0.trackCount) tracks", artwork: artworkProvider.artwork(seed: "artist|\($0.id)", columns: 16), route: .artist(id: $0.id), track: nil) }
        case .liked:
            return sortedLiked.map { GridItemModel(title: $0.title, subtitle: $0.artistName, artwork: artworkProvider.artwork(for: $0), route: nil, track: $0) }
        }
    }

    private func groupContainer<Content: View>(id: String, title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if expandedGroups.contains(id) { expandedGroups.remove(id) } else { expandedGroups.insert(id) }
                TermHaptic.tap()
            } label: {
                HStack(spacing: TermSpace.xs) {
                    Text(expandedGroups.contains(id) ? "├── [▼]" : "├── [▶]")
                        .termType(TermType.labelSM, color: theme.palette.accent)
                    Text(title)
                        .termType(TermType.labelMD, color: theme.palette.accent)
                    Spacer()
                    Text("[\(count)]")
                        .termType(TermType.labelSM, color: theme.palette.textMuted)
                }
                .padding(.horizontal, TermSpace.sm)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.palette.panelRaised)
                .overlay(Rectangle().strokeBorder(theme.palette.accentDeep, lineWidth: 1))
            }
            .buttonStyle(TermPressStyle())

            if expandedGroups.contains(id) {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.leading, TermSpace.sm)
            }
        }
    }

    private var loadingState: some View {
        ASCIIPanel(title: "LIBRARY", trailing: "loading") {
            Text("LOADING DIRECTORY TREE…")
                .termType(TermType.bodySM, color: theme.palette.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorState(_ message: String) -> some View {
        ASCIIPanel(title: "LIBRARY", trailing: "error") {
            Text(message)
                .termType(TermType.bodySM, color: theme.palette.amber)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        ASCIIPanel(title: "LIBRARY", trailing: "empty") {
            Text("NO ENTRIES IN ./lib — run sync to populate")
                .termType(TermType.bodySM, color: theme.palette.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func placeholderDestination(id: String) -> some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            ASCIIPanel(title: "DETAIL :: PLACEHOLDER", trailing: "stage d2") {
                Text("ARTIST DETAIL — \(id)")
            }
            .padding(TermSpace.md)
        }
        .environmentObject(theme)
    }
}

// MARK: - Row

struct LibraryRow: View {
    let glyph: String
    let title: String
    let subtitle: String
    let trailing: String
    let action: () -> Void

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: TermSpace.xs) {
                Text(glyph)
                    .termType(TermType.glyphSM, color: theme.palette.accent)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .termType(TermType.bodySM, color: theme.palette.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .termType(TermType.telemetryTight, color: theme.palette.textMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(trailing)
                    .termType(TermType.telemetryTight, color: theme.palette.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, TermSpace.sm)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.palette.background)
            .overlay(Rectangle().strokeBorder(theme.palette.hairline, lineWidth: 1))
        }
        .buttonStyle(TermPressStyle())
        .accessibilityLabel(Text(title))
    }
}

// MARK: - Grid tile

private struct GridItemModel: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let artwork: TrackArtwork
    let route: AppRoute?
    let track: Track?
}

struct GridTile: View {
    let title: String
    let subtitle: String
    let artwork: TrackArtwork
    let action: () -> Void

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: TermSpace.xs) {
                ASCIIArtworkView(matrix: artwork.matrix, fontSize: 5, tint: artwork.accent)
                    .frame(height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: TermRadius.tag))
                Text(title)
                    .termType(TermType.bodySM, color: theme.palette.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .termType(TermType.telemetryTight, color: theme.palette.textMuted)
                    .lineLimit(1)
            }
            .padding(TermSpace.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.palette.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(theme.palette.accentDeep, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(TermPressStyle())
        .accessibilityLabel(Text(title))
    }
}

struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        TerminalAppPreview {
            LibraryPreview()
        }
    }

    private struct LibraryPreview: View {
        @StateObject private var viewModel = LibraryViewModel(library: PreviewServices().library)

        var body: some View {
            LibraryView(viewModel: viewModel)
        }
    }
}
