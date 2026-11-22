import Combine
import Foundation

/// The only playback surface the UI is allowed to touch. Phase 2 can back
/// this with AVAudioEngine without changing a single view.
protocol PlayerServiceProtocol: AnyObject {
    var state: PlayerState { get }
    var statePublisher: AnyPublisher<PlayerState, Never> { get }

    func play()
    func pause()
    func togglePlayPause()
    func seek(to progress: Double)
    func next()
    func previous()

    func play(_ track: Track, in queue: [Track])
    func enqueue(_ track: Track)
    func removeFromQueue(at offsets: IndexSet)
    func moveQueue(from source: Int, to destination: Int)

    func toggleLikeCurrentTrack()
    func setRepeatMode(_ mode: RepeatMode)
    func toggleShuffle()
    func setShuffle(_ enabled: Bool)
    func sendRawCommand(_ command: UInt32)
    func setVolume(_ value: Double)
    func openURI(_ uri: String)
}

extension PlayerServiceProtocol {
    func setShuffle(_ enabled: Bool) {
        if state.isShuffled != enabled {
            toggleShuffle()
        }
    }

    func sendRawCommand(_ command: UInt32) {
        STLog.log("SptTerm: sendRawCommand(\(command)) default no-op")
    }
}
