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

private struct ServiceContainerKey: EnvironmentKey {
    static let defaultValue: STServiceContainer? = nil
}

extension EnvironmentValues {
    var serviceContainer: STServiceContainer? {
        get { self[ServiceContainerKey.self] }
        set { self[ServiceContainerKey.self] = newValue }
    }

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

/// Unified Environment holding services for SptTerm UI
@MainActor
final class ServiceEnvironment: ObservableObject {
    @Published var isAuthorized: Bool = false

    let player: PlayerServiceProtocol
    let library: LibraryServiceProtocol
    let auth: STAuthServiceProtocol
    let audioTweaks: AudioEffectsServiceProtocol
    let artwork: ArtworkProviding
    var legacyContainer: STServiceContainer?

    private var cancellables = Set<AnyCancellable>()

    init(
        player: PlayerServiceProtocol,
        library: LibraryServiceProtocol,
        auth: STAuthServiceProtocol,
        audioTweaks: AudioEffectsServiceProtocol,
        artwork: ArtworkProviding = MockArtworkService(),
        legacyContainer: STServiceContainer? = nil
    ) {
        self.player = player
        self.library = library
        self.auth = auth
        self.audioTweaks = audioTweaks
        self.artwork = artwork
        self.legacyContainer = legacyContainer
        self.isAuthorized = auth.isAuthorized

        auth.authorizedPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] authState in
                self?.isAuthorized = authState
            }
            .store(in: &cancellables)
    }

    func start() {
        if isAuthorized {
            #if canImport(SpotifyiOS)
            legacyContainer?.start()
            #endif
        }
    }

    func authorize() async throws {
        try await auth.authorize()
    }

    func signOut() {
        auth.signOut()
    }

    func handle(url: URL) -> Bool {
        auth.handle(url: url)
    }

    #if canImport(SpotifyiOS)
    static func forApp() -> ServiceEnvironment {
        let container = STServiceContainer()
        return ServiceEnvironment(
            player: container.player,
            library: container.library,
            auth: container.auth,
            audioTweaks: container.effects,
            artwork: container.artwork,
            legacyContainer: container
        )
    }
    #endif
}

protocol STSpotifyWebAPIClient: AnyObject {
    func currentUserProfile() async throws -> STUserProfileDTO
}

#if canImport(SpotifyiOS)
/// Live wiring. Held by `ServiceEnvironment` for the standalone app.
@MainActor
final class STServiceContainer: ObservableObject {
    @Published private(set) var isAuthorized = false

    let auth = STSpotifyAuth()
    private(set) lazy var api = STSpotifyWebAPI(auth: auth)

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
#else
final class STMockWebAPIClient: STSpotifyWebAPIClient {
    func currentUserProfile() async throws -> STUserProfileDTO {
        STUserProfileDTO(id: "spotify_tweak_session", display_name: "Spotify Client", product: "premium", email: nil)
    }
}

@MainActor
final class STServiceContainer: ObservableObject {
    @Published private(set) var isAuthorized = true
    let auth: STAuthServiceProtocol = MockAuthService(isAuthorized: true)
    let api: STSpotifyWebAPIClient? = STMockWebAPIClient()
}
#endif

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
