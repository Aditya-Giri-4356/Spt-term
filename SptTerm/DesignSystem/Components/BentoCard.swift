import SwiftUI

/// Compact telemetry card from the library showcase strip
/// (`[MOST_PLAYED] … 482 runs [FLAC]`).
struct BentoCard: View {
    @EnvironmentObject private var theme: TerminalTheme

    let label: String
    var labelTrailing: String?
    let title: String
    let subtitle: String
    var footerLeading: String?
    var badge: String?
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button {
                    TermHaptic.tap()
                    action()
                } label: {
                    card
                }
                .buttonStyle(TermPressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens \(title)")
            } else {
                card
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: TermSpace.xs) {
            HStack(spacing: TermSpace.xs) {
                Text(label)
                    .termType(TermType.labelSM, color: theme.palette.accent)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let labelTrailing {
                    Text(labelTrailing)
                        .termType(TermType.labelSM, color: theme.palette.textMuted)
                        .lineLimit(1)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .termType(TermType.bodyMD, color: theme.palette.accent)
                    .lineLimit(1)
                Text(subtitle)
                    .termType(TermType.telemetryTight, color: theme.palette.textSecondary)
                    .lineLimit(1)
            }
            HStack(spacing: TermSpace.xs) {
                if let footerLeading {
                    Text(footerLeading)
                        .termType(TermType.labelSM, color: theme.palette.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                if let badge {
                    StatusPill(text: badge, filled: true)
                }
            }
        }
        .padding(TermSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.background)
        .overlay(
            Rectangle()
                .strokeBorder(theme.palette.accentDeep, lineWidth: 1)
        )
    }
}

struct BentoCard_Previews: PreviewProvider {
    static var previews: some View {
        TerminalPreview {
            HStack(spacing: TermSpace.sm) {
                BentoCard(
                    label: "[MOST_PLAYED]",
                    labelTrailing: "96kHz/24b",
                    title: "Resonance (Remastered)",
                    subtitle: "HOME — Odyssey",
                    footerLeading: "▶ 482 runs",
                    badge: "[FLAC]"
                )
                BentoCard(
                    label: "[OFFLINE_DECK]",
                    labelTrailing: "100% OK",
                    title: "Nightcall",
                    subtitle: "Kavinsky — OutRun",
                    footerLeading: "Cached: 48.2MB",
                    badge: "[SYNCED]"
                )
            }
        }
    }
}
