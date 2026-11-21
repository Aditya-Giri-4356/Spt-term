# SptTerm Implementation Progress

## Architectural Decisions & Constraints

### 1. Single PKCE Token Architecture
- **Scopes**: `user-library-read`, `playlist-read-private`, `playlist-read-collaborative`, `user-read-private`, `app-remote-control`, `streaming` defined in `STSpotifyConfig.scopes`.
- **Authorization Flow**: Initiated via `STSpotifyAuth.authorize()` using RFC 7636 PKCE (S256 code challenge).
- **Callback Routing**: The `sptterm://auth` callback is routed in a single place:
  - Intercepted by `ASWebAuthenticationSession` during interactive auth.
  - Handled via `STSpotifyAuth.handle(url:)` through `STRootGate.onOpenURL` if triggered externally.
- **Unified Consumption**:
  - **Spotify Web API**: Uses Bearer token via `STSpotifyAuth.withToken` (with automatic single-retry refresh on 401).
  - **Spotify App Remote**: Consumes the same access token in `STRemotePlayerService.connect()` via `appRemote.connectionParameters.accessToken = token`.
- **Storage & Fallback Resilience**:
  - Dual-layer token persistence: primary Keychain storage (`kSecClassGenericPassword`, service: bundle ID) with an automatic in-memory fallback (`inMemoryToken`) to prevent authorization/API failures when Keychain access is constrained.
  - Diagnostic logging via `os_log` tracking token exchanges (length, expiry, save status), token retrieval, and HTTP API calls.

### 2. In-Process UI Tweak Architecture (Phase B)
- **Tweak Target (`SptTermTweak.dylib`)**:
  - Built as an arm64 iOS 16+ dynamic library via XcodeGen.
  - Hosts the full SptTerm SwiftUI interface inside a dedicated non-key floating `UIWindow` above alert level (`UIWindow.Level.alert + 10.0`).
  - Minimized floating launch pill (`[ >_ SPT.TERM ]`) with passthrough touch handling, 44x44 minimum touch target, persistent coordinates stored in `UserDefaults(suiteName: "com.aditya.sptterm.tweak")`.
  - Fullscreen terminal view hosted in `UIHostingController` with `[ _ MINIMIZE ]` CRT button, safely making and releasing key window state.
  - In-process services:
    - `STInProcessPlayerService`: Polling `MPNowPlayingInfoCenter.default().nowPlayingInfo` (title, artist, album, duration, elapsed, rate) and dispatching transport controls via private `MRMediaRemoteSendCommand` (dlopen/dlsym).
    - `STSessionLibraryService`: Observes tracks during session use, deduplicating by URI (newest first, capped at 200 items), persisting to `UserDefaults(suiteName: "com.aditya.sptterm.tweak")`. Displays one-line header `"SESSION HISTORY - browse/search in Spotify"`. Tapping an entry calls `UIApplication.shared.open(...)` and logs with `"SptTerm:" NSLog` prefix.
    - `STInProcessArtworkService`: Reads `MPMediaItemArtwork` from `nowPlayingInfo` on the main thread, rasterizes pixels to ASCII glyph matrix (`ASCIIGlyphMatrix`), and extracts dominant accent color, falling back to mock only when artwork is `nil`.
    - `STAudioTweaksService`: Audio effects / EQ state isolated completely in `UserDefaults(suiteName: "com.aditya.sptterm.tweak")`.
    - `ExecPlaceholderView`: Live interactive command line supporting real actions (`play`, `pause`, `next`, `prev`, `theme <name>`, `open <uri>`); any other command outputs `"not available in-process"`. Prominently displays `"UI ONLY - does not process Spotify audio"`.

---

## Feature Matrix

| Feature | Status | Notes |
|---|---|---|
| Overlay Hosting | **VERIFIED (user-reported)** | Hosted via UIHostingController in floating dylib overlay window on active UIWindowScene |
| Now-Playing Metadata & Spectrum | **VERIFIED (user-reported)** | Track title, artist, album, elapsed progress, rate from MPNowPlayingInfoCenter |
| Transport Controls | **VERIFIED (user-reported)** | Play/pause, next, previous via MRMediaRemoteSendCommand private dispatch |
| Minimize & Restore | **VERIFIED (user-reported)** | CRT `[ _ MINIMIZE ]` button and floating launch pill |
| Pill Drag & Persistence | **VERIFIED (user-reported)** | Draggable floating pill; position persisted to `com.aditya.sptterm.tweak` suite |
| Themes & CRT Styling | **VERIFIED (user-reported)** | All 37 retro phosphor themes, scanlines, and CRT bloom persisted to tweak suite |
| Eevee Coexistence & Stability | **VERIFIED (user-reported)** | Coexists stably within injected EeveeSpotify process without crashing or symbol collision |
| Seek Control (drag + EXEC) | **VERIFIED (user-reported)** | Scrubber release & EXEC `seek <seconds>` seeking via MediaRemote ladder |
| Per-Track History Covers | **VERIFIED (user-reported)** | Saved per-entry ASCII matrix & dominant accent captured during session playback |
| On-Screen Log Buffer (`STLog`) | **VERIFIED (user-reported)** | 200-line ring buffer with EXEC `log` and `log copy` commands |
| Session Library (`STSessionLibraryService`) | **VERIFIED (user-reported)** | Observes nowPlayingInfo, dedupes by URI, newest first, cap 200, persisted in tweak suite |
| Play-by-URI (`open <uri>`) | **VERIFIED (user-reported)** | Opens `spotify:track:...` via `player.openURI` with `"SptTerm:" NSLog` logging |
| Progress Sync After Seek | **UNTESTED** | Local anchor extrapolation, 2.5s ignore window, 2 consecutive full-ladder failures while playing before SEEK N/A, resync on transport |
| Live Cover Cache & Retry | **UNTESTED** | URI-keyed cache, placeholder on URI change with poll retry, 300x300 main-thread fetch with bounds fallback, single nil log per track |
| Repeat Ladder & Verification | **UNTESTED** | AdvanceRepeatMode (7), ChangeRepeatMode (25/27/14), MPRemoteCommandCenter 1s verify, REPEAT (UNVERIFIED) and REPEAT N/A handling |
| Audio FX (`STAudioTweaksService`, EQ UI) | **MOCK/UI-ONLY** | Visible `"UI ONLY - does not process Spotify audio"` badge; state persisted to tweak suite |
| Web API (Phase A) | **BLOCKED** | Blocked by Spotify Web API app-owner Premium requirement (HTTP 403 on `/me/playlists`) |
| Phase B Milestone 2 In-Process Tweak Build | **COMPILES ONLY** | `SptTermTweak` (Debug + Release) and `SptTerm` schemes compile cleanly with zero errors |
