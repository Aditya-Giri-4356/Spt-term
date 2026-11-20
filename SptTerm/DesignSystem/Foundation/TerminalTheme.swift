import SwiftUI
import Combine

/// Codable snapshot of everything the theme layer persists.
struct ThemeState: Codable, Equatable {
    var themeID: String
    var customAccentHex: String?
    var scanlines: Bool
    var crtBloom: Bool
}

protocol ThemeStorage {
    func load() -> ThemeState?
    func save(_ state: ThemeState)
}

/// Default persistence: one Codable blob in UserDefaults.
final class UserDefaultsThemeStorage: ThemeStorage {
    private let key = "sptterm.theme.state.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ThemeState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ThemeState.self, from: data)
    }

    func save(_ state: ThemeState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Non-persisting storage used by previews and tests.
final class EphemeralThemeStorage: ThemeStorage {
    private var state: ThemeState?

    init(state: ThemeState? = nil) {
        self.state = state
    }

    func load() -> ThemeState? { state }
    func save(_ state: ThemeState) { self.state = state }
}

/// Central runtime theme object. Accent color and CRT options can change at
/// any moment and every view reacts through the environment.
@MainActor
final class TerminalTheme: ObservableObject {
    @Published private(set) var themeID: String
    @Published private(set) var palette: ThemePalette
    @Published private(set) var customAccentHex: String?
    @Published private(set) var scanlinesEnabled: Bool
    @Published private(set) var bloomEnabled: Bool

    let catalog: [ThemeDefinition]
    private let storage: ThemeStorage

    init(storage: ThemeStorage = UserDefaultsThemeStorage()) {
        self.storage = storage
        self.catalog = ThemeCatalog.all

        let state = storage.load()
        let id = state?.themeID ?? ThemeCatalog.defaultID
        let definition = ThemeCatalog.definition(for: id)
        let accentHex = state?.customAccentHex

        self.themeID = definition.id
        self.customAccentHex = accentHex
        self.scanlinesEnabled = state?.scanlines ?? true
        self.bloomEnabled = state?.crtBloom ?? true
        self.palette = accentHex.map {
            ThemePalette.derived(accent: Color(termHex: $0), background: definition.background)
        } ?? definition.palette
    }

    var definition: ThemeDefinition {
        catalog.first { $0.id == themeID } ?? catalog[0]
    }

    var isCustomAccent: Bool { customAccentHex != nil }

    func select(_ id: String) {
        guard catalog.contains(where: { $0.id == id }) else { return }
        themeID = id
        customAccentHex = nil
        palette = ThemeCatalog.definition(for: id).palette
        persist()
    }

    func setCustomAccent(_ hex: String?) {
        customAccentHex = hex
        if let hex {
            palette = ThemePalette.derived(accent: Color(termHex: hex), background: definition.background)
        } else {
            palette = definition.palette
        }
        persist()
    }

    func setScanlines(_ enabled: Bool) {
        scanlinesEnabled = enabled
        persist()
    }

    func setBloom(_ enabled: Bool) {
        bloomEnabled = enabled
        persist()
    }

    private func persist() {
        storage.save(
            ThemeState(
                themeID: themeID,
                customAccentHex: customAccentHex,
                scanlines: scanlinesEnabled,
                crtBloom: bloomEnabled
            )
        )
    }
}

extension TerminalTheme {
    /// Shared instance for previews only; never touches UserDefaults.
    static let preview: TerminalTheme = {
        TerminalTheme(storage: EphemeralThemeStorage())
    }()

    static func preview(themeID: String) -> TerminalTheme {
        TerminalTheme(
            storage: EphemeralThemeStorage(
                state: ThemeState(
                    themeID: themeID,
                    customAccentHex: nil,
                    scanlines: false,
                    crtBloom: false
                )
            )
        )
    }
}
