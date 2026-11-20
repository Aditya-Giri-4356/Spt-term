# Handoff

Done:
- (a) DesignSystem: tokens, 37 themes (hand-tuned + derived), 18 ASCII/TUI components, CRT scanline & phosphor glow modifiers, preview support.
- (b) Models + Services: Track, Album, Artist, Playlist, HomeSection, SearchResults, EQBand, AudioPreset, PlayerState, Route (AppRoute). Decoupled protocol architecture (Player, AudioEffects, Library, ArtworkProviding) + ServiceEnvironment injection + mock implementations.
- (c) NowPlaying + MiniPlayer: NowPlayingView with live spectrum, synchronized lyrics scroller, transport faders, metadata panels; MiniPlayerView with matched geometry and drag-down dismiss.
- (d1) Home + Library: HomeView with continue playing & bento shelves; LibraryView with list & grid modes, filter tags, sorting, file-tree telemetry.
- (d2) Search + Detail Screens: SearchView (300ms debounce, recent searches, categories), CollectionDetailView, AlbumDetailView, PlaylistDetailView, ArtistDetailPlaceholder.
- (h) Navigation Shell:
  - `@main` app entry (`SptTermApp.swift`) hosting `TerminalTheme` and `RootView`.
  - 4 working tabs: `[1:PLAY]`, `[2:LIB]`, `[3:EXEC]` (placeholder), `[4:THEME]` (placeholder) with `@AppStorage("root.selectedTab")` persistence.
  - Exactly one `NavigationStack` per tab (zero nested stacks) with `.navigationDestination(for: AppRoute.self)` routing to real detail screens and search.
  - Services injected exclusively via `ServiceEnvironment` protocols—no `Mock*` references in views and zero ViewModel instantiation inside `body`.
  - `MiniPlayerView` positioned directly ABOVE `TerminalTabBar`.
  - `NowPlayingView` presented in the same view hierarchy with shared matched-geometry `namespace` and no tap-catching overlays.
  - All navigation actions in Home and Library append to the active tab's navigation path (all dummy/no-op functions removed).

Still TODO:
- (e) Queue management sheet/screen.
- (f) Audio Tuning & Equalizer (10-band EQ + presets) replacing `ExecPlaceholderView`.
- (g) Settings & Themes Manager (`~/.spttermrc` config editor) replacing `ThemePlaceholderView`.
- (i) Project build files: Note that no `.xcodeproj` or `Package.swift` exists yet; Xcode project creation/linking was NOT verified.

Conventions: SwiftUI, iOS 16+, ObservableObject, SF Mono via TermFont, zero warnings with `-warnings-as-errors`, views depend only on protocols, files <= ~300 lines, TerminalAppPreview for previews.

Verification: `xcrun swiftc -typecheck -warnings-as-errors -target arm64-apple-ios16.0-simulator -sdk $(xcrun --show-sdk-path --sdk iphonesimulator)` clean across all 42 Swift files in `SptTerm/`.
