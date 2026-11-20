import SwiftUI

/// Fixed top chrome shared by every screen: volume telemetry, wordmark,
/// user tag and the quick theme switcher.
struct TerminalHeader: View {
    @EnvironmentObject private var theme: TerminalTheme
    @Environment(\.playerService) private var playerService

    var subtitle: String = "Now Playing"
    var volume: Double? = nil
    var connectionLabel: String = "[pts/0] :: ONLINE"

    @State private var isDraggingVolume = false

    private var effectiveVolume: Double {
        volume ?? playerService.state.volume
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TermSpace.xs) {
            HStack(spacing: TermSpace.xs) {
                volumeControl
                Spacer(minLength: TermSpace.xs)
                Text(connectionLabel)
                    .termType(TermType.labelSM, color: theme.palette.cyan)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: TermSpace.xs) {
                Text("SPT.TERM V2.4.0")
                    .termType(TermType.headlineMD, color: theme.palette.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(":: \(subtitle)")
                    .termType(TermType.labelSM, color: theme.palette.textMuted)
                    .lineLimit(1)
                Spacer(minLength: TermSpace.xs)
                HStack(spacing: 2) {
                    Text("USER:")
                        .termType(TermType.labelSM, color: theme.palette.textMuted)
                    Text("[root]")
                        .termType(TermType.labelSM, color: theme.palette.textPrimary)
                }
            }

            HStack(spacing: TermSpace.xs) {
                Text("THEME:")
                    .termType(TermType.labelSM, color: theme.palette.textMuted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TermSpace.xs) {
                        ForEach(quickPicks) { definition in
                            themeChip(definition)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(.horizontal, TermSpace.gutter)
        .padding(.top, TermSpace.sm)
        .padding(.bottom, TermSpace.sm)
        .background(theme.palette.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.palette.hairline)
                .frame(height: 1)
        }
    }

    private var volumeControl: some View {
        Text(volumeMeter)
            .termType(TermType.labelSM, color: isDraggingVolume ? theme.palette.accent : theme.palette.accentDim)
            .lineLimit(1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDraggingVolume = true
                        let fraction = max(0, min(1, Double(value.location.x / 110.0)))
                        playerService.setVolume(fraction)
                    }
                    .onEnded { _ in
                        isDraggingVolume = false
                        TermHaptic.detent()
                    }
            )
            .accessibilityLabel("Volume: \(Int(effectiveVolume * 100))%")
    }

    private var volumeMeter: String {
        let filled = Int((effectiveVolume.clampedUnit * 10).rounded())
        return "[VOL: [" + String(repeating: "█", count: filled)
            + String(repeating: "░", count: max(10 - filled, 0)) + "]]"
    }

    private var quickPicks: [ThemeDefinition] {
        ThemeCatalog.quickPicks.compactMap { id in
            theme.catalog.first { $0.id == id }
        }
    }

    private func themeChip(_ definition: ThemeDefinition) -> some View {
        let isActive = theme.themeID == definition.id && !theme.isCustomAccent
        return Button {
            theme.select(definition.id)
            TermHaptic.tap()
        } label: {
            Text(isActive ? "[*\(definition.name)]" : "[\(definition.name)]")
                .termType(TermType.labelSM, color: isActive ? theme.palette.onAccent : theme.palette.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(isActive ? theme.palette.accent : Color.clear)
                .overlay(
                    Rectangle()
                        .strokeBorder(
                            isActive ? theme.palette.accent : TermColorMath.withAlpha(theme.palette.hairline, 0.9),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(TermPressStyle())
        .accessibilityLabel(Text("Theme \(definition.name)"))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

struct TerminalHeader_Previews: PreviewProvider {
    static var previews: some View {
        TerminalScreenPreview {
            VStack(spacing: 0) {
                TerminalHeader()
                Spacer()
            }
        }
    }
}
