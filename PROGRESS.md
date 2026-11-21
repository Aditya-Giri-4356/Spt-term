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

### 2. Project Generation & Build
- `project.pbxproj` was restored to standard Xcode format using **XcodeGen** (`project.yml`).
- `SptTermTweak/**` is explicitly excluded from the main application target.
- `SpotifyiOS` SDK is integrated as an SPM binary dependency from `https://github.com/spotify/ios-sdk` at `master`.
- `Info.plist` defines `CFBundleURLTypes` (`sptterm`) and `LSApplicationQueriesSchemes` (`spotify`).

---

## Feature Matrix

| Feature | Status | Notes |
|---|---|---|
| Xcode Project Generation (`project.yml`) | **VERIFIED** | Generated via XcodeGen 2.48.0; `plutil -lint` passes cleanly |
| SPM Package Resolution (`SpotifyiOS`) | **VERIFIED** | Resolved `https://github.com/spotify/ios-sdk @ master (8d3a71d)` |
| iOS Simulator Compilation (`generic/platform=iOS Simulator`) | **VERIFIED** | Clean build with zero errors and zero Swift compiler warnings |
| iOS Device Compilation (`generic/platform=iOS`) | **VERIFIED** | Clean arm64 build with zero errors |
| Info.plist & URL Schemes (`sptterm`, `spotify`) | **VERIFIED** | Validated with `plutil -lint`; bundle validation passes |
| Git Synchronization | **VERIFIED** | Pushed to remote `origin/main` (commit `f1b8803` and subsequent fixes) |
| PKCE Token Exchange & Refresh (`STSpotifyAuth`) | **COMPILES ONLY** | S256 verification and token refresh logic compiles cleanly |
| Spotify Web API Client (`STSpotifyWebAPI`) | **COMPILES ONLY** | Search, playlists, albums, and tracks endpoints mapped |
| App Remote Player Service (`STRemotePlayerService`) | **COMPILES ONLY** | Connects with PKCE token; handles player state and transport controls |
| Remote Artwork ASCII Rasterizer (`STRemoteArtworkService`) | **COMPILES ONLY** | Fetches via `imageAPI.fetchImage(forItem:with:callback:)`, renders ASCII glyph matrix |
| Hardware Volume Instant Sync (`TerminalHeader`, `STRemotePlayerService`) | **VERIFIED** | Direct KVO observation on `AVAudioSession.outputVolume` and `@State` reactivity on drag |
| Wordmark Clean Branding (`TerminalHeader`) | **VERIFIED** | Stripped `V2.4.0` version suffix next to `SPT.TERM` |
| Preset Audio Effects (`STPresetAudioEffects`) | **COMPILES ONLY** | Clamped gain presets persisted in UserDefaults |
| Service Container & Root Gate (`STServiceContainer`, `STRootGate`) | **COMPILES ONLY** | Reactive environment injection and onOpenURL routing |
| Live Spotify App Remote Connection | **UNTESTED** | Requires active Spotify client on device |
| Live Spotify Web API Queries | **UNTESTED** | Requires valid Spotify Client ID in `STSpotifyConfig.clientID` |
| Phase B Tweak Injection (`EeveeSpotify.ipa`) | **UNTESTED** | Scheduled for Phase B session; target is EeveeSpotify IPA |
