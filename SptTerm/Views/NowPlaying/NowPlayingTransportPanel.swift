import SwiftUI

struct NowPlayingTransportPanel: View {
    @ObservedObject var viewModel: NowPlayingViewModel

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        ASCIIPanel(title: "TOUCH TUI :: PRIMARY CONTROLS", trailing: "FIFO READY") {
            VStack(spacing: TermSpace.sm) {
                HStack(spacing: TermSpace.xs) {
                    transportButton(
                        glyph: "⤮",
                        label: viewModel.shuffleLabel,
                        isActive: viewModel.state.isShuffled && viewModel.state.isShuffleSupported,
                        action: viewModel.toggleShuffle
                    )
                    transportButton(
                        glyph: "⏮",
                        label: nil,
                        isActive: false,
                        action: viewModel.previous
                    )
                    playPauseButton
                    transportButton(
                        glyph: "⏭",
                        label: nil,
                        isActive: false,
                        action: viewModel.next
                    )
                    transportButton(
                        glyph: viewModel.repeatSymbol,
                        label: viewModel.repeatLabel,
                        isActive: viewModel.state.repeatMode != .off && viewModel.state.isRepeatSupported,
                        action: viewModel.cycleRepeat
                    )
                }

                Rectangle()
                    .fill(theme.palette.hairline)
                    .frame(height: 1)

                HStack(spacing: TermSpace.xs) {
                    BracketButton(
                        title: "Liked",
                        glyph: viewModel.state.isCurrentTrackLiked ? "★" : "☆",
                        variant: viewModel.state.isCurrentTrackLiked ? .primary : .ghost,
                        isActive: viewModel.state.isCurrentTrackLiked
                    ) {
                        viewModel.toggleLike()
                    }
                    BracketButton(title: "AirPlay", glyph: "↗", variant: .ghost) {
                        TermHaptic.tap()
                    }
                    BracketButton(
                        title: "Queue:\(viewModel.state.queue.count)",
                        glyph: "☰",
                        variant: .ghost
                    ) {
                        TermHaptic.tap()
                    }
                }
            }
        }
    }

    private var playPauseButton: some View {
        Button {
            viewModel.playPause()
        } label: {
            Text(viewModel.state.isPlaying ? "❚❚" : "▶")
                .termType(TermType.glyphLG, color: theme.palette.onAccent)
                .frame(maxWidth: .infinity, minHeight: TermSpace.hitLarge)
                .background(theme.palette.accent)
                .overlay(Rectangle().strokeBorder(theme.palette.accent, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: TermRadius.button))
                .phosphorGlow(theme.palette.accent, radius: 12, intensity: 0.7)
        }
        .buttonStyle(TermPressStyle())
        .accessibilityLabel(viewModel.state.isPlaying ? "Pause" : "Play")
    }

    private func transportButton(
        glyph: String,
        label: String?,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            VStack(spacing: 2) {
                Text(glyph)
                    .termType(TermType.glyphMD)
                if let label {
                    Text(label)
                        .termType(TermType.labelSM)
                }
            }
            .foregroundColor(isActive ? theme.palette.onAccent : theme.palette.accent)
            .frame(maxWidth: .infinity, minHeight: TermSpace.hitLarge)
            .background(isActive ? theme.palette.accent : theme.palette.background)
            .overlay(Rectangle().strokeBorder(isActive ? theme.palette.accent : theme.palette.accentDeep, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: TermRadius.button))
        }
        .buttonStyle(TermPressStyle())
    }
}

struct NowPlayingTransportPanel_Previews: PreviewProvider {
    static var previews: some View {
        TerminalAppPreview {
            TransportPreview()
        }
    }

    private struct TransportPreview: View {
        @StateObject private var viewModel = NowPlayingViewModel(
            player: PreviewServices().player,
            artworkProvider: PreviewServices().artwork
        )

        var body: some View {
            ScrollView {
                NowPlayingTransportPanel(viewModel: viewModel)
                    .padding(TermSpace.md)
            }
        }
    }
}
