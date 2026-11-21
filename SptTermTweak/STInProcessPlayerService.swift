import Foundation
import Combine
import MediaPlayer
import UIKit
import AVFoundation

typealias STPlayerService = PlayerServiceProtocol

final class STInProcessPlayerService: NSObject, PlayerServiceProtocol {
    private let subject: CurrentValueSubject<PlayerState, Never>
    private var pollTimer: AnyCancellable?
    private var volumeObserver: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()

    var state: PlayerState { subject.value }
    var statePublisher: AnyPublisher<PlayerState, Never> {
        subject.eraseToAnyPublisher()
    }

    override init() {
        var initial = PlayerState.empty
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(true)
        initial.volume = Double(audioSession.outputVolume)
        #endif
        subject = CurrentValueSubject(initial)
        super.init()

        setupVolumeObserver()
        setupNotificationObservers()
        startPolling()
        pollNowPlaying()
    }

    deinit {
        pollTimer?.cancel()
        volumeObserver?.invalidate()
    }

    // MARK: - State & Metadata Observation

    private func setupVolumeObserver() {
        #if os(iOS)
        volumeObserver = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            DispatchQueue.main.async {
                self?.setVolume(Double(session.outputVolume))
            }
        }
        #endif
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.pollNowPlaying()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] _ in
                self?.pollNowPlaying()
            }
            .store(in: &cancellables)
    }

    private func startPolling() {
        pollTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pollNowPlaying()
            }
    }

    @objc func pollNowPlaying() {
        guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo, !info.isEmpty else {
            return
        }

        let title = info[MPMediaItemPropertyTitle] as? String ?? ""
        let artist = info[MPMediaItemPropertyArtist] as? String ?? ""
        let album = info[MPMediaItemPropertyAlbumTitle] as? String ?? ""
        let duration = (info[MPMediaItemPropertyPlaybackDuration] as? NSNumber)?.doubleValue ?? 0
        let elapsed = (info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue ?? 0
        let rate = (info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue ?? 0
        let isPlaying = rate > 0.0
        let externalID = (info["MPNowPlayingInfoPropertyExternalContentIdentifier"] as? String) ?? "\(title)|\(artist)"

        var next = state
        next.isPlaying = isPlaying
        next.duration = duration
        next.progress = elapsed

        if !title.isEmpty {
            if next.currentTrack?.title != title || next.currentTrack?.artistName != artist {
                let track = Track(
                    id: externalID,
                    title: title,
                    artistID: "spotify:artist:unknown",
                    artistName: artist,
                    albumID: "spotify:album:unknown",
                    albumTitle: album,
                    year: Calendar.current.component(.year, from: Date()),
                    trackNumber: 1,
                    duration: duration,
                    formatLabel: "STREAM",
                    bitrateLabel: "320k",
                    lyrics: []
                )
                next.currentTrack = track
                if !next.queue.contains(where: { $0.id == track.id }) {
                    next.queue.insert(track, at: 0)
                }
                STSessionLibraryService.shared.recordTrack(track)
            }
        }

        if next != state {
            publish(next)
        }
    }

    private func publish(_ state: PlayerState) {
        subject.send(state)
    }

    // MARK: - MediaRemote Control

    private typealias MRMediaRemoteSendCommandFunction = @convention(c) (UInt32, AnyObject?) -> Bool
    private typealias MRMediaRemoteSetElapsedTimeFunction = @convention(c) (Double) -> Void

    private let winningStrategyKey = "sptterm.seek.winning_strategy"
    private var seekUnsupportedSession = false
    private var seekTask: Task<Void, Never>?
    private let tweakDefaults = UserDefaults(suiteName: "com.aditya.sptterm.tweak") ?? .standard

    private func sendMRCommand(_ command: UInt32) {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else {
            STLog.log("SptTerm: dlopen MediaRemote failed")
            return
        }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "MRMediaRemoteSendCommand") else {
            STLog.log("SptTerm: dlsym MRMediaRemoteSendCommand failed")
            return
        }
        let sendCmd = unsafeBitCast(sym, to: MRMediaRemoteSendCommandFunction.self)
        let result = sendCmd(command, nil)
        STLog.log("SptTerm: MRMediaRemoteSendCommand(\(command)) = \(result ? 1 : 0)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pollNowPlaying()
        }
    }

    func play() {
        sendMRCommand(0) // Play = 0
    }

    func pause() {
        sendMRCommand(1) // Pause = 1
    }

    func togglePlayPause() {
        if state.isPlaying {
            pause()
        } else {
            play()
        }
    }

    func next() {
        sendMRCommand(4) // Next = 4
    }

    func previous() {
        sendMRCommand(5) // Previous = 5
    }

    // MARK: - Seek Ladder

    private func currentNowPlayingElapsed() -> Double {
        guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            return state.progress
        }
        return (info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue ?? state.progress
    }

    func seek(to progress: Double) {
        let seconds = min(max(progress, 0), max(state.duration, 0))
        var nextState = state
        nextState.progress = seconds
        publish(nextState)

        if seekUnsupportedSession {
            STLog.log("SptTerm: seek called but seek is unsupported for this session (SEEK N/A)")
            return
        }

        seekTask?.cancel()
        seekTask = Task { [weak self] in
            guard let self else { return }

            let strategies: [String] = [
                "kMRMediaRemoteOptionPlaybackPosition",
                "PlaybackPosition",
                "kMRMediaRemoteOptionElapsedTime",
                "MRMediaRemoteSetElapsedTime"
            ]

            var orderedStrategies = strategies
            if let winning = self.tweakDefaults.string(forKey: self.winningStrategyKey),
               let idx = orderedStrategies.firstIndex(of: winning) {
                orderedStrategies.remove(at: idx)
                orderedStrategies.insert(winning, at: 0)
            }

            var anySucceeded = false

            for strat in orderedStrategies {
                guard !Task.isCancelled else { return }

                let elapsedBefore = self.currentNowPlayingElapsed()
                var cmd: UInt32 = 0
                var optionKey = strat
                var ret = false

                guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else {
                    STLog.log("SptTerm: dlopen MediaRemote failed in seek ladder")
                    continue
                }

                if strat == "MRMediaRemoteSetElapsedTime" {
                    cmd = 0
                    optionKey = "MRMediaRemoteSetElapsedTime"
                    if let sym = dlsym(handle, "MRMediaRemoteSetElapsedTime") {
                        let fn = unsafeBitCast(sym, to: MRMediaRemoteSetElapsedTimeFunction.self)
                        fn(seconds)
                        ret = true
                    } else {
                        ret = false
                    }
                } else {
                    cmd = 24
                    optionKey = strat
                    if let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
                        let fn = unsafeBitCast(sym, to: MRMediaRemoteSendCommandFunction.self)
                        let options = [strat: NSNumber(value: seconds)] as NSDictionary
                        ret = fn(24, options)
                    } else {
                        ret = false
                    }
                }
                dlclose(handle)

                // Wait 1.0 s, read nowPlayingInfo elapsed
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }

                let elapsedAfter = self.currentNowPlayingElapsed()
                let diff = abs(elapsedAfter - seconds)
                let success = diff < 3.0

                STLog.log("SptTerm: seek attempt [\(strat)] cmd=\(cmd) option=\(optionKey) ret=\(ret ? 1 : 0) before=\(String(format: "%.1f", elapsedBefore)) after=\(String(format: "%.1f", elapsedAfter)) diff=\(String(format: "%.1f", diff)) target=\(String(format: "%.1f", seconds)) -> \(success ? "SUCCESS" : "FAILED")")

                if success {
                    anySucceeded = true
                    self.tweakDefaults.set(strat, forKey: self.winningStrategyKey)
                    STLog.log("SptTerm: seek winning strategy remembered: \(strat)")
                    await MainActor.run {
                        self.pollNowPlaying()
                    }
                    break
                }
            }

            if !anySucceeded {
                self.seekUnsupportedSession = true
                STLog.log("SptTerm: seek all strategies failed, marking seek unsupported for this session (SEEK N/A)")
                await MainActor.run {
                    var unsupp = self.state
                    unsupp.isSeekSupported = false
                    self.publish(unsupp)
                }
            }
        }
    }

    // MARK: - Play URI & Open URI

    func openURI(_ uri: String) {
        playURI(uri)
    }

    func playURI(_ uri: String) {
        guard let url = URL(string: uri) else { return }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { success in
                STLog.log("SptTerm: openURL completion: \(success ? 1 : 0) for \(uri)")
            }
        }
    }

    func play(_ track: Track, in queue: [Track]) {
        var next = state
        next.currentTrack = track
        next.duration = track.duration
        next.progress = 0
        next.isPlaying = true
        var resolvedQueue = queue.isEmpty ? [track] : queue
        if !resolvedQueue.contains(where: { $0.id == track.id }) {
            resolvedQueue.insert(track, at: 0)
        }
        next.queue = resolvedQueue
        publish(next)

        if track.id.hasPrefix("spotify:") || track.id.hasPrefix("http") {
            playURI(track.id)
        } else {
            playURI("spotify:track:\(track.id)")
        }
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

    func setVolume(_ value: Double) {
        var next = state
        next.volume = min(max(value, 0), 1)
        publish(next)
    }
}
