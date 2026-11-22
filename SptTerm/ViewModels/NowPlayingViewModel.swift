import Combine
import SwiftUI

@MainActor
final class NowPlayingViewModel: ObservableObject {
    @Published private(set) var state: PlayerState
    @Published private(set) var artwork: TrackArtwork
    @Published private(set) var syncedLyrics: [LyricsLine] = []

    private let player: PlayerServiceProtocol
    private let artworkProvider: ArtworkProviding
    private var cancellable: AnyCancellable?

    init(player: PlayerServiceProtocol, artworkProvider: ArtworkProviding) {
        self.player = player
        self.artworkProvider = artworkProvider
        state = player.state
        artwork = Self.resolveArtwork(provider: artworkProvider, track: player.state.currentTrack)
        cancellable = player.statePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in
                guard let self else { return }
                let trackChanged = self.state.currentTrack?.id != newState.currentTrack?.id
                let rowsChanged = self.state.currentTrack?.artworkMatrixRows != newState.currentTrack?.artworkMatrixRows
                self.state = newState
                if trackChanged || rowsChanged {
                    STPerfLogger.shared.measureBlock(label: "artwork-apply") {
                        self.artwork = Self.resolveArtwork(provider: artworkProvider, track: newState.currentTrack)
                    }
                }
                if trackChanged {
                    self.syncedLyrics = []
                    if STLyricsService.shared.isEnabled, let track = newState.currentTrack {
                        Task { @MainActor [weak self] in
                            guard let self, STLyricsService.shared.isEnabled else { return }
                            if let fetched = await STLyricsService.shared.fetchLyrics(for: track) {
                                if self.state.currentTrack?.id == track.id {
                                    self.syncedLyrics = fetched
                                }
                            }
                        }
                    }
                }
            }
    }

    deinit {
        cancellable?.cancel()
    }

    // MARK: - Derived

    var currentTrack: Track? { state.currentTrack }

    var progressBinding: Binding<Double> {
        Binding(
            get: { self.state.progressFraction },
            set: { _ in }
        )
    }

    var volumeBinding: Binding<Double> {
        Binding(
            get: { self.state.volume },
            set: { self.setVolume($0) }
        )
    }

    func setVolume(_ value: Double) {
        player.setVolume(value)
    }

    var activeLyrics: [LyricsLine] {
        !syncedLyrics.isEmpty ? syncedLyrics : (state.currentTrack?.lyrics ?? [])
    }

    var currentLyricIndex: Int {
        let lines = activeLyrics
        guard !lines.isEmpty else { return -1 }
        var index = -1
        for (offset, line) in lines.enumerated() where line.time <= state.progress {
            index = offset
        }
        return index
    }

    var repeatSymbol: String {
        if !state.isRepeatSupported {
            return "⟲"
        }
        switch state.repeatMode {
        case .off: return "⟲"
        case .all: return "⟲"
        case .one: return "⟲¹"
        }
    }

    var repeatLabel: String {
        if let override = state.repeatOverrideLabel {
            return override
        }
        if !state.isRepeatSupported {
            return STLog.repeatNA
        } else if state.isRepeatAssumed {
            return "\(state.repeatMode.label) (ASSUMED)"
        } else if state.isRepeatUnverified {
            return STLog.repeatUnverified
        } else {
            return state.repeatMode.label
        }
    }

    var shuffleLabel: String {
        if let override = state.shuffleOverrideLabel {
            return override
        }
        if !state.isShuffleSupported {
            return STLog.shuffleNA
        } else if state.isShuffleAssumed {
            return state.isShuffled ? "ON (ASSUMED)" : "OFF (ASSUMED)"
        } else if state.isShuffleUnverified {
            return STLog.shuffleUnverified
        } else {
            return "SHUF"
        }
    }

    // MARK: - Actions

    func playPause() {
        TermHaptic.playPause()
        player.togglePlayPause()
    }

    func next() {
        TermHaptic.tap()
        player.next()
    }

    func previous() {
        TermHaptic.tap()
        player.previous()
    }

    func seek(_ fraction: Double) {
        player.seek(to: fraction * state.duration)
    }

    func toggleShuffle() {
        TermHaptic.tap()
        guard state.isShuffleSupported else {
            STLog.log("SptTerm: shuffle called but shuffle is unsupported (\(STLog.shuffleNA))")
            return
        }
        player.toggleShuffle()
    }

    func cycleRepeat() {
        TermHaptic.tap()
        guard state.isRepeatSupported else {
            STLog.log("SptTerm: repeat called but repeat is unsupported (\(STLog.repeatNA))")
            return
        }
        let next: RepeatMode
        switch state.repeatMode {
        case .off: next = .all
        case .all: next = .one
        case .one: next = .off
        }
        player.setRepeatMode(next)
    }

    func toggleLike() {
        TermHaptic.tap()
        player.toggleLikeCurrentTrack()
    }

    // MARK: - Internals

    private static func resolveArtwork(provider: ArtworkProviding, track: Track?) -> TrackArtwork {
        if let track {
            return provider.artwork(for: track)
        }
        return provider.artwork(seed: "idle::no-track", columns: 16)
    }
}
