---
name: Phosphor TUI
colors:
  surface: '#111411'
  surface-dim: '#111411'
  surface-bright: '#373a36'
  surface-container-lowest: '#0c0f0c'
  surface-container-low: '#191c19'
  surface-container: '#1d201d'
  surface-container-high: '#282b27'
  surface-container-highest: '#333632'
  on-surface: '#e1e3dd'
  on-surface-variant: '#b9ccb5'
  inverse-surface: '#e1e3dd'
  inverse-on-surface: '#2e312d'
  outline: '#849581'
  outline-variant: '#3b4b3a'
  surface-tint: '#00e55b'
  primary: '#edffe8'
  on-primary: '#003911'
  primary-container: '#00ff66'
  on-primary-container: '#007128'
  inverse-primary: '#006e27'
  secondary: '#97cfe0'
  on-secondary: '#003640'
  secondary-container: '#094e5c'
  on-secondary-container: '#86bece'
  tertiary: '#fff8ff'
  on-tertiary: '#411478'
  tertiary-container: '#e9d6ff'
  on-tertiary-container: '#744dad'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#6bff83'
  primary-fixed-dim: '#00e55b'
  on-primary-fixed: '#002107'
  on-primary-fixed-variant: '#00531b'
  secondary-fixed: '#b3ecfc'
  secondary-fixed-dim: '#97cfe0'
  on-secondary-fixed: '#001f26'
  on-secondary-fixed-variant: '#094e5c'
  tertiary-fixed: '#eddcff'
  tertiary-fixed-dim: '#d7baff'
  on-tertiary-fixed: '#290055'
  on-tertiary-fixed-variant: '#593090'
  background: '#111411'
  on-background: '#e1e3dd'
  surface-variant: '#333632'
typography:
  headline-lg:
    fontFamily: JetBrains Mono
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 34px
    letterSpacing: -0.02em
  headline-lg-mobile:
    fontFamily: JetBrains Mono
    fontSize: 22px
    fontWeight: '700'
    lineHeight: 28px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: JetBrains Mono
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: 0em
  body-lg:
    fontFamily: JetBrains Mono
    fontSize: 16px
    fontWeight: '500'
    lineHeight: 22px
    letterSpacing: 0em
  body-md:
    fontFamily: JetBrains Mono
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: 0em
  body-sm:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
    letterSpacing: 0.02em
  label-lg:
    fontFamily: JetBrains Mono
    fontSize: 13px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.05em
  label-md:
    fontFamily: JetBrains Mono
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
    letterSpacing: 0.06em
  label-sm:
    fontFamily: JetBrains Mono
    fontSize: 9px
    fontWeight: '600'
    lineHeight: 12px
    letterSpacing: 0.08em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 0.75rem
  margin: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 0.75rem
  space-lg: 1rem
  space-xl: 1.5rem
---

## Brand & Style

This design system translates the command-line terminal and vintage phosphor CRT aesthetic into an ergonomic, ultra-responsive iOS mobile interface. It merges raw, technical developer culture with refined, touch-first audio controls. The interface balances high-contrast monochrome terminal utility with luminous, analog vacuum-tube glow.

### Personality & Aesthetic Attributes
- **Vintage Precision:** Character-grid discipline, fixed-width rhythm, and ASCII wireframes structured specifically around modern mobile touch standards.
- **Luminescent & Tactical:** Deep CRT obsidian backgrounds illuminated by glowing phosphor beam lines, dynamic audio spectrums, and bracketed telemetry indicators.
- **Ergonomic Brutalism:** Visual styling draws from ncurses, VT100, and UNIX shells, yet interactive hit areas strictly adhere to iOS human interface standards (minimum 44×44pt touch envelopes) disguised as discrete character blocks or terminal pill tags.

## Colors

The palette is engineered exclusively for an authentic, deep dark-mode experience. Surfaces absorb ambient light, while foreground data radiates active voltage.

### Palette Architecture
- **Primary (`#00ff66` P1 Phosphor Green):** The default operational colorway. Used for high-voltage UI moments: active playback states, primary interactive glyphs, playback cursors, and primary telemetry. Secondary shades include mid-frequency green (`#22c55e`) for static labels and muted bus line green (`#15803d`) for subtle ASCII frame rendering.
- **Secondary (`#88c0d0` Frost Cyan / Nord):** Evokes cold arctic terminal themes. Applied to audio metadata (sample rate, bit depth, codec flags, and playlist indexes).
- **Tertiary (`#bd93f9` Synth Dracula Violet):** Assigned to secondary status flags, alternative themes, loop/shuffle overrides, and diagnostic error/exception highlights alongside CRT Amber (`#ffb000`).
- **Neutral (`#0a0d0a` Void Obsidian / Matrix CRT Surface):** The foundational substrate. Elevated panels use `#030503` (CRT shadow mask depth) and `#111611` (illuminated surface containers).

### Dynamic Theming Tokens
While P1 Green governs default states, color token mappings switch dynamically based on user-selected color profiles (e.g., CRT Amber `#ffb000`, Nord Frost `#81a1c1`, or Dracula Pink `#ff79c6`) without altering spatial or structural tokens.

## Typography

Typography is strictly monospaced. Character widths remain constant to ensure that simulated terminal grids, tables, and ASCII borders align across any screen orientation.

### Hierarchy & Style Rules
- **Headline Levels:** Reserved for active track titles, artist header telemetry, and modal views. Uppercase styling is preferred for system headers, while mixed-case is preserved for audio track titles.
- **Body & Data Levels:** Output streams, track listings, playlist dumps, and audio hardware metrics (e.g., `FLAC / 24-bit / 96.0 kHz`).
- **Labels & Micro-Tokens:** Command prompts (`$`, `>`), shell tags, buffer readouts, and timestamps.
- **Character Fallback Strategy:** If `JetBrains Mono` is unavailable, fallback sequence strictly prioritizes `SF Mono`, `Fira Code`, and system-standard fixed-width typefaces.

## Layout & Spacing

Layout geometry follows an emulated character-cell grid overlay combined with modern fluid constraints to ensure compatibility with iPhone screen boundaries, Dynamic Island, and home indicator regions.

### Grid & Composition Rules
- **Safe Area Anchoring:** Outer gutters conform to `1rem` (16pt), expanding to native iOS Dynamic Island and Safe Area bounds on top and bottom edges.
- **Character Alignment:** All structural components snap to multi-unit character heights (increments of 8pt/16pt). 
- **Touch Bounds vs. Visual Bounds:** Visual elements can remain condensed and precise (e.g., a 14pt ASCII `[x]` button), but their hit target container expands to at least `44×44pt` through transparent layout bounds.
- **Screen Adaptation:** 
  - Mobile (Compact): Single vertical terminal shell stream. Box borders span 100% canvas width minus horizontal margins.
  - Tablet/Landscape (Regular): Dual-column split console featuring queue/log outputs on the left and active deck/visualizer controls on the right.

## Elevation & Depth

Visual hierarchy is created without skeuomorphic drop shadows. Instead, depth is conveyed through cathode-ray luminescence, scanlines, border complexity, and tonal surface steps.

### Depth Mechanics
- **Ground Floor (Base Canvas):** `#030503` paired with an ultra-subtle, persistent 1px horizontal scanline repeating pattern (`rgba(0, 255, 102, 0.03)` on 3px intervals) simulating CRT raster sweeps.
- **Panels & Enclosures (Level 1):** Solid `#0a0d0a` framed by single-line ASCII box characters (`┌─┐│└─┘`).
- **Active Focus & Modals (Level 2):** Elevated via double-line ASCII frames (`╔═╗║╚═╝`) with an interior backfill of `#111611` and an ambient green phosphor bloom (`box-shadow: 0 0 15px rgba(0, 255, 102, 0.15)`).
- **Glow & Bloom:** Text and vector elements tagged as active or playing emit a soft optical dispersion filter (`drop-shadow: 0 0 4px currentColor`). Inactive or muted parameters are dimmed to 40% opacity without bloom.

## Shapes

The design system maintains an intentional tension between retro rectangular terminal cells and ergonomic mobile controls.

### Geometric Rules
- **ASCII Containers:** Absolute 0px sharp corners where ASCII border characters (`┌`, `┐`, `└`, `┘`) simulate structural edges.
- **Interactive Badges & Pill Buttons:** Styled with a tight `0.25rem` (`roundedness: 1`) radius to provide tactile softness for buttons, status badges, and chip filters while retaining hardware-terminal character.
- **Dividers:** Horizontal and vertical separator bars utilize pure Unicode box-drawing paths (`─`, `━`, `│`, `┃`) rather than standard CSS border dividers.

## Components

### Buttons & Interactive Prompts
- **Primary Terminal Trigger:** Styled as reversed phosphor blocks (`background: #00ff66; color: #030503; font-weight: 700; border-radius: 4px;`). Active state triggers an inverted phosphor flash.
- **Ghost Shell Action:** Enclosed in brackets: `[ PLAY ]`, `[ PAUSE ]`, `[ MUTE ]`. Tapping triggers a transient cursor blink `_`.
- **Icon Glyphs:** Standard media controls rendered via unicode or fixed-width monospaced shapes (`▶`, `■`, `❚❚`, `⏮`, `⏭`, `🔁`).

### Progress Bars & Telemetry Scrubbers
- **Track Progress:** Formatted using fixed-width bracketed string syntax:
  `[====================>--------------------]`
  On iOS touch displays, dragging across the bracketed track updates the interior characters in real time, while a floating tooltip outputs direct timecode data (`02:41 / 04:15`).
- **Buffer & VU Meters:** Dynamic peak meters displaying dB thresholds:
  `L: [||||||||||||||||....] -6dB`
  `R: [||||||||||||||......] -12dB`

### Chips, Tags & Status Badges
- **Status Pills:** Pill-shaped tags displaying codec info, network state, or queue position:
  `[ FLAC 96k ]` `[ LIVE ]` `[ SHUFFLE: OFF ]`
  Bordered with 1px dimmed phosphor lines (`#15803d`) and illuminated with primary green or secondary frost cyan text.

### Text Inputs & Command Lines
- **Shell Input Field:** Prefixed with a persistent command prompt `user@term.fm:~$ `. Displays an animated blinking block cursor (`▋`). Supports virtual keyboard interaction with instant keystroke click feedback.

### Cards & Grouping Structures
- **TUI Group Panels:** Framed by ASCII border sets with inlaid titles breaking the top border:
  ```
  ┌── NOW PLAYING ─────────────────────────────────┐
  │ Track: Cybernetic Drift                        │
  │ Artist: Carbon Based Lifeforms                 │
  │ Status: [ PLAYING ]          Bitrate: 1411kbps │
  └────────────────────────────────────────────────┘
  ```
- **Track Lists:** Formatted as an aligned terminal file directory:
  `-rw-r--r--  01  03:42  Solar_Fields_Active.flac`
  `-rw-r--r--  02  05:18  Vector_Hold_Nightrun.wav`
  Tapping a row highlights the entire line with a `#15803d` translucent background strip.