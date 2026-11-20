import SwiftUI

/// Complete set of color tokens a screen is allowed to use.
/// Only eight themes ship hand-tuned values; every other theme derives a full
/// token set from `accent` + `background` so no per-theme code is required.
struct ThemePalette: Equatable {
    var background: Color
    var panel: Color
    var panelRaised: Color
    var accent: Color
    var accentDim: Color
    var accentDeep: Color
    var onAccent: Color
    var textPrimary: Color
    var textSecondary: Color
    var textMuted: Color
    var hairline: Color
    var cyan: Color
    var violet: Color
    var amber: Color
    var error: Color
    var isLight: Bool

    var glow: Color {
        TermColorMath.withAlpha(accent, isLight ? 0.16 : 0.35)
    }

    var softGlow: Color {
        TermColorMath.withAlpha(accent, isLight ? 0.10 : 0.18)
    }

    static func derived(accent: Color, background: Color) -> ThemePalette {
        let isLight = TermColorMath.luminance(background) > 0.45

        if isLight {
            let deep = TermColorMath.mix(accent, background, 0.55)
            return ThemePalette(
                background: background,
                panel: TermColorMath.mix(background, .black, 0.04),
                panelRaised: TermColorMath.mix(background, .black, 0.09),
                accent: accent,
                accentDim: TermColorMath.mix(accent, .black, 0.20),
                accentDeep: deep,
                onAccent: TermColorMath.luminance(accent) > 0.45 ? .black : .white,
                textPrimary: TermColorMath.mix(.black, accent, 0.12),
                textSecondary: TermColorMath.mix(.black, accent, 0.34),
                textMuted: TermColorMath.mix(background, .black, 0.55),
                hairline: TermColorMath.mix(accent, background, 0.74),
                cyan: Color(termHex: "#2F7E95"),
                violet: Color(termHex: "#6C4CB0"),
                amber: Color(termHex: "#A86A00"),
                error: Color(termHex: "#B3261E"),
                isLight: true
            )
        }

        let tintedPanel = TermColorMath.mix(TermColorMath.mix(background, .white, 0.035), accent, 0.05)
        let tintedRaised = TermColorMath.mix(TermColorMath.mix(background, .white, 0.07), accent, 0.07)
        return ThemePalette(
            background: background,
            panel: tintedPanel,
            panelRaised: tintedRaised,
            accent: accent,
            accentDim: TermColorMath.mix(accent, .black, 0.14),
            accentDeep: TermColorMath.mix(accent, background, 0.45),
            onAccent: TermColorMath.mix(background, .black, 0.85),
            textPrimary: TermColorMath.mix(.white, accent, 0.08),
            textSecondary: TermColorMath.mix(TermColorMath.mix(.white, accent, 0.30), background, 0.22),
            textMuted: TermColorMath.mix(accent, background, 0.52),
            hairline: TermColorMath.mix(accent, background, 0.62),
            cyan: Color(termHex: "#97CFE0"),
            violet: Color(termHex: "#BD93F9"),
            amber: Color(termHex: "#FFB000"),
            error: Color(termHex: "#FFB4AB"),
            isLight: false
        )
    }
}
