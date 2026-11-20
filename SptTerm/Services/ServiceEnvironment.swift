import SwiftUI

// MARK: - Environment keys

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

// MARK: - Injection helpers

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

// MARK: - Preview container

final class PreviewServices {
    let library: LibraryServiceProtocol = MockLibraryService()
    let player: PlayerServiceProtocol = MockPlayerService()
    let effects: AudioEffectsServiceProtocol = MockAudioEffectsService.ephemeral()
    let artwork: ArtworkProviding = MockArtworkService()
}

/// Preview container with theme + services pre-wired.
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
