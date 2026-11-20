import SwiftUI

struct RootView: View {
    @Environment(\.playerService) private var playerService
    @Environment(\.libraryService) private var libraryService
    @Environment(\.artworkProvider) private var artworkProvider
    @Environment(\.audioEffectsService) private var audioEffectsService

    var body: some View {
        RootShellView(
            playerService: playerService,
            libraryService: libraryService,
            artworkProvider: artworkProvider,
            audioEffectsService: audioEffectsService
        )
    }
}

struct RootShellView: View {
    let playerService: PlayerServiceProtocol
    let libraryService: LibraryServiceProtocol
    let artworkProvider: ArtworkProviding
    let audioEffectsService: AudioEffectsServiceProtocol

    @EnvironmentObject private var theme: TerminalTheme

    @AppStorage("root.selectedTab") private var selectedTabRaw: String = TabItem.player.rawValue
    @State private var isNowPlayingExpanded: Bool = false

    @State private var playerPath: [AppRoute] = []
    @State private var libraryPath: [AppRoute] = []
    @State private var execPath: [AppRoute] = []
    @State private var themePath: [AppRoute] = []

    @StateObject private var nowPlayingViewModel: NowPlayingViewModel
    @StateObject private var homeViewModel: HomeViewModel
    @StateObject private var libraryViewModel: LibraryViewModel

    @Namespace private var namespace

    init(
        playerService: PlayerServiceProtocol,
        libraryService: LibraryServiceProtocol,
        artworkProvider: ArtworkProviding,
        audioEffectsService: AudioEffectsServiceProtocol
    ) {
        self.playerService = playerService
        self.libraryService = libraryService
        self.artworkProvider = artworkProvider
        self.audioEffectsService = audioEffectsService

        _nowPlayingViewModel = StateObject(wrappedValue: NowPlayingViewModel(
            player: playerService,
            artworkProvider: artworkProvider
        ))
        _homeViewModel = StateObject(wrappedValue: HomeViewModel(
            library: libraryService,
            player: playerService
        ))
        _libraryViewModel = StateObject(wrappedValue: LibraryViewModel(
            library: libraryService
        ))
    }

    private var selectedTab: TabItem {
        get { TabItem(rawValue: selectedTabRaw) ?? .player }
        nonmutating set { selectedTabRaw = newValue.rawValue }
    }

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()

            // 1. Four tabs with one NavigationStack per tab
            tabContent

            // 2. Mini-player placed ABOVE the tab bar
            if !isNowPlayingExpanded {
                VStack(spacing: 0) {
                    Spacer()

                    if playerService.state.currentTrack != nil {
                        MiniPlayerView(
                            viewModel: nowPlayingViewModel,
                            isExpanded: $isNowPlayingExpanded,
                            namespace: namespace
                        )
                        .padding(.horizontal, TermSpace.sm)
                        .padding(.bottom, TermSpace.xs)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    TerminalTabBar(
                        selected: selectedTab,
                        onSelect: { tab in
                            selectedTab = tab
                            TermHaptic.tap()
                        }
                    )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 3. Now Playing full screen presented in same view hierarchy with shared namespace
            if isNowPlayingExpanded {
                NowPlayingView(
                    viewModel: nowPlayingViewModel,
                    isExpanded: $isNowPlayingExpanded,
                    namespace: namespace
                )
                .transition(.move(edge: .bottom))
                .zIndex(10)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isNowPlayingExpanded)
        .animation(.easeInOut(duration: 0.2), value: playerService.state.currentTrack)
        .environment(\.shellMetrics, ShellMetrics(theme: theme))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .player:
            NavigationStack(path: $playerPath) {
                PlayerShellContent(
                    viewModel: homeViewModel,
                    namespace: namespace,
                    isNowPlayingExpanded: $isNowPlayingExpanded,
                    path: $playerPath
                )
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route, path: $playerPath)
                }
            }
        case .library:
            NavigationStack(path: $libraryPath) {
                LibraryShellContent(
                    viewModel: libraryViewModel,
                    isNowPlayingExpanded: $isNowPlayingExpanded,
                    path: $libraryPath
                )
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route, path: $libraryPath)
                }
            }
        case .exec:
            NavigationStack(path: $execPath) {
                ExecPlaceholderView()
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(for: route, path: $execPath)
                    }
            }
        case .theme:
            NavigationStack(path: $themePath) {
                ThemePlaceholderView()
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(for: route, path: $themePath)
                    }
            }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute, path: Binding<[AppRoute]>) -> some View {
        switch route {
        case .album(let id):
            AlbumDetailView(
                albumID: id,
                library: libraryService,
                player: playerService,
                artworkProvider: artworkProvider
            )
        case .playlist(let id):
            PlaylistDetailView(
                playlistID: id,
                library: libraryService,
                player: playerService,
                artworkProvider: artworkProvider
            )
        case .artist(let id):
            ArtistDetailPlaceholder(artistID: id)
        case .search:
            SearchView(
                viewModel: SearchViewModel(library: libraryService),
                path: path
            )
        }
    }
}
