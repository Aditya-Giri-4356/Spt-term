# SptTerm

A retro-terminal / CRT-style SwiftUI Spotify player interface for iOS featuring authentic ASCII panels, tactile leveled tab navigation (`[1:PLAY]`, `[2:LIB]`, `[3:EXEC]`, `[4:THEME]`), 37 CRT phosphor themes, and real-time ASCII artwork rasterization.

SptTerm consists of two components:
1. **Phase A (Standalone App)**: Standalone iOS client application (`com.aditya.sptterm`).
2. **Phase B (`SptTermTweak.dylib`)**: In-process overlay dynamic library injected into a sideloaded Spotify IPA, hosting the full SptTerm interface in a floating window alongside the official Spotify client.

---

## Status

| Feature / Subsystem | Status | Notes |
|---|---|---|
| Overlay Window + Draggable Launch Pill | **VERIFIED (user-reported on a real device, iOS 27.0)** | Floating `UIWindow` above alert level hosting `UIHostingController`; draggable 44x44pt pill with persistence |
| Now-Playing Metadata | **VERIFIED (user-reported on a real device, iOS 27.0)** | Track title, artist, album, duration, elapsed time, and rate observed from `MPNowPlayingInfoCenter` |
| Transport Controls (Play / Pause / Next / Prev) | **VERIFIED (user-reported on a real device, iOS 27.0)** | Dispatched in-process via MediaRemote command primitives (commands 0, 1, 4, 5) |
| Seek Control + Progress Sync | **VERIFIED (user-reported on a real device, iOS 27.0)** | Scrubber scrubbing and `seek <seconds>` via MediaRemote command 24; anchor extrapolation and sync window |
| Phosphor Themes | **VERIFIED (user-reported on a real device, iOS 27.0)** | All 37 monochrome and amber phosphor themes, scanlines, and bloom; persisted to isolated tweak suite |
| Session Library | **VERIFIED (user-reported on a real device, iOS 27.0)** | Session track history deduplicated by URI (newest first, capped at 200 items); tap to play via URI |
| ASCII Artwork | **VERIFIED (user-reported on a real device, iOS 27.0)** | Real-time pixel-to-glyph ASCII rasterization from `MPMediaItemArtwork` (partial: some covers missing after skips) |
| Shuffle Control | **VERIFIED (user-reported on a real device, iOS 27.0)** | Triggered via Spotify's own on-screen button using the accessibility UI hook; handles second-mode menu diffing |
| Synced Lyrics | **VERIFIED (user-reported on a real device, iOS 27.0)** | LRCLIB integration toggleable via `lyrics on` in `[3:EXEC]`; fetches from the next track |
| Repeat Control | **NOT WORKING ON DEVICE** | UI hook shows "REPEAT N/A" (investigation pending). MediaRemote repeat/shuffle route is dead (device reports currentType=0, no state keys). |
| Audio FX & Equalizer | **UI ONLY** | Displays 10-band equalizer and DSP presets; explicitly marked "does not process Spotify audio" |
| Phase A Spotify Web API | **BLOCKED** | Spotify Web API blocked by developer dashboard app owner requirement for Spotify Premium (HTTP 403) |
| Stats, Pill Polish, Config Loader, Tests, Docs | **NOT YET RE-ADDED** | Implemented on `feat/opus-batch`; not yet merged into `feat/stable` |

---

## How It Works

SptTerm operates in-process inside Spotify via `SptTermTweak.dylib`:
- **Window Layering**: An injected dynamic library constructor creates a non-key floating `UIWindow` configured at `UIWindow.Level.alert + 10.0`, hosting a `UIHostingController` with the SptTerm SwiftUI interface.
- **Metadata & State**: Polls `MPNowPlayingInfoCenter.default().nowPlayingInfo` on the main run loop to extract track title, artist name, album name, duration, elapsed playback position, and artwork.
- **Transport & Seeking**: Directly dispatches transport controls (`kMRPlay`, `kMRPause`, `kMRNextTrack`, `kMRPreviousTrack`) and playback position scrubbing (`kMRSetPlaybackPosition`) via dynamically resolved `MRMediaRemoteSendCommand` symbols (`dlopen`/`dlsym`).
- **Shuffle & UI Interaction**: Interacts directly with Spotify's native on-screen player controls using accessibility-based inspection and activation (`accessibilityActivate` / touch dispatch) when full-screen player views are visible.

---

## Build Instructions

### Prerequisites
- macOS Sonoma or Sequoia with Xcode 15+ or 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Apple Command Line Tools (`xcode-select --install`)

### Building the Tweak Dylib

1. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```

2. Build the `SptTermTweak` dylib in Release configuration:
   ```bash
   xcodebuild -project SptTerm.xcodeproj \
              -scheme SptTermTweak \
              -destination "generic/platform=iOS" \
              -configuration Release \
              build
   ```

The compiled dylib is placed in DerivedData under `Build/Products/Release-iphoneos/SptTermTweak.dylib`.

### Client ID Configuration
If building the Phase A standalone app, configure your Spotify Developer Client ID:
- Copy the example configuration to a gitignored local file:
  ```bash
  cp Local.xcconfig.example Local.xcconfig
  ```
- Edit `Local.xcconfig` to provide your Client ID:
  ```xcconfig
  SPOTIFY_CLIENT_ID = YOUR_ACTUAL_CLIENT_ID
  ```
- `Local.xcconfig` is ignored by git and must never be committed; `Base.xcconfig` holds only `YOUR_CLIENT_ID`.

---

## Installation

> **IMPORTANT**: You must supply your **OWN** legally obtained Spotify IPA file. This repository does not contain, host, or distribute any proprietary Spotify binaries or IPA files.

1. **Prepare IPA**: Start with an original Spotify IPA.
2. **Inject Dylib**: Use [Sideloadly](https://sideloadly.io/) (or your preferred sideloading tool) to inject **only** `SptTermTweak.dylib` into the original IPA.
3. **Clean Injection Only**: Always inject into the clean, original IPA. Never re-inject into an already modified package.
4. **Sideload**: Install the resulting IPA to your iOS device using your Apple ID.

---

## Disclaimer & Credits

- **Disclaimer**: This is an unofficial personal research and customization project. SptTerm is not affiliated with, authorized by, maintained by, or in any way officially connected with Spotify AB or any of its subsidiaries. Modifying the Spotify client application likely violates Spotify's Terms of Service; use entirely at your own risk, on your own account and device.
- **Credits**: Tested alongside [EeveeSpotify](https://github.com/SideloadLabs/EeveeSpotifyReincarnated) (by SideloadLabs). SptTerm is an independent project and does not bundle or include EeveeSpotify source code or binaries.

---

## Known Issues

- **Repeat N/A**: Repeat control currently displays "REPEAT N/A" on device; the UI hook candidate for repeat requires further element hierarchy inspection.
- **Artwork Cache Misses**: Approximately 2 out of 10 track covers may fail to resolve after rapid track skips.
- **Tab Change Stammer**: Minor UI thread hitch observed when switching between dense tabs.
- **Lyrics Initial Track**: Synced lyrics (`lyrics on` in `[3:EXEC]`) does not fetch for the currently playing track immediately upon toggle; fetching begins on the subsequent track change.
- **File Size**: Select legacy service and view controller files exceed the 300-line recommended threshold and are slated for modular decomposition.
