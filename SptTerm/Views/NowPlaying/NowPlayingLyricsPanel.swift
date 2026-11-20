import SwiftUI

struct NowPlayingLyricsPanel: View {
    @ObservedObject var viewModel: NowPlayingViewModel

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        ASCIIPanel(title: "LYRICS_STREAM :: buffer/live", trailing: "[SYNC: OK]") {
            VStack(alignment: .leading, spacing: TermSpace.xs) {
                if let track = viewModel.currentTrack, !track.lyrics.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(track.lyrics.enumerated()), id: \.offset) { index, line in
                                    lyricRow(index: index, line: line, isActive: index == viewModel.currentLyricIndex)
                                        .id(index)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 150)
                        .task(id: viewModel.currentLyricIndex) {
                            guard viewModel.currentLyricIndex >= 0 else { return }
                            withAnimation(TermMotion.panel) {
                                proxy.scrollTo(viewModel.currentLyricIndex, anchor: .center)
                            }
                        }
                    }
                } else {
                    Text("NO LYRICS BUFFERED")
                        .termType(TermType.bodySM, color: theme.palette.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Rectangle()
                    .fill(theme.palette.hairline)
                    .frame(height: 1)

                HStack {
                    Text("└────────────────────────────────────┘")
                        .termType(TermType.telemetryTight, color: theme.palette.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Spacer()
                    Text("BUF: 512KB [OK]")
                        .termType(TermType.telemetryTight, color: theme.palette.textSecondary)
                }
            }
        }
    }

    private func lyricRow(index: Int, line: LyricsLine, isActive: Bool) -> some View {
        HStack(alignment: .top, spacing: TermSpace.xs) {
            Text(line.timeLabel)
                .termType(TermType.telemetryTight, color: isActive ? theme.palette.accent : theme.palette.textMuted)
                .frame(width: 34, alignment: .leading)

            Text(">")
                .termType(TermType.telemetryTight, color: isActive ? theme.palette.accent : theme.palette.textMuted)

            if isActive {
                HStack(spacing: 4) {
                    Text("CURRENT")
                        .termType(TermType.labelSM, color: theme.palette.onAccent)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(theme.palette.accent)
                    Text(line.text)
                        .termType(TermType.bodySM, color: theme.palette.accent)
                        .lineLimit(1)
                    BlinkingCursor(width: 6, height: 12)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, TermSpace.xs)
                .background(theme.palette.panelRaised)
                .phosphorGlow(theme.palette.accent, radius: 6, intensity: 0.5)
            } else {
                Text(line.text)
                    .termType(TermType.bodySM, color: theme.palette.textSecondary)
                    .lineLimit(1)
                    .padding(.vertical, 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(line.timeLabel): \(line.text)")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

struct NowPlayingLyricsPanel_Previews: PreviewProvider {
    static var previews: some View {
        TerminalAppPreview {
            LyricsPreview()
        }
    }

    private struct LyricsPreview: View {
        @StateObject private var viewModel = NowPlayingViewModel(
            player: PreviewServices().player,
            artworkProvider: PreviewServices().artwork
        )

        var body: some View {
            ScrollView {
                NowPlayingLyricsPanel(viewModel: viewModel)
                    .padding(TermSpace.md)
            }
        }
    }
}
