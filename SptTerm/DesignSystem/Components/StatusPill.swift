import SwiftUI

/// `[ FLAC 96k ]`-style telemetry chip.
struct StatusPill: View {
    enum Tone {
        case accent
        case cyan
        case violet
        case amber
        case muted
    }

    @EnvironmentObject private var theme: TerminalTheme
    let text: String
    var tone: Tone = .accent
    var filled: Bool = false

    var body: some View {
        Text(text)
            .termType(TermType.labelSM, color: filled ? theme.palette.onAccent : tint)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(filled ? tint : theme.palette.background)
            .overlay(
                Rectangle()
                    .strokeBorder(filled ? tint : TermColorMath.withAlpha(tint, 0.55), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: TermRadius.tag))
            .accessibilityLabel(Text(text))
    }

    private var tint: Color {
        switch tone {
        case .accent: return theme.palette.accent
        case .cyan: return theme.palette.cyan
        case .violet: return theme.palette.violet
        case .amber: return theme.palette.amber
        case .muted: return theme.palette.textMuted
        }
    }
}

struct StatusPill_Previews: PreviewProvider {
    static var previews: some View {
        TerminalPreview {
            VStack(spacing: TermSpace.sm) {
                HStack(spacing: TermSpace.xs) {
                    StatusPill(text: "[ FLAC 96k ]")
                    StatusPill(text: "[ LIVE ]", tone: .cyan)
                    StatusPill(text: "[ SHUFFLE: OFF ]", tone: .violet)
                    StatusPill(text: "[ SYNCED ]", filled: true)
                }
                HStack(spacing: TermSpace.xs) {
                    StatusPill(text: "[ OFFLINE ]", tone: .muted)
                    StatusPill(text: "[ ERROR ]", tone: .amber)
                }
            }
        }
    }
}
