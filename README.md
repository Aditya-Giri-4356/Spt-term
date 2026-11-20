# SptTerm (Spotify Terminal UI for iOS)

SptTerm is a retro-terminal phosphor CRT music player for iOS, translating the command-line terminal and vintage vacuum-tube monitor aesthetic into an ergonomic, touch-first mobile interface.

The project is built natively using Swift and SwiftUI, targeting iOS 16.0 and later, optimized for modern iPhones (including iPhone 14) with dynamic safe area handling, responsive layout constraints, and tactile hardware interaction.

---

## Current Status and Architecture

SptTerm is currently in an active prototype state with a complete, compile-clean SwiftUI navigation shell, dedicated design system, hardware telemetry synchronization, and decoupled service layers.

### 1. Navigation Shell and Leveled Tab Bar
- Four primary navigation tabs with fixed, leveled 50pt tactile keycaps:
  - Tab 1: [1:PLAY] [ > ] - Home screen, continue playing shelf, bento cards, and active deck.
  - Tab 2: [2:LIB] [ = ] - File-tree music library, album/playlist directories, and crates.
  - Tab 3: [3:EXEC] [ >_ ] - Audio tuning, 10-band equalizer, and DSP executor console.
  - Tab 4: [4:THEME] [ * ] - Phosphor CRT theme catalog and config manager.
- Each tab features a dedicated single NavigationStack (zero nested stacks) with routing to detail views (Album, Playlist, Artist, and Search).
- The navigation bar is leveled with uniform button frames, 6pt spacing, and authentic ASCII logo badges.

### 2. Audio Playback and Telemetry
- MiniPlayer: Floats directly above the navigation bar with matched-geometry artwork transitions, live playback toggle, track metadata, and mini progress bar.
- Full-Screen Now Playing View:
  - Displays ASCII album art matrix, live VU/spectrum meter, transport controls, and synchronized lyrics panel.
  - Hardware Volume Synchronization: Live two-way sync with physical iPhone volume buttons via AVAudioSession observation.
  - Interactive ASCII Volume Scrubber: Draggable volume telemetry in the header (`[VOL: [########..]]`) and Now Playing view.
  - Interactive Swipe-to-Dismiss: Dragging down on the window moves the entire interface 1:1 with the finger; releasing past the threshold smoothly collapses the window back into the MiniPlayer on top of the navbar.
  - Dedicated pull-down grab bar (`[ -- v COLLAPSE -- ]`) with tap and drag-to-dismiss support.

### 3. Phosphor TUI Design System
- Monospaced typography rhythm using Apple SF Mono (with JetBrains Mono token fallbacks).
- 37 hand-tuned and dynamically derived color themes (Matrix P1 Green, CRT Amber, Cyberpunk Pink, Nord Cyan, Commodore 64, etc.).
- CRT scanline raster overlay and ambient phosphor bloom effects.
- Active states styled as inverted phosphor blocks with haptic feedback (`TermHaptic.tap()`).

### 4. Protocol-Driven Architecture
- Views interact exclusively through decoupled Swift protocols:
  - `PlayerServiceProtocol`: Playback state, track progress, volume, play/pause/skip.
  - `LibraryServiceProtocol`: Albums, playlists, search index, recent items.
  - `AudioEffectsServiceProtocol`: Equalizer bands and presets.
  - `ArtworkProviding`: ASCII matrix generation and dominant color derivation.
- Mock services provide instant offline development and testing. The codebase is structured for direct integration with the Spotify iOS App Remote SDK or Spotify Web API.

---

## Repository Structure

```
SptTerm/
├── SptTermApp.swift             # Main app entry point
├── DesignSystem/
│   ├── Components/              # 18 custom TUI components (ASCIIPanel, SpectrumBars, etc.)
│   ├── Foundation/              # Typography, Spacing, Radii, Themes, Haptics, Motion
│   └── Modifiers/               # Scanlines, Phosphor glow, Monospace type modifiers
├── Models/                      # Track, Album, Artist, Playlist, PlayerState, Route
├── Services/                    # Decoupled protocols and mock implementations
├── ViewModels/                  # Observable ViewModels (NowPlaying, Home, Library, Search)
└── Views/
    ├── Detail/                  # Album, Playlist, and Collection detail screens
    ├── Library/                 # Terminal file-tree library browser
    ├── MiniPlayer/              # Compact floating player view
    ├── NowPlaying/              # Full-screen player with live ASCII spectrum and scrubber
    ├── Search/                  # Command-line search console
    └── Shell/                   # Root shell, leveled tab bar, and navigation stacks
```

---

## Prerequisites

- macOS 14.0 (Sonoma) or macOS 15.0 (Sequoia)
- Xcode 15.0 or Xcode 16.0+
- iOS 16.0+ SDK (Command Line Tools installed via `xcode-select --install`)
- Optional: Physical iPhone with iOS 16+ or iOS Simulator

---

## How to Build and Run

### Method 1: Using Xcode (Recommended)

1. Clone the repository:
   ```bash
   git clone https://github.com/Aditya-Giri-4356/Spt-term.git
   cd Spt-term
   ```

2. Open the project in Xcode:
   ```bash
   open SptTerm.xcodeproj
   ```

3. Configure Signing (for physical iPhone only):
   - Select the `SptTerm` project in the left Project Navigator.
   - Select the `SptTerm` target under Targets.
   - Go to the **Signing & Capabilities** tab.
   - Under **Team**, select your Apple ID / Personal Team.
   - Ensure the Bundle Identifier is unique (e.g. `com.aditya.sptterm`).

4. Select Run Destination:
   - In the top toolbar destination picker, choose your physical iPhone (e.g. `Aditya's iPhone 14`) or any iOS Simulator (e.g. `iPhone 16 Pro`).

5. Build and Run:
   - Press `Cmd + R` or click the Play button.

---

### Method 2: Command Line (xcodebuild)

You can build the project directly from the terminal without opening the Xcode GUI.

1. Build for iOS Simulator:
   ```bash
   xcodebuild -project SptTerm.xcodeproj \
              -scheme SptTerm \
              -destination "generic/platform=iOS Simulator" \
              build
   ```

2. Typecheck Swift files directly:
   ```bash
   xcrun swiftc -typecheck \
                -warnings-as-errors \
                -target arm64-apple-ios16.0-simulator \
                -sdk $(xcrun --show-sdk-path --sdk iphonesimulator) \
                $(find SptTerm -name "*.swift")
   ```

3. Build for Physical iOS Device:
   ```bash
   xcodebuild -project SptTerm.xcodeproj \
              -scheme SptTerm \
              -destination "generic/platform=iOS" \
              build
   ```

---

## Technical Constraints and Conventions

- Language: Swift 5.9+ / Swift 6 compatible
- Framework: Pure native SwiftUI (no third-party package dependencies)
- Audio Integration: AVFoundation (`AVAudioSession` hardware volume observation)
- Typography: Monospaced character grid discipline using `TermFont.mono`
- Formatting: Zero warnings with `-warnings-as-errors`
- Touch Envelopes: All interactive ASCII elements maintain a minimum 44x44pt hit area in compliance with Apple Human Interface Guidelines.
