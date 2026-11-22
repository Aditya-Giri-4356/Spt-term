import SwiftUI

/// Section in the LIB tab displaying discovered Spotify playlists above the session library.
struct STPlaylistCacheSection: View {
    @ObservedObject var viewModel: LibraryViewModel
    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: TermSpace.xs) {
            headerBar

            if let status = viewModel.playlistStatus {
                statusBanner(status)
            }

            if viewModel.cachedPlaylists.isEmpty {
                emptyState
            } else {
                playlistList
            }
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: TermSpace.xs) {
            Text("PLAYLISTS (\(viewModel.cachedPlaylists.count)) - open Spotify > Your Library, scroll, press SCAN")
                .termType(TermType.telemetryTight, color: theme.palette.accent)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                TermHaptic.tap()
                Task {
                    await viewModel.scanPlaylists()
                }
            } label: {
                Text(viewModel.isScanning ? "[...]" : "[SCAN]")
                    .termType(TermType.labelSM, color: theme.palette.onAccent)
                    .padding(.horizontal, TermSpace.sm)
                    .padding(.vertical, 5)
                    .background(theme.palette.accent)
                    .overlay(Rectangle().strokeBorder(theme.palette.accent, lineWidth: 1))
            }
            .buttonStyle(TermPressStyle())
            .disabled(viewModel.isScanning)

            Button {
                TermHaptic.tap()
                Task {
                    await viewModel.scanAll()
                }
            } label: {
                Text(viewModel.isScanning ? "[...]" : "[SCAN ALL]")
                    .termType(TermType.labelSM, color: theme.palette.onAccent)
                    .padding(.horizontal, TermSpace.sm)
                    .padding(.vertical, 5)
                    .background(theme.palette.accent)
                    .overlay(Rectangle().strokeBorder(theme.palette.accent, lineWidth: 1))
            }
            .buttonStyle(TermPressStyle())
            .disabled(viewModel.isScanning)
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
                viewModel.clearPlaylistStatus()
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
            Text("open Spotify > Your Library, scroll, press SCAN")
                .termType(TermType.bodySM, color: theme.palette.textMuted)
                .padding(.horizontal, TermSpace.sm)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.background)
        .overlay(Rectangle().strokeBorder(theme.palette.hairline, lineWidth: 1))
    }

    private var playlistList: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.cachedPlaylists) { item in
                LibraryRow(
                    glyph: "♫",
                    title: item.name,
                    subtitle: item.label,
                    trailing: "SELECT"
                ) {
                    TermHaptic.tap()
                    viewModel.selectPlaylist(item)
                }
            }
        }
    }
}
