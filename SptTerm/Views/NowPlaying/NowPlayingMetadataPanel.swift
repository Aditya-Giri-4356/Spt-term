import SwiftUI

struct NowPlayingMetadataPanel: View {
    @ObservedObject var viewModel: NowPlayingViewModel
    var namespace: Namespace.ID

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        VStack(spacing: TermSpace.md) {
            ASCIIPanel(title: "ALBUM ART :: ASCII", trailing: "[EMBEDDED]") {
                ASCIIArtworkView(
                    matrix: viewModel.artwork.matrix,
                    fontSize: 6,
                    tint: viewModel.artwork.accent
                )
                .frame(height: 118)
                .matchedGeometryEffect(id: "playbackArtwork", in: namespace)
            }

            ASCIIPanel(title: "NOW PLAYING :: PID 4092", trailing: "spt.term:~$") {
                VStack(alignment: .leading, spacing: TermSpace.xs) {
                    HStack(spacing: TermSpace.xs) {
                        Circle()
                            .fill(theme.palette.accent)
                            .frame(width: 6, height: 6)
                            .phosphorGlow(theme.palette.accent, radius: 4)
                        Text("META_TAGS")
                            .termType(TermType.labelSM, color: theme.palette.textMuted)
                        Spacer()
                        Text("[ID3v2.4]")
                            .termType(TermType.labelSM, color: theme.palette.cyan)
                    }

                    if let track = viewModel.currentTrack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TRACK")
                                .termType(TermType.labelSM, color: theme.palette.textMuted)
                            Text(track.title)
                                .termType(TermType.headlineLGMobile, color: theme.palette.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("ARTIST")
                                .termType(TermType.labelSM, color: theme.palette.textMuted)
                            Text(track.artistName)
                                .termType(TermType.bodyLG, color: theme.palette.accentDim)
                                .lineLimit(1)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("ALBUM")
                                .termType(TermType.labelSM, color: theme.palette.textMuted)
                            Text("\(track.albumTitle) (\(track.year))")
                                .termType(TermType.bodyMD, color: theme.palette.textSecondary)
                                .lineLimit(1)
                        }

                        Rectangle()
                            .fill(theme.palette.hairline)
                            .frame(height: 1)
                            .padding(.vertical, 2)

                        telemetryRow(label: "FORMAT:", value: track.formatLabel.uppercased() + " / 24-bit / 96kHz", valueColor: theme.palette.accent)
                        telemetryRow(label: "BITRATE:", value: track.bitrateLabel + " (lossless)", valueColor: theme.palette.cyan)
                        telemetryRow(label: "SINK:", value: "AirPods Pro 2 [AAC-ELD]", valueColor: theme.palette.accentDim)
                    } else {
                        Text("NO TRACK LOADED")
                            .termType(TermType.bodyMD, color: theme.palette.textMuted)
                    }
                }
            }
        }
    }

    private func telemetryRow(label: String, value: String, valueColor: Color) -> some View {
        HStack {
            Text(label)
                .termType(TermType.telemetryTight, color: theme.palette.textMuted)
            Spacer()
            Text(value)
                .termType(TermType.telemetryTight, color: valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct NowPlayingMetadataPanel_Previews: PreviewProvider {
    static var previews: some View {
        TerminalAppPreview {
            MetadataPreview()
        }
    }

    private struct MetadataPreview: View {
        @Namespace private var namespace
        @StateObject private var viewModel = NowPlayingViewModel(
            player: PreviewServices().player,
            artworkProvider: PreviewServices().artwork
        )

        var body: some View {
            ScrollView {
                NowPlayingMetadataPanel(viewModel: viewModel, namespace: namespace)
                    .padding(TermSpace.md)
            }
        }
    }
}
