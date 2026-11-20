import SwiftUI

/// A glyph grid produced by the artwork provider. Phase 1 fills this with a
/// deterministic seed; real artwork can replace it behind `ArtworkProviding`.
struct ASCIIGlyphMatrix: Equatable {
    let rows: [String]

    var isEmpty: Bool { rows.isEmpty }

    func text() -> String {
        rows.joined(separator: "\n")
    }

    static let placeholder = ASCIIGlyphMatrix(rows: [
        "....####......",
        "..########....",
        ".##########...",
        "###.####.####.",
        "##..####..####",
        "#...####...###",
        "###.####.#####",
        "##..####..####",
        ".##########...",
        "..########....",
        "....####......",
        ".............."
    ])
}

/// Renders the character-grid album art used instead of raster covers.
struct ASCIIArtworkView: View {
    @EnvironmentObject private var theme: TerminalTheme

    let matrix: ASCIIGlyphMatrix
    var fontSize: CGFloat = 7
    var showsFrame: Bool = true
    var tint: Color?

    var body: some View {
        Text(matrix.text())
            .font(TermFont.mono(fontSize, .bold))
            .foregroundColor(tint ?? theme.palette.accent)
            .lineSpacing(1)
            .multilineTextAlignment(.leading)
            .minimumScaleFactor(0.4)
            .lineLimit(matrix.rows.count)
            .padding(TermSpace.xs)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.palette.background)
            .overlay {
                if showsFrame {
                    Rectangle()
                        .strokeBorder(TermColorMath.withAlpha(theme.palette.accentDeep, 0.9), lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }
}

struct ASCIIArtworkView_Previews: PreviewProvider {
    static var previews: some View {
        TerminalPreview {
            VStack(spacing: TermSpace.md) {
                ASCIIArtworkView(matrix: .placeholder)
                    .frame(width: 140, height: 120)
                ASCIIArtworkView(matrix: .placeholder, fontSize: 4, showsFrame: false)
                    .frame(width: 90, height: 70)
            }
        }
    }
}
