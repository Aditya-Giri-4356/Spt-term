# ASSUMPTIONS.md

## Verified
- iOS 16.0 target, macOS 15 build host, Xcode 27.2, iOS 27.2 SDK; no simulator runtimes; typecheck only.
- All 37 themes selectable at runtime via derived tokens; ThemeCatalogModel has 38 entries (00..37, Amber CRT included).
- SF Mono used throughout via single TermFont.Typography swap point (`TermFont.mono`).
- 4-tab bottom bar preserved; Home is landing state in [1:PLAY].
- MVVM; ViewModels are `@MainActor final class ...: ObservableObject` with `@Published` backing.
- DesignSystem wired through `@EnvironmentObject var theme: TerminalTheme`, plus `ArtworkProviding`, `PlayerServiceProtocol`, `LibraryServiceProtocol`, `AudioEffectsServiceProtocol` as `@Environment` values.
- `TerminalAppPreview` wraps previews and injects mock environment keys; all views carry a `#Preview` via `PreviewProvider`.
- ASCII artwork deterministic from per-track seed + accent where `ArtworkProviding` exposes it.
- `PlayerServiceProtocol.play(_:in:)` kicks off a queue; `toggleShuffle` flips `state.isShuffled`; `enqueue` sends to the queue.

## Design assumptions (stage d2)
- SearchViewModel debounces with Combine (`$query.debounce(for: .milliseconds(300))`) because `.onChange(of:perform:)` is deprecated on iOS 17+ SDK and `.task(id:)` would double-task the sleep; Combine debounce is iOS 13+ and silent under -warnings-as-errors.
- Recent searches persisted via `UserDefaults.standard` under key `search.recent`, capped at 8, deduplicated, newest first; cleared via an in-place button in the recent panel.
- Search prompt is a TUI stdin line: `">"` telemetry glyph + `TextField` (termType telemetry/accent) + `BlinkingCursor`.
- Search result grouping order: Tracks, Albums, Artists, Playlists; each group only rendered when non-empty; each group has its own SectionHeader with trailing count.
- Albums in search results rendered as a horizontal tile carousel via `ASCIIArtworkView`; Tracks/Artists/Playlists as `ASCIIPanel` rows.
- Per-track context button is a `[+]` framed pill that calls `addToQueue` (enqueue + haptic) on long-press intent; tapping the row itself plays into the collection queue.
- `CollectionDetailView` is the single reusable header + controls + track-list shell used by both AlbumDetailView and PlaylistDetailView; differences are title/subtitle/artwork/track source and the view-model hookup.
- Album subtitle: `artist • year • genre`. Playlist subtitle: `owner • N saves • tag`.
- Current-track highlighting in the track list uses accent text + accent bar overlay + subtle accent background tint, matching NowPlaying row convention.
- `navigationDestination` wiring in HomeView/LibraryView resolves `.album` and `.playlist` to real detail views; `.artist` remains a placeholder destination (stage d2 out of scope; flagged as a follow-up).
- Artist placeholder destination shows `ARTIST DETAIL — <id>` inside the existing PLACEHOLDER panel; no new artist UI created yet.
- Preview detail views use locally constructed `MockPlayerService()` (not held in `@StateObject`/`@ObservedObject` to avoid `ObservableObject` conformance on the mock) and `PreviewServices().library` for the library mock; this keeps previews simplest and avoids forcing mock conformance.
- SearchView previews use `PreviewServices().library` directly so the ViewModel's Combine debounce sink can still fire without a real service key dependency.
- Navigation uses `NavigationStack` with a typed `appRoute` path (`[AppRoute]`); path bindings default to `.constant([])` in previews where not driven by a parent.
