# SptTerm In-Process Tweak Installation Guide

## Important Distribution & Legal Notice

> **Distribution Policy**: We distribute **ONLY** the dynamic library binary (`SptTermTweak.dylib`) and its open-source Swift/Objective-C codebase. We **never** host, package, or distribute modified Spotify IPAs, copyrighted application binaries, or proprietary client assets. All binary patching and sideloading is performed locally by the user.

---

## Prerequisites

1. **Computer**: macOS (Intel or Apple Silicon) or Windows with [Sideloadly](https://sideloadly.io/) installed.
2. **Device**: iPhone running iOS 16.0 or later, connected via USB or Wi-Fi sync.
3. **Clean IPA**: An original, clean EeveeSpotify IPA (or standard decrypted Spotify IPA).
4. **Tweak Dylib**: The compiled `SptTermTweak.dylib` (available from the Debug or Release build products).

---

## Step-by-Step Sideloadly Instructions

### 1. Launch Sideloadly
- Open Sideloadly on your computer.
- Ensure your iOS device appears in the device selector dropdown.

### 2. Select the IPA
- Drag and drop your **original, clean EeveeSpotify IPA** into the IPA box in Sideloadly.
- **CRITICAL WARNING**: **Never re-inject into an already-injected IPA.** Re-injecting into an IPA that already contains a previous version of `SptTermTweak.dylib` creates duplicated Mach-O load commands (`LC_LOAD_DYLIB`) and causes launch-time dynamic linker crashes. Always begin with a pristine IPA file.

### 3. Inject `SptTermTweak.dylib`
- Click the **Advanced Options** button in Sideloadly.
- Locate the **Inject Dylibs/Frameworks** section.
- Click the `+` button and browse to `SptTermTweak.dylib`:
  - **Release**: `DerivedData/SptTerm-*/Build/Products/Release-iphoneos/SptTermTweak.dylib`
  - **Debug**: `DerivedData/SptTerm-*/Build/Products/Debug-iphoneos/SptTermTweak.dylib`
- Ensure **Cydia Substrate / Substitute / ElleKit** or **Direct insert** injection method is selected.

### 4. Sideload to Device
- Enter your Apple ID credentials.
- Click **Start** to initiate signing and sideloading.
- Wait for Sideloadly to report `Done`.

### 5. Trust Certificate on Device
- On your iPhone, navigate to **Settings > General > VPN & Device Management**.
- Select your Apple ID developer profile and tap **Trust**.

---

## Launching SptTerm

1. Launch the sideloaded Spotify app.
2. Once Spotify becomes active in the foreground, `SptTermTweakInit` will automatically present the draggable floating launch pill:
   ```
   [ >_ SPT.TERM ]
   ```
3. Tap the pill to expand the full-screen retro phosphor CRT terminal interface.
4. Tap `[ _ MINIMIZE ]` in the top-right corner to return to the standard Spotify UI with the floating pill intact.
5. In the `[3:EXEC]` tab, use commands like `play`, `pause`, `next`, `prev`, `seek <seconds>`, `theme <name>`, `open <uri>`, `log`, and `log copy`.

---

## Privacy Notice (Synced Lyrics)

When synced lyrics are enabled (`lyrics on`), track metadata (title, artist name, album title, and duration) is transmitted over HTTPS to [LRCLIB](https://lrclib.net) to retrieve synchronized lyrics. No Spotify account credentials, user identifiers, or private data are ever transmitted. Synced lyrics are disabled by default.
