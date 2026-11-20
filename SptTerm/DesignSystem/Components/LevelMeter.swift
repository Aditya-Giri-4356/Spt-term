import SwiftUI

/// `L: [||||||||||||||||....] -4.2dB`
struct LevelMeter: View {
    @EnvironmentObject private var theme: TerminalTheme

    let label: String
    let level: Double
    var decibels: String
    var bars: Int = 20

    var body: some View {
        HStack(spacing: TermSpace.xs) {
            Text("\(label):")
                .termType(TermType.telemetryTight, color: theme.palette.accent)
            meterText
                .font(TermFont.mono(12, .regular))
                .tracking(-0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 0)
            Text(decibels)
                .termType(TermType.telemetryTight, color: theme.palette.cyan)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) channel")
        .accessibilityValue(decibels)
    }

    private var meterText: Text {
        let filled = Int((level.clampedUnit * Double(bars)).rounded())
        let empty = max(bars - filled, 0)
        let filledText = Text("[" + String(repeating: "|", count: filled))
            .foregroundColor(theme.palette.accent)
        let emptyText = Text(String(repeating: ".", count: empty) + "]")
            .foregroundColor(theme.palette.textMuted)
        return Text("\(filledText)\(emptyText)")
    }
}

struct LevelMeter_Previews: PreviewProvider {
    static var previews: some View {
        TerminalPreview {
            VStack(spacing: TermSpace.xs) {
                LevelMeter(label: "L", level: 0.8, decibels: "-4.2dB")
                LevelMeter(label: "R", level: 0.65, decibels: "-6.8dB")
            }
        }
    }
}
