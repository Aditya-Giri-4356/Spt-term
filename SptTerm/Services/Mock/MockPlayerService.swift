import Combine
import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Fake transport: advances progress on a 0.5s timer while playing. No audio.
final class MockPlayerService: PlayerServiceProtocol {
    private let subject: CurrentValueSubject<PlayerState, Never>
    private var ticker: AnyCancellable?
    private var volumeObserver: NSKeyValueObservation?

    private let tickInterval: TimeInterval = 0.5

    init(
        track: Track? = MockCatalog.tracks.first,
        queue: [Track] = MockCatalog.tracks,
        likedTrackIDs: Set<String> = ["t1", "t5", "t18"]
    ) {
        var initial = PlayerState.empty
        initial.queue = queue
        initial.currentTrack = track
        initial.duration = track?.duration ?? 0
        initial.likedTrackIDs = likedTrackIDs

        #if canImport(AVFoundation)
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(true)
        initial.volume = Double(audioSession.outputVolume)
        #endif
        #endif

        subject = CurrentValueSubject(initial)

        #if canImport(AVFoundation)
        #if os(iOS)
        volumeObserver = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            DispatchQueue.main.async {
                self?.setVolume(Double(session.outputVolume))
            }
        }
        #endif
        #endif
    }

    deinit {
        ticker?.cancel()
        volumeObserver?.invalidate()
    }

    var state: PlayerState { subject.value }

    var statePublisher: AnyPublisher<PlayerState, Never> {
        subject.eraseToAnyPublisher()
    }

    // MARK: Transport

    func play() {
        var next = state
        if next.currentTrack == nil {
            guard let first = next.queue.first else { return }
            next.currentTrack = first
            next.duration = first.duration
            next.progress = 0
        }
        next.isPlaying = true
        publish(next)
        startTicking()
    }

    func pause() {
        var next = state
        next.isPlaying = false
        publish(next)
        stopTicking()
    }

    func togglePlayPause() {
        if state.isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to progress: Double) {
        var next = state
        next.progress = min(max(progress, 0), max(next.duration, 0))
        publish(next)
    }

    func next() {
        advance()
    }

    func previous() {
        var next = state
        guard let current = next.currentTrack, !next.queue.isEmpty else { return }
        if next.progress > 3 {
            next.progress = 0
            publish(next)
            return
        }
        let index = next.queue.firstIndex { $0.id == current.id } ?? 0
        let target = index > 0 ? index - 1 : (next.repeatMode == .all ? next.queue.count - 1 : 0)
        next.currentTrack = next.queue[target]
        next.progress = 0
        next.duration = next.queue[target].duration
        publish(next)
    }

    // MARK: Queue

    func play(_ track: Track, in queue: [Track]) {
        var next = state
        var resolvedQueue = queue.isEmpty ? [track] : queue
        if !resolvedQueue.contains(where: { $0.id == track.id }) {
            resolvedQueue.insert(track, at: 0)
        }
        next.queue = resolvedQueue
        next.currentTrack = track
        next.progress = 0
        next.duration = track.duration
        next.isPlaying = true
        publish(next)
        startTicking()
    }

    func enqueue(_ track: Track) {
        var next = state
        guard !next.queue.contains(where: { $0.id == track.id }) else { return }
        next.queue.append(track)
        publish(next)
    }

    func removeFromQueue(at offsets: IndexSet) {
        var next = state
        for index in offsets.sorted(by: >) where next.queue.indices.contains(index) {
            next.queue.remove(at: index)
        }
        if let current = next.currentTrack,
           !next.queue.contains(where: { $0.id == current.id }) {
            next.currentTrack = next.queue.first
            next.progress = 0
            next.duration = next.queue.first?.duration ?? 0
        }
        publish(next)
    }

    func moveQueue(from source: Int, to destination: Int) {
        var next = state
        guard next.queue.indices.contains(source) else { return }
        let track = next.queue.remove(at: source)
        let target = source < destination ? destination - 1 : destination
        next.queue.insert(track, at: min(max(target, 0), next.queue.count))
        publish(next)
    }

    // MARK: Preferences

    func toggleLikeCurrentTrack() {
        guard let current = state.currentTrack else { return }
        var next = state
        if next.likedTrackIDs.contains(current.id) {
            next.likedTrackIDs.remove(current.id)
        } else {
            next.likedTrackIDs.insert(current.id)
        }
        publish(next)
    }

    func setRepeatMode(_ mode: RepeatMode) {
        var next = state
        next.repeatMode = mode
        publish(next)
    }

    func toggleShuffle() {
        var next = state
        next.isShuffled.toggle()
        publish(next)
    }

    func setShuffle(_ enabled: Bool) {
        var next = state
        next.isShuffled = enabled
        publish(next)
    }

    func sendRawCommand(_ command: UInt32) {
        STLog.log("MockPlayerService: sendRawCommand(\(command))")
    }

    func setVolume(_ value: Double) {
        var next = state
        next.volume = value.clampedUnit
        publish(next)
    }

    func openURI(_ uri: String) {
        STLog.log("MockPlayerService.openURI: \(uri)")
    }

    // MARK: Internals

    private func tick() {
        guard state.isPlaying else { return }
        var next = state
        next.progress += tickInterval
        if next.progress >= next.duration {
            advance()
        } else {
            publish(next)
        }
    }

    private func advance() {
        var next = state
        guard let current = next.currentTrack, !next.queue.isEmpty else { return }

        if next.repeatMode == .one {
            next.progress = 0
            publish(next)
            return
        }

        let index = next.queue.firstIndex { $0.id == current.id } ?? 0
        var target: Int?
        if next.isShuffled {
            target = randomOtherIndex(excluding: index)
        } else if index + 1 < next.queue.count {
            target = index + 1
        } else if next.repeatMode == .all {
            target = 0
        }

        guard let targetIndex = target, next.queue.indices.contains(targetIndex) else {
            next.isPlaying = false
            next.progress = 0
            publish(next)
            stopTicking()
            return
        }

        next.currentTrack = next.queue[targetIndex]
        next.progress = 0
        next.duration = next.queue[targetIndex].duration
        publish(next)
    }

    private func randomOtherIndex(excluding index: Int) -> Int {
        guard state.queue.count > 1 else { return index }
        var candidate = Int.random(in: 0..<state.queue.count)
        if candidate == index {
            candidate = (candidate + 1) % state.queue.count
        }
        return candidate
    }

    private func publish(_ existing: PlayerState) {
        subject.send(existing)
    }

    private func startTicking() {
        guard ticker == nil else { return }
        ticker = Timer.publish(every: tickInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }
}
