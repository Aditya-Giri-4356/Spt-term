import Combine
import SwiftUI

private struct LibraryServiceKey: EnvironmentKey {
    static let defaultValue: LibraryServiceProtocol = MockLibraryService()
}

private struct PlayerServiceKey: EnvironmentKey {
    static let defaultValue: PlayerServiceProtocol = MockPlayerService()
}

private struct AudioEffectsServiceKey: EnvironmentKey {
    static let defaultValue: AudioEffectsServiceProtocol = MockAudioEffectsService()
}

private struct ArtworkProviderKey: EnvironmentKey {
    static let defaultValue: ArtworkProviding = MockArtworkService()
}

extension EnvironmentValues {
    var libraryService: LibraryServiceProtocol {
        get { self[LibraryServiceKey.self] }
        set { self[LibraryServiceKey.self] = newValue }
    }

    var playerService: PlayerServiceProtocol {
        get { self[PlayerServiceKey.self] }
        set { self[PlayerServiceKey.self] = newValue }
    }

    var audioEffectsService: AudioEffectsServiceProtocol {
        get { self[AudioEffectsServiceKey.self] }
        set { self[AudioEffectsServiceKey.self] = newValue }
    }

    var artworkProvider: ArtworkProviding {
        get { self[ArtworkProviderKey.self] }
        set { self[ArtworkProviderKey.self] = newValue }
    }
}

extension View {
    func libraryService(_ service: LibraryServiceProtocol) -> some View {
        environment(\.libraryService, service)
    }

    func playerService(_ service: PlayerServiceProtocol) -> some View {
        environment(\.playerService, service)
    }

    func audioEffectsService(_ service: AudioEffectsServiceProtocol) -> some View {
        environment(\.audioEffectsService, service)
    }

    func artworkProvider(_ provider: ArtworkProviding) -> some View {
        environment(\.artworkProvider, provider)
    }

    func injectMockServices(_ services: PreviewServices = PreviewServices()) -> some View {
        self
            .environment(\.libraryService, services.library)
            .environment(\.playerService, services.player)
            .environment(\.audioEffectsService, services.effects)
            .environment(\.artworkProvider, services.artwork)
    }
}

/// Live wiring. Held by `STRootGate` for the app's lifetime.
@MainActor
final class STServiceContainer: ObservableObject {
    @Published private(set) var isAuthorized = false

    let auth = STSpotifyAuth()
    private lazy var api = STSpotifyWebAPI(auth: auth)

    private(set) lazy var player: PlayerServiceProtocol =
        STRemotePlayerService(auth: auth, webAPI: api)
    private(set) lazy var library: LibraryServiceProtocol =
        STWebLibraryService(api: api)
    private(set) lazy var artwork: ArtworkProviding =
        STRemoteArtworkService(remote: { [weak self] in self?.remotePlayer?.imageRemote })
    let effects: AudioEffectsServiceProtocol = STPresetAudioEffects()

    var remotePlayer: STRemotePlayerService? { player as? STRemotePlayerService }

    private var cancellables = Set<AnyCancellable>()

    init() {
        auth.authorizedPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] authorized in
                self?.isAuthorized = authorized
                if authorized {
                    (self?.player as? STRemotePlayerService)?.connect()
                }
            }
            .store(in: &cancellables)
    }

    func start() {
        guard isAuthorized else { return }
        (player as? STRemotePlayerService)?.connect()
    }
}

final class PreviewServices {
    let library: LibraryServiceProtocol = MockLibraryService()
    let player: PlayerServiceProtocol = MockPlayerService()
    let effects: AudioEffectsServiceProtocol = MockAudioEffectsService.ephemeral()
    let artwork: ArtworkProviding = MockArtworkService()
}

struct TerminalAppPreview<Content: View>: View {
    @StateObject private var theme: TerminalTheme
    @State private var services = PreviewServices()
    private let content: Content

    init(themeID: String = ThemeCatalog.defaultID, @ViewBuilder content: () -> Content) {
        _theme = StateObject(wrappedValue: TerminalTheme.preview(themeID: themeID))
        self.content = content()
    }

    var body: some View {
        content
            .background(theme.palette.background.ignoresSafeArea())
            .foregroundColor(theme.palette.textPrimary)
            .environmentObject(theme)
            .environment(\.libraryService, services.library)
            .environment(\.playerService, services.player)
            .environment(\.audioEffectsService, services.effects)
            .environment(\.artworkProvider, services.artwork)
            .preferredColorScheme(theme.palette.isLight ? .light : .dark)
    }
}
