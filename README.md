# SptTerm

A retro-terminal / CRT-style SwiftUI Spotify player interface for iOS featuring ASCII panels, tactile leveled tab navigation ([1:PLAY], [2:LIB], [3:EXEC], [4:THEME]), 37 CRT phosphor themes, real-time ASCII artwork rasterization, and built-in diagnostic probe instrumentation.

SptTerm consists of three core components:
1. Phase A (Standalone App): Standalone iOS client application (com.aditya.sptterm).
2. Phase B (SptTermTweak.dylib): In-process overlay dynamic library injected into a sideloaded Spotify IPA, hosting the full SptTerm interface in a floating window alongside the Spotify client.
3. Diagnostic Probe Engine (SPT_PROBE): In-process runtime introspection and reverse-engineering suite for inspecting Spotify internal state, LevelDB storage, heap objects, network traffic, and class hierarchies.

IMPORTANT NOTICE: This is an active, experimental reverse-engineering project. Bugs, crashes, UI hitches, and unexpected behavior are to be expected. To run the tweak, you must build SptTermTweak.dylib and inject it into your own legally obtained Spotify IPA (either a clean IPA or an IPA pre-patched with tweaks like EeveeSpotify) using a sideloading utility such as Sideloadly. Free-signed Apple IDs require re-signing every 7 days. SptTerm does not distribute modified apps, proprietary binaries, or pre-packaged IPAs.

---

## Status

| Feature / Subsystem | Status | Notes |
|---|---|---|
| Overlay Window + Draggable Launch Pill | VERIFIED (iOS 17+) | Floating UIWindow above alert level hosting UIHostingController; draggable 44x44pt pill with persistence |
| Now-Playing Metadata | VERIFIED (iOS 17+) | Track title, artist, album, duration, elapsed time, and rate observed from MPNowPlayingInfoCenter |
| Transport Controls (Play / Pause / Next / Prev) | VERIFIED (iOS 17+) | Dispatched in-process via MediaRemote command primitives (commands 0, 1, 4, 5) |
| Seek Control + Progress Sync | VERIFIED (iOS 17+) | Scrubber scrubbing and seek <seconds> via MediaRemote command 24; anchor extrapolation and sync window |
| Phosphor Themes | VERIFIED (iOS 17+) | All 37 monochrome and amber phosphor themes, scanlines, and bloom; persisted to isolated tweak suite |
| Session Library | VERIFIED (iOS 17+) | Session track history deduplicated by URI (newest first, capped at 200 items); tap to play via URI |
| Library Discovery & Cache ([2:LIB]) | FUNCTIONAL / EXPERIMENTAL | In-app playlist discovery via navigation inspection; persistent playlist cache v2; tap to view tracks and play |
| ASCII Artwork | VERIFIED (iOS 17+) | Real-time pixel-to-glyph ASCII rasterization from MPMediaItemArtwork (partial: some covers missing after skips) |
| Shuffle Control | VERIFIED (iOS 17+) | Triggered via Spotify's own on-screen button using the accessibility UI hook; handles second-mode menu diffing |
| Synced Lyrics | VERIFIED (iOS 17+) | LRCLIB integration toggleable via lyrics on in [3:EXEC]; fetches synchronized lyrics |
| Diagnostic Probe Engine | FUNCTIONAL (SPT_PROBE) | In-process experiments A, B, D, E, G, H, I for runtime introspection, LevelDB parsing, heap scanning, and network inspection |
| Repeat Control | NOT WORKING ON DEVICE | UI hook shows "REPEAT N/A" (investigation pending). MediaRemote repeat/shuffle route is inactive |
| Audio FX & Equalizer | UI ONLY | Displays 10-band equalizer and DSP presets; explicitly marked "does not process Spotify audio" |
| Phase A Spotify Web API | BLOCKED | Spotify Web API blocked by developer dashboard app owner requirement for Spotify Premium (HTTP 403) |

---

## How It Works

SptTerm operates in-process inside Spotify via SptTermTweak.dylib:
- Window Layering: An injected dynamic library constructor creates a non-key floating UIWindow configured at UIWindow.Level.alert + 10.0, hosting a UIHostingController with the SptTerm SwiftUI interface.
- Metadata & State: Observes MPNowPlayingInfoCenter.default().nowPlayingInfo to extract track title, artist name, album name, duration, elapsed playback position, and artwork.
- Transport & Seeking: Dispatches transport controls (kMRPlay, kMRPause, kMRNextTrack, kMRPreviousTrack) and playback position scrubbing (kMRSetPlaybackPosition) via dynamically resolved MRMediaRemoteSendCommand symbols (dlopen / dlsym).
- Shuffle & UI Interaction: Interacts with Spotify's native on-screen player controls using accessibility-based inspection and activation (accessibilityActivate / touch dispatch) when player views are visible.
- Library Exploration: Discovers user playlists and tracks through hierarchical view inspection, caching entries to an isolated JSON store for instant navigation.

---

## Diagnostic Probe Engine (SPT_PROBE)

When compiled with `SPT_PROBE=1`, SptTerm includes a dedicated diagnostic and reverse-engineering probe suite. The probe enables low-level investigation of Spotify's internal storage and architecture directly from the running app, helping research URI-based playback initiation and offline library loading without UI scraping.

### Experiments Suite

- Experiment A (Class & Method Inventory):
  Enumerates loaded Mach-O images using Objective-C runtime C APIs (`objc_copyClassList`, `class_getImageName`, `class_copyMethodList`). Filters non-system frameworks, groups class prefixes, highlights keyword-matched classes (Player, Playback, Playlist, Esperanto, Storage, etc.), and ranks top selector dumps.

- Experiment B (Heap Instance Finder):
  Enumerates live malloc zones via `malloc_get_all_zones` and memory-safe pointer validation (`vm_read_overwrite`). Identifies active instances of critical playback controllers (e.g., `SPTExternalIntegrationPlaybackControllerImplementation`, `SPTEsperantoPlayer`) and safely dumps ivars (strings, numbers, collections, scalar hex, Swift offsets) to map memory topology.

- Experiment D (Filesystem & SQLite Schema Inspector):
  Recursively audits sandboxed app directories (Documents, Library/Application Support, Caches) up to depth 8. Generates directory byte totals and extension breakdowns. Dynamically loads `libsqlite3.dylib` via `dlopen` to query schema tables, row counts, and cached URL histograms from internal databases such as `Cache.db`.

- Experiment E (Network & NSURLSession Interceptor):
  Swizzles `-[NSURLSessionTask resume]` from `+load` to monitor in-process HTTP/HTTPS traffic. Normalizes path patterns (mapping user IDs and hex identifiers to tokens), records response delegates, computes top non-image path histograms, and SHA-256 hashes sensitive credentials to prevent credential exposure.

- Experiment G (PersistentCache LevelDB & Snappy Parser):
  Inspects Spotify's `PersistentCache` storage directory. Validates LevelDB 8-byte magic footers (`0xdb4775248b80fb57ULL`), decodes compressed blocks using a custom bounds-checked Snappy decompressor, scans for Spotify URIs (`spotify:track:`, `spotify:playlist:`, etc.), and analyzes cached metadata blobs.

- Experiment H (LevelDB Deep Reader):
  Targets user database paths (`Users/*/primary.ldb`). Parses `CURRENT` and `MANIFEST` VersionEdit records to determine the active file set. Ingests `*.ldb` SSTables and write-ahead logs (`*.log`) into a deduplicated key index, extracts URI reference counts and key families, identifies protobuf type URLs, and reconstructs playlist completeness metrics.

- Experiment I (Targeted Class & Protocol Dump):
  Performs deep introspection of 12 key Spotify playback and service classes. Dumps class inheritance chains, adopted protocols (including extended method type encodings via `_protocol_getMethodTypeEncoding`), properties, and instance variable layouts while filtering token and credential names.

### Probe UI Panel

The probe UI is embedded directly into the SptTerm interface when `SPT_PROBE` is active:
- Collapsible Header: Toggle between compact status bar and full diagnostic panel using the Hide / Show control.
- Experiment Triggers: Dedicated trigger buttons (`[A]`, `[B]`, `[D]`, `[E]`, `[G]`, `[H]`, `[I]`) dispatch experiments to background utility queues with safety timeouts.
- Log Viewer: Displays real-time tails of the unified probe log with automatic line truncation and scrollback.
- Copy to Clipboard: A single-tap "Copy" button copies the active 64 KB log tail to the iOS system pasteboard for instant sharing.
- Export Log: Direct export button invokes the system share sheet (`UIActivityViewController`) to save or air-drop the raw log file.

---

## Build Instructions

### Prerequisites
- macOS Sonoma or Sequoia with Xcode 15+ or 16+
- XcodeGen (`brew install xcodegen`)
- Apple Command Line Tools (`xcode-select --install`)

### Building the Release Tweak Dylib

1. Generate the Xcode project from configuration:
   ```bash
   xcodegen generate
   ```

2. Build the standard Release dylib:
   ```bash
   xcodebuild -project SptTerm.xcodeproj \
              -scheme SptTermTweak \
              -destination "generic/platform=iOS" \
              -configuration Release \
              build
   ```

The output dylib is generated at:
`DerivedData/SptTerm/Build/Products/Release-iphoneos/SptTermTweak.dylib`

### Building the Probe Instrumentation Dylib

To build the dylib with diagnostic probe capabilities enabled:
```bash
xcodebuild -project SptTerm.xcodeproj \
           -scheme SptTermTweak \
           -destination "generic/platform=iOS" \
           -configuration Release \
           GCC_PREPROCESSOR_DEFINITIONS='$inherited SPT_PROBE=1' \
           OTHER_SWIFT_FLAGS='$(inherited) -DSPT_PROBE' \
           build
```

### Standalone App (Phase A) Configuration

If building the standalone client app, configure your Spotify Developer Client ID:
1. Copy the example configuration to a local file:
   ```bash
   cp Local.xcconfig.example Local.xcconfig
   ```
2. Edit `Local.xcconfig` to provide your Spotify Client ID:
   ```xcconfig
   SPOTIFY_CLIENT_ID = YOUR_ACTUAL_CLIENT_ID
   ```
   Note: `Local.xcconfig` is gitignored and must never be committed.

---

## Sideloading Instructions (Sideloadly)

To run SptTerm on an iOS device, `SptTermTweak.dylib` must be injected into a Spotify IPA using Sideloadly. The tweak runs in-process on non-jailbroken devices.

IMPORTANT: You must provide your own legally obtained Spotify IPA. This project does not provide or distribute Spotify IPAs.

### Preparation
- Target IPA: You may use a clean, official Spotify IPA or an IPA already modified with tweaks like EeveeSpotify.
- Signing Account: A free Apple ID allows installation for up to 7 days before requiring re-sideloading/re-signing. A paid Apple Developer account provides 365-day signing.
- Sideloadly: Download and install Sideloadly on macOS or Windows (https://sideloadly.io).

### Injection Steps

1. Connect your iOS device to your computer via USB (or configure Wi-Fi pairing in Sideloadly).
2. Launch Sideloadly and enter your Apple ID.
3. Drag and drop your Spotify IPA file into the IPA target box in Sideloadly.
4. Expand the "Advanced Options" tab at the bottom of the Sideloadly window.
5. In the "Inject dylibs / frameworks" section, click "+" and select your compiled `SptTermTweak.dylib`.
6. Ensure the injection mode is set to Cydia Substrate or Substitute (default automatic injection works for most configurations).
7. Click "Start" to sign the package and install it onto your iOS device.
8. On your iOS device, go to Settings > General > VPN & Device Management, tap your developer certificate under Developer App, and select "Trust".
9. Open Spotify. The floating draggable launch pill (`[ >_ SPT.TERM ]`) will appear on screen. Tap the pill to open the retro-terminal interface.

---

## Disclaimer & Credits

- Disclaimer: This is an unofficial personal research, accessibility, and customization project. SptTerm is not affiliated with, endorsed by, maintained by, or in any way officially connected with Spotify AB or any of its subsidiaries. Modifying the Spotify client application may violate Spotify terms of service. Use strictly at your own risk.
- Expected Bugs: This modification interacts with internal Spotify views, non-public system APIs (MediaRemote), and local LevelDB storage caches. Features may behave unexpectedly, cause UI stutter, or break across Spotify updates.
- Credits: Tested alongside EeveeSpotify (https://github.com/SideloadLabs/EeveeSpotifyReincarnated by SideloadLabs) as a separate injection layer. SptTerm is an independent project and does not bundle or include EeveeSpotify source code or binaries.

---

## Known Issues

- Repeat N/A: Repeat control displays "REPEAT N/A" on device due to inactive MediaRemote repeat routing; UI hook candidate under investigation.
- Artwork Cache Misses: Some track album covers may fail to resolve immediately following rapid skip bursts.
- Tab Change Stammer: Minor rendering delay observed when navigating into densely populated tabs on older devices.
- Lyrics Initial Track: Synced lyrics toggle (`lyrics on` in `[3:EXEC]`) begins fetching on the first track transition after activation.
- Non-Jailbroken 7-Day Expiry: Free Apple ID installations require re-sideloading every 7 days through Sideloadly.
