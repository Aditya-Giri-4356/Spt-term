import SwiftUI

/// Minimal ASCII synced lyrics panel.
/// Shows previous / current / next line, with current highlighted in the theme accent.
/// Nothing is rendered when lyrics are off or no lyrics are available.
struct NowPlayingLyricsPanel: View {
    @ObservedObject var viewModel: NowPlayingViewModel
    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        if STLyricsService.shared.isEnabled && !viewModel.activeLyrics.isEmpty {
            let lines = viewModel.activeLyrics
            let currentIndex = viewModel.currentLyricIndex
            let prevText = (currentIndex > 0 && currentIndex < lines.count) ? lines[currentIndex - 1].text : ""
            let currText = (currentIndex >= 0 && currentIndex < lines.count) ? lines[currentIndex].text : (lines.first?.text ?? "")
            let nextText = (currentIndex >= 0 && currentIndex + 1 < lines.count) ? lines[currentIndex + 1].text : (lines.count > 1 ? lines[1].text : "")

            ASCIIPanel(title: "LYRICS :: synced", trailing: "[LRCLIB]") {
                VStack(alignment: .leading, spacing: TermSpace.xs) {
                    if !prevText.isEmpty {
                        Text("  " + prevText)
                            .termType(TermType.bodySM, color: theme.palette.textMuted)
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Text("> " + currText)
                            .termType(TermType.bodySM, color: theme.palette.accent)
                            .lineLimit(1)
                        BlinkingCursor(width: 6, height: 12)
                    }
                    if !nextText.isEmpty {
                        Text("  " + nextText)
                            .termType(TermType.bodySM, color: theme.palette.textMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct NowPlayingLyricsPanel_Previews: PreviewProvider {
    static var previews: some View {
        TerminalAppPreview {
            NowPlayingLyricsPanel(viewModel: NowPlayingViewModel(
                player: PreviewServices().player,
                artworkProvider: PreviewServices().artwork
            ))
        }
    }
}
