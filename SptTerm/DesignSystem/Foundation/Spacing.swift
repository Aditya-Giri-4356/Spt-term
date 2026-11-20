import CoreGraphics

enum TermSpace {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24

    static let gutter: CGFloat = 12
    static let margin: CGFloat = 16

    /// Minimum interactive envelope, even when the visual glyph is 9pt.
    static let hit: CGFloat = 44
    static let hitLarge: CGFloat = 48
}
