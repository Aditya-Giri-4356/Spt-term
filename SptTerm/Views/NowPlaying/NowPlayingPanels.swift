import SwiftUI

struct NowPlayingSpectrumPanel: View {
    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        ASCIIPanel(title: "DSP :: SPECTRUM_FFT_1024", trailing: "UI ONLY") {
            VStack(alignment: .leading, spacing: TermSpace.xs) {
                Text("UI ONLY - does not process Spotify audio")
                    .termType(TermType.telemetryTight, color: theme.palette.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LiveSpectrumBars(columns: 9)
                    .frame(height: 64)
                    .padding(.horizontal, TermSpace.xs)
                HStack {
                    ForEach(["60Hz", "120Hz", "250Hz", "500Hz", "1kHz", "2kHz", "4kHz", "8kHz", "16kHz"], id: \.self) { label in
                        Text(label)
                            .termType(TermType.telemetryTight, color: theme.palette.textMuted)
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
                Rectangle().fill(theme.palette.hairline).frame(height: 1)
                HStack(spacing: TermSpace.sm) {
                    LevelMeter(label: "L", level: 0.78, decibels: "-4.2dB")
                    LevelMeter(label: "R", level: 0.62, decibels: "-6.8dB")
                }
            }
        }
    }
}

struct NowPlayingScrubberPanel: View {
    @ObservedObject var viewModel: NowPlayingViewModel
    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        let isSeekSupported = viewModel.state.isSeekSupported
        let trailing = isSeekSupported ? "POS: \(TermFormat.percent(viewModel.state.progressFraction))" : "SEEK N/A"

        ASCIIPanel(title: "SEEK & VOLUME", trailing: trailing) {
            VStack(alignment: .leading, spacing: TermSpace.sm) {
                TimeScrubber(
                    progress: viewModel.progressBinding,
                    duration: viewModel.state.duration,
                    onSeek: { fraction in
                        if isSeekSupported {
                            viewModel.seek(fraction)
                        }
                    },
                    isReadOnly: !isSeekSupported
                )

                HStack(spacing: TermSpace.xs) {
                    Text("VOL:")
                        .termType(TermType.telemetryTight, color: theme.palette.textMuted)
                    TermSlider(
                        value: viewModel.volumeBinding,
                        label: "",
                        valueText: "\(Int(viewModel.state.volume * 100))%",
                        cells: 14
                    )
                }
            }
        }
    }
}

struct NowPlayingCommandLine: View {
    @ObservedObject var viewModel: NowPlayingViewModel
    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        HStack(spacing: TermSpace.xs) {
            Text("spt.term:~$")
                .termType(TermType.telemetry, color: theme.palette.cyan)
            Text("mpris:playback --volume=\(Int(viewModel.state.volume * 100))%")
                .termType(TermType.telemetry, color: theme.palette.accentDim)
                .lineLimit(1)
            BlinkingCursor()
            Spacer(minLength: 0)
            Text("[ENTER]")
                .termType(TermType.labelSM, color: theme.palette.textMuted)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .overlay(Rectangle().strokeBorder(theme.palette.hairline, lineWidth: 1))
        }
        .padding(TermSpace.sm)
        .background(theme.palette.panelRaised)
        .overlay(Rectangle().strokeBorder(theme.palette.accentDeep, lineWidth: 1))
    }
}

struct NowPlayingPanels_Previews: PreviewProvider {
    static var previews: some View {
        TerminalAppPreview {
            NowPlayingPanelsPreview()
        }
    }

    private struct NowPlayingPanelsPreview: View {
        @StateObject private var viewModel = NowPlayingViewModel(
            player: PreviewServices().player,
            artworkProvider: PreviewServices().artwork
        )

        var body: some View {
            ScrollView {
                VStack(spacing: TermSpace.md) {
                    NowPlayingSpectrumPanel()
                    NowPlayingScrubberPanel(viewModel: viewModel)
                    NowPlayingCommandLine(viewModel: viewModel)
                }
                .padding(TermSpace.md)
            }
        }
    }
}
