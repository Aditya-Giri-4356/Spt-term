import SwiftUI

enum TabItem: String, CaseIterable, Identifiable {
    case player
    case library
    case exec
    case theme

    var id: String { rawValue }

    /// ASCII logo icon enclosed in retro terminal brackets
    var asciiLogo: String {
        switch self {
        case .player: return "[ ▶ ]"
        case .library: return "[ ≡ ]"
        case .exec: return "[ >_ ]"
        case .theme: return "[ ☼ ]"
        }
    }

    /// Alternate raw ASCII glyphs
    var asciiGlyph: String {
        switch self {
        case .player: return "▶"
        case .library: return "≡"
        case .exec: return ">_"
        case .theme: return "☼"
        }
    }

    /// Pipe-framed ASCII glyphs
    var asciiPipe: String {
        switch self {
        case .player: return "|▶|"
        case .library: return "|≡|"
        case .exec: return "|>_|"
        case .theme: return "|☼|"
        }
    }

    /// Leveled shortcut badge: uniform 5-7 chars (e.g. "1:PLAY")
    var badge: String {
        switch self {
        case .player: return "1:PLAY"
        case .library: return "2:LIB"
        case .exec: return "3:EXEC"
        case .theme: return "4:THEME"
        }
    }

    /// Short label without index (e.g. "PLAY")
    var shortTitle: String {
        switch self {
        case .player: return "PLAY"
        case .library: return "LIB"
        case .exec: return "EXEC"
        case .theme: return "THEME"
        }
    }

    /// Full human-readable title (used for accessibility)
    var title: String {
        switch self {
        case .player: return "PLAY"
        case .library: return "LIBRARY"
        case .exec: return "EXEC"
        case .theme: return "THEME"
        }
    }
}
