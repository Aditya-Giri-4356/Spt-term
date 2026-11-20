import SwiftUI

/// `[====================>--------------------]`
struct ASCIIProgressBar: View {
    @EnvironmentObject private var theme: TerminalTheme

    var progress: Double
    var width: Int = 38
    var showsHead: Bool = true
    var fontSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 0) {
            Text("[")
                .foregroundColor(theme.palette.textMuted)
            Text(filledPart)
                .foregroundColor(theme.palette.accent)
                .phosphorGlow(theme.palette.accent, radius: 5, intensity: 0.8)
            Text(emptyPart)
                .foregroundColor(theme.palette.textMuted)
            Text("]")
                .foregroundColor(theme.palette.textMuted)
        }
        .font(TermFont.mono(fontSize, .bold))
        .tracking(-0.4)
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue(TermFormat.percent(progress.clampedUnit, decimals: 0))
    }

    private var cells: Int { max(width, 1) }

    private var filledCount: Int {
        Int((Double(cells) * progress.clampedUnit).rounded())
    }

    private var filledPart: String {
        let count = min(max(filledCount, 0), cells)
        if count == 0 { return "" }
        if count >= cells { return String(repeating: "=", count: cells) }
        if showsHead {
            return String(repeating: "=", count: count - 1) + ">"
        }
        return String(repeating: "=", count: count)
    }

    private var emptyPart: String {
        String(repeating: "-", count: max(cells - filledCount, 0))
    }
}

struct ASCIIProgressBar_Previews: PreviewProvider {
    static var previews: some View {
        TerminalPreview {
            VStack(spacing: TermSpace.sm) {
                ASCIIProgressBar(progress: 0)
                ASCIIProgressBar(progress: 0.32)
                ASCIIProgressBar(progress: 0.65)
                ASCIIProgressBar(progress: 1)
            }
        }
    }
}
