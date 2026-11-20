import SwiftUI

/// The single place fonts are created. Swap JetBrains Mono in here later:
/// `.custom("JetBrainsMono-Regular", size: size)` and nothing else changes.
enum TermFont {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

struct TermTypeToken: Hashable {
    let size: CGFloat
    let weight: Font.Weight
    let tracking: CGFloat
    let relativeTo: Font.TextStyle
    let isUppercase: Bool

    func scaled(by factor: CGFloat) -> CGFloat {
        size * min(max(factor, 1), 1.25)
    }
}

/// Type scale lifted from DESIGN.md.
enum TermType {
    static let headlineLG = TermTypeToken(size: 28, weight: .bold, tracking: -0.56, relativeTo: .largeTitle, isUppercase: false)
    static let headlineLGMobile = TermTypeToken(size: 22, weight: .bold, tracking: -0.22, relativeTo: .title2, isUppercase: false)
    static let headlineMD = TermTypeToken(size: 18, weight: .semibold, tracking: 0, relativeTo: .title3, isUppercase: false)
    static let bodyLG = TermTypeToken(size: 16, weight: .medium, tracking: 0, relativeTo: .body, isUppercase: false)
    static let bodyMD = TermTypeToken(size: 14, weight: .regular, tracking: 0, relativeTo: .body, isUppercase: false)
    static let bodySM = TermTypeToken(size: 12, weight: .regular, tracking: 0.24, relativeTo: .footnote, isUppercase: false)
    static let labelLG = TermTypeToken(size: 13, weight: .semibold, tracking: 0.65, relativeTo: .subheadline, isUppercase: true)
    static let labelMD = TermTypeToken(size: 11, weight: .medium, tracking: 0.66, relativeTo: .caption, isUppercase: true)
    static let labelSM = TermTypeToken(size: 9, weight: .semibold, tracking: 0.72, relativeTo: .caption2, isUppercase: true)

    /// Glyph-only sizes for the unicode transport/control characters.
    static let glyphLG = TermTypeToken(size: 22, weight: .bold, tracking: 0, relativeTo: .title2, isUppercase: false)
    static let glyphMD = TermTypeToken(size: 16, weight: .bold, tracking: 0, relativeTo: .body, isUppercase: false)
    static let glyphSM = TermTypeToken(size: 12, weight: .bold, tracking: 0, relativeTo: .caption, isUppercase: false)

    /// Dense telemetry strings (ASCII bars, meters, timestamps).
    static let telemetry = TermTypeToken(size: 12, weight: .regular, tracking: -0.2, relativeTo: .caption, isUppercase: false)
    static let telemetryTight = TermTypeToken(size: 10, weight: .regular, tracking: -0.4, relativeTo: .caption2, isUppercase: false)
}
