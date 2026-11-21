import Combine
import SwiftUI

@MainActor
final class NowPlayingViewModel: ObservableObject {
    @Published private(set) var state: PlayerState
    @Published private(set) var artwork: TrackArtwork

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
                state = newState
                artwork = Self.resolveArtwork(provider: artworkProvider, track: newState.currentTrack)
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

    var currentLyricIndex: Int {
        guard let track = state.currentTrack, !track.lyrics.isEmpty else { return -1 }
        let lines = track.lyrics
        var index = -1
        for (offset, line) in lines.enumerated() where line.time <= state.progress {
            index = offset
        }
        return index
    }

    var repeatSymbol: String {
        switch state.repeatMode {
        case .off: return "⟲"
        case .all: return "⟲"
        case .one: return "⟲¹"
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
        player.toggleShuffle()
    }

    func cycleRepeat() {
        TermHaptic.tap()
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
