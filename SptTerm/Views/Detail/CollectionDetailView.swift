import SwiftUI

struct CollectionDetailView: View {
    let title: String
    let subtitle: String
    let artwork: TrackArtwork
    let tracks: [Track]
    let player: PlayerServiceProtocol
    let isLoading: Bool
    let errorMessage: String?
    let onPlayAll: () -> Void
    let onShuffle: () -> Void
    let onTrackTap: (Track) -> Void
    let onTrackContext: (Track) -> Void

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: TermSpace.md) {
                ASCIIPanel(title: "COLLECTION", trailing: "detail") {
                    HStack(spacing: TermSpace.sm) {
                        ASCIIArtworkView(matrix: artwork.matrix, fontSize: 6, tint: artwork.accent)
                            .frame(width: 118, height: 104)
                            .overlay(Rectangle().strokeBorder(theme.palette.accentDeep, lineWidth: 1))
                        VStack(alignment: .leading, spacing: TermSpace.xs) {
                            Text(title)
                                .termType(TermType.headlineLGMobile, color: theme.palette.textPrimary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                            Text(subtitle)
                                .termType(TermType.bodySM, color: theme.palette.textSecondary)
                                .lineLimit(3)
                            StatusPill(text: "[ \(tracks.count) tracks ]", tone: .cyan, filled: false)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack(spacing: TermSpace.xs) {
                    BracketButton(title: "Play All", glyph: "▶", variant: .primary) { onPlayAll() }
                    BracketButton(title: "Shuffle", glyph: "⤮") { onShuffle() }
                }

                if isLoading {
                    ASCIIPanel(title: "TRACKS", trailing: "loading") {
                        Text("BUFFERING TRACK LIST…")
                            .termType(TermType.bodySM, color: theme.palette.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if let error = errorMessage {
                    ASCIIPanel(title: "TRACKS", trailing: "error") {
                        Text(error)
                            .termType(TermType.bodySM, color: theme.palette.amber)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if tracks.isEmpty {
                    ASCIIPanel(title: "TRACKS", trailing: "empty") {
                        Text("NO TRACKS IN THIS COLLECTION")
                            .termType(TermType.bodySM, color: theme.palette.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ASCIIPanel(title: "TRACKS", trailing: "\(tracks.count) entries") {
                        VStack(spacing: 0) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                trackRow(index: index + 1, track: track)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, TermSpace.gutter)
            .padding(.top, TermSpace.sm)
            .padding(.bottom, TermSpace.xl)
        }
        .background(theme.palette.background.ignoresSafeArea())
    }

    private func trackRow(index: Int, track: Track) -> some View {
        let isCurrent = track.id == player.state.currentTrack?.id
        return HStack(spacing: TermSpace.xs) {
            Button {
                onTrackTap(track)
            } label: {
                HStack(spacing: TermSpace.xs) {
                    Text(isCurrent ? "▶" : String(format: "%02d", index))
                        .termType(TermType.telemetryTight, color: isCurrent ? theme.palette.accent : theme.palette.textMuted)
                        .frame(width: 22, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title)
                            .termType(TermType.bodySM, color: isCurrent ? theme.palette.accent : theme.palette.textPrimary)
                            .lineLimit(1)
                        Text("\(track.artistName) • \(track.durationLabel)")
                            .termType(TermType.telemetryTight, color: theme.palette.textMuted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(TermPressStyle())

            Button {
                TermHaptic.tap()
                onTrackContext(track)
            } label: {
                Text("[+]")
                    .termType(TermType.labelSM, color: theme.palette.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .overlay(Rectangle().strokeBorder(theme.palette.hairline, lineWidth: 1))
            }
            .buttonStyle(TermPressStyle())
            .accessibilityLabel(Text("Add \(track.title) to queue"))
        }
        .background(isCurrent ? TermColorMath.withAlpha(theme.palette.accent, 0.08) : Color.clear)
        .overlay(Rectangle().strokeBorder(isCurrent ? theme.palette.accentDeep : Color.clear, lineWidth: 1))
    }
}

struct CollectionDetailView_Previews: PreviewProvider {
    static var previews: some View {
        TerminalAppPreview {
            CollectionPreview()
        }
    }

    private struct CollectionPreview: View {
        let library = PreviewServices().library

        var body: some View {
            let player = MockPlayerService()
            CollectionDetailView(
                title: "Odyssey",
                subtitle: "HOME • 2014 • Electronic",
                artwork: MockArtworkService().artwork(seed: "album|a1", columns: 16),
                tracks: [],
                player: player,
                isLoading: false,
                errorMessage: nil,
                onPlayAll: {},
                onShuffle: {},
                onTrackTap: { _ in },
                onTrackContext: { _ in }
            )
        }
    }
}
