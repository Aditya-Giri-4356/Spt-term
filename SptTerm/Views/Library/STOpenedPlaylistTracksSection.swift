import SwiftUI

/// Section in the LIB tab displaying tracks detected from an opened playlist in Spotify.
struct STOpenedPlaylistTracksSection: View {
    @ObservedObject var viewModel: LibraryViewModel
    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: TermSpace.xs) {
            headerBar

            if let status = viewModel.trackStatus {
                statusBanner(status)
            }

            if viewModel.openedPlaylistTracks.isEmpty {
                emptyState
            } else {
                trackList
            }
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: TermSpace.xs) {
            Text("TRACKS IN OPENED PLAYLIST (\(viewModel.openedPlaylistTracks.count)) - open a playlist in Spotify, press SCAN")
                .termType(TermType.telemetryTight, color: theme.palette.accent)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !viewModel.openedPlaylistTracks.isEmpty {
                Button {
                    TermHaptic.tap()
                    viewModel.clearOpenedTracks()
                } label: {
                    Text("[CLEAR]")
                        .termType(TermType.labelSM, color: theme.palette.amber)
                        .padding(.horizontal, TermSpace.sm)
                        .padding(.vertical, 5)
                        .background(theme.palette.background)
                        .overlay(Rectangle().strokeBorder(theme.palette.amber, lineWidth: 1))
                }
                .buttonStyle(TermPressStyle())
            }
        }
        .padding(.horizontal, TermSpace.sm)
        .padding(.vertical, 6)
        .background(theme.palette.panelRaised)
        .overlay(Rectangle().strokeBorder(theme.palette.accentDeep, lineWidth: 1))
    }

    private func statusBanner(_ message: String) -> some View {
        HStack(spacing: TermSpace.xs) {
            Text("[!]")
                .termType(TermType.labelSM, color: theme.palette.amber)
            Text(message)
                .termType(TermType.telemetryTight, color: theme.palette.amber)
                .lineLimit(2)
            Spacer()
            Button {
                viewModel.clearTrackStatus()
            } label: {
                Text("[X]")
                    .termType(TermType.telemetryTight, color: theme.palette.textMuted)
            }
        }
        .padding(.horizontal, TermSpace.sm)
        .padding(.vertical, 4)
        .background(theme.palette.background)
        .overlay(Rectangle().strokeBorder(theme.palette.amber, lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: TermSpace.xs) {
            Text("open a playlist in Spotify, press SCAN")
                .termType(TermType.bodySM, color: theme.palette.textMuted)
                .padding(.horizontal, TermSpace.sm)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.background)
        .overlay(Rectangle().strokeBorder(theme.palette.hairline, lineWidth: 1))
    }

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(viewModel.openedPlaylistTracks.enumerated()), id: \.offset) { idx, label in
                LibraryRow(
                    glyph: "♪",
                    title: label,
                    subtitle: "[\(idx + 1)]",
                    trailing: "PLAY"
                ) {
                    TermHaptic.tap()
                    viewModel.selectTrack(label)
                }
            }
        }
    }
}
