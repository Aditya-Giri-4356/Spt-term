import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var viewModel: NowPlayingViewModel
    @Binding var isExpanded: Bool
    var namespace: Namespace.ID
    var onTap: (() -> Void)? = nil

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        Button {
            TermHaptic.tap()
            if let onTap { onTap() } else {
                withAnimation(TermMotion.expand) { isExpanded = true }
            }
        } label: {
            HStack(spacing: TermSpace.sm) {
                ASCIIArtworkView(
                    matrix: viewModel.artwork.matrix,
                    fontSize: 4,
                    showsFrame: false,
                    tint: viewModel.artwork.accent
                )
                .frame(width: 34, height: 34)
                .matchedGeometryEffect(id: "playbackArtwork", in: namespace)
                .overlay(Rectangle().strokeBorder(theme.palette.accentDeep, lineWidth: 1))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Track: \(viewModel.state.currentTrack?.title ?? "No Track")")
                        .termType(TermType.bodySM, color: theme.palette.textPrimary)
                        .lineLimit(1)
                    Text(viewModel.state.currentTrack?.artistName ?? "—")
                        .termType(TermType.telemetryTight, color: theme.palette.textMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ASCIIProgressBar(progress: viewModel.state.progressFraction, width: 12, fontSize: 9)
                    .frame(width: 72)

                Button {
                    viewModel.playPause()
                } label: {
                    Text(viewModel.state.isPlaying ? "[❚❚]" : "[▶]")
                        .termType(TermType.labelMD, color: theme.palette.accent)
                        .frame(minWidth: TermSpace.hit, minHeight: TermSpace.hit)
                }
                .buttonStyle(TermPressStyle())

                Button {
                    viewModel.next()
                } label: {
                    Text("[>>]")
                        .termType(TermType.labelMD, color: theme.palette.textSecondary)
                        .frame(minWidth: TermSpace.hit, minHeight: TermSpace.hit)
                }
                .buttonStyle(TermPressStyle())
            }
            .padding(.horizontal, TermSpace.sm)
            .padding(.vertical, 6)
            .background(theme.palette.panelRaised)
            .overlay(Rectangle().strokeBorder(theme.palette.accentDeep, lineWidth: 1))
        }
        .buttonStyle(TermPressStyle())
        .accessibilityLabel("Mini player")
        .accessibilityHint("Expands to Now Playing")
    }
}

struct MiniPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        TerminalAppPreview {
            MiniPlayerPreview()
        }
    }

    private struct MiniPlayerPreview: View {
        @State private var isExpanded = false
        @Namespace private var namespace
        @StateObject private var viewModel = NowPlayingViewModel(
            player: PreviewServices().player,
            artworkProvider: PreviewServices().artwork
        )

        var body: some View {
            VStack {
                Spacer()
                MiniPlayerView(viewModel: viewModel, isExpanded: $isExpanded, namespace: namespace)
            }
            .padding(TermSpace.md)
        }
    }
}
