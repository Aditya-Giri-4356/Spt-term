import SwiftUI

/// One selectable entry in the theme matrix.
struct ThemeDefinition: Identifiable, Hashable {
    let id: String
    let number: Int
    let name: String
    let detail: String
    let accentHex: String
    let backgroundHex: String

    var accent: Color { Color(termHex: accentHex) }
    var background: Color { Color(termHex: backgroundHex) }

    /// Hand-tuned palette when available, otherwise fully derived tokens.
    var palette: ThemePalette {
        ThemePalette.handTuned[id] ?? .derived(accent: accent, background: background)
    }

    var listNumber: String {
        String(format: "%02d", number)
    }

    static func == (lhs: ThemeDefinition, rhs: ThemeDefinition) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum ThemeCatalog {
    static let defaultID = "phosphor"

    static let quickPicks: [String] = all.map(\.id)

    static let all: [ThemeDefinition] = [
        entry("phosphor", 0, "Phosphor Matrix", "IBM 5151 Monochrome / VT100 Green", "#00FF66", "#000000"),
        entry("1976", 1, "1976", "Warm Orange, Golden Yellow & Red Retro Stripes", "#FF9D2E", "#160F08"),
        entry("8008", 2, "8008", "Slate Navy, Soft Gray & Neon Magenta", "#FF4F8B", "#181D27"),
        entry("9009", 3, "9009", "Classic Cherry Vintage Beige & Muted Accent Gray", "#D8C7A8", "#171614"),
        entry("aurora", 4, "Aurora", "Electric Cyan to Synthwave Magenta Polar Glow", "#4DEEEA", "#08121A"),
        entry("burgundy", 5, "Burgundy", "Deep Wine Maroon & Crimson Velvet", "#C8384F", "#130A0C"),
        entry("carbon", 6, "Carbon", "Charcoal Gray & Industrial Warning Orange", "#FF8A1F", "#111111"),
        entry("dark", 7, "Dark", "Classic Obsidian Black & Crisp White Terminal", "#FFFFFF", "#000000"),
        entry("denim", 8, "Denim", "Washed Indigo Blue-Gray & Amber Gold Stitch", "#E0A458", "#161F29"),
        entry("dots", 9, "Dots", "Biip Minimalist Slate with Multicolored Code Dots", "#8FB6D9", "#1B1E23"),
        entry("dracula", 10, "Dracula", "#BD93F9 Goth Vampire Purple, Lavender & Pink", "#BD93F9", "#1E1F29"),
        entry("eclipse", 11, "Eclipse", "Steel Navy, Twilight Slate & Lunar Yellow Rim", "#FFD866", "#0E1A2B"),
        entry("gruvbox", 12, "Gruvbox", "Retro Warm Earthy Espresso & Golden Amber", "#FABD2F", "#1D2021"),
        entry("handarbeit", 13, "Handarbeit", "Bauhaus Craft Red, Royal Blue, Teal & Gold", "#E8443B", "#1C1C1C"),
        entry("hyperfuse", 14, "Hyperfuse", "Purple-Tinted Industrial Gray & Electric Violet", "#B78BFF", "#1B1D26"),
        entry("light", 15, "Light", "High-Contrast Clean Chalk White Monochrome", "#111111", "#FFFFFF"),
        entry("mizu", 16, "Mizu", "Serene Japanese Water Navy & Icy Cool Teal", "#6FC3C7", "#101B1E"),
        entry("modern-dolch", 17, "Modern Dolch", "Cool Charcoal Slate & Cyan/Teal Modern Accents", "#7ECFD1", "#1E2123"),
        entry("monokai", 18, "Monokai", "Matte Black, Lime Green, Yellow & Magenta", "#A6E22E", "#1E1F1C"),
        entry("mr-sleeves", 19, "Mr Sleeves", "Silver-Chalk Gray & Pastel Blush Pink Accents", "#F2C9D4", "#22222A"),
        entry("nautilus", 20, "Nautilus", "Deep Ocean Navy, Sea Teal & Marigold Yellow", "#F2C230", "#0B1B2B"),
        entry("nord", 21, "Nord", "Arctic Polar Night Slate & Glacial Frost Blue", "#88C0D0", "#2E3440"),
        entry("oblivion", 22, "Oblivion", "Git Graphite Gray & Multi-Token Code Syntax", "#A8B5C4", "#111418"),
        entry("olivia", 23, "Olivia", "Deep Espresso Noir & Luxe Rose Gold Accents", "#F2C7C2", "#17120F"),
        entry("phantom", 24, "Phantom", "Abyssal Violet-Black & Regal Gilded Gold", "#C7A252", "#120E16"),
        entry("rama", 25, "Rama", "Clean Works Cream Ivory & Signature Industrial Yellow", "#B58B14", "#EFE9DC"),
        entry("sakura", 26, "Sakura", "Japanese Cherry Blossom Pastel Pink & Pure White", "#E5668F", "#FFF6F8"),
        entry("serika", 27, "Serika", "Asphalt Dark Gray & Canary Warning Yellow", "#FFCE1F", "#212121"),
        entry("solarized-dark", 28, "Solarized Dark", "Ethan Schoonover Deep Cyan-Teal & Low-Contrast Slate", "#2AA198", "#002B36"),
        entry("solarized-light", 29, "Solarized Light", "Warm Parchment Cream & Solarized Cyan Accents", "#859900", "#FDF6E3"),
        entry("vilebloom", 30, "Vilebloom", "Split Retro Blue-Teal & Orchid Bloom Magenta", "#F06A9B", "#141A22"),
        entry("yuri", 31, "Yuri", "Aerospace Navy Blue & Cosmonaut Rocket Red", "#FF4D4D", "#0D1A2E"),
        entry("honeywell", 32, "Honeywell", "Industrial Battleship Slate & Crimson Emergency", "#E03E3E", "#2A2A2A"),
        entry("space-cadet", 33, "Space Cadet", "MIT Lisp Symbolics Royal Blue & Stark White", "#7B8CFF", "#1A1A2E"),
        entry("godspeed", 34, "Godspeed", "Apollo Lunar Flight Computer Yellow & Cockpit Navy", "#FFD34D", "#1B2733"),
        entry("leviathan", 35, "Leviathan", "Abyssal Deep-Trench Navy & Radioactive Phosphor", "#4DF08C", "#0A1219"),
        entry("kobayashi", 36, "Kobayashi", "Hazard Safety Yellow, Crimson Red & Carbon Black", "#FFC400", "#141414"),
        entry("amber", 37, "Amber CRT", "Classic P3 Amber Phosphor Beam & Warm Enclosure", "#FFB000", "#0B0803")
    ]

    static func definition(for id: String) -> ThemeDefinition {
        let clean = id.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        return all.first {
            $0.id == id || $0.id.lowercased().replacingOccurrences(of: "-", with: "") == clean
        } ?? all[0]
    }

    private static func entry(
        _ id: String,
        _ number: Int,
        _ name: String,
        _ detail: String,
        _ accent: String,
        _ background: String
    ) -> ThemeDefinition {
        ThemeDefinition(
            id: id,
            number: number,
            name: name,
            detail: detail,
            accentHex: accent,
            backgroundHex: background
        )
    }
}
