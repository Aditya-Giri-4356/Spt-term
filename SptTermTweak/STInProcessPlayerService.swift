import Foundation
import Combine
import MediaPlayer
import UIKit
import AVFoundation

typealias STPlayerService = PlayerServiceProtocol

private struct PlaybackAnchor {
    var elapsed: Double
    var timestamp: Date
    var rate: Double

    func extrapolated(at date: Date = Date(), duration: Double = 0) -> Double {
        let delta = date.timeIntervalSince(timestamp)
        let calc = elapsed + rate * delta
        if duration > 0 {
            return min(max(calc, 0), duration)
        }
        return max(calc, 0)
    }
}

final class STInProcessPlayerService: NSObject, PlayerServiceProtocol {
    private let subject: CurrentValueSubject<PlayerState, Never>
    private var pollTimer: AnyCancellable?
    private var volumeObserver: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Local Anchor & Seek State
    private var anchor = PlaybackAnchor(elapsed: 0, timestamp: Date(), rate: 0)
    private var ignoreNowPlayingUntil: Date = .distantPast
    private var consecutiveSeekFailures: Int = 0
    private var seekUnsupportedSession = false
    private var seekTask: Task<Void, Never>?

    // MARK: - Repeat State
    private var repeatUnsupportedSession = false
    private var repeatTask: Task<Void, Never>?

    // MARK: - Shuffle State
    private var shuffleUnsupportedSession = false
    private var shuffleTask: Task<Void, Never>?

    private let winningStrategyKey = "sptterm.seek.winning_strategy"
    private let tweakDefaults = UserDefaults(suiteName: "com.aditya.sptterm.tweak") ?? .standard

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
        seekTask?.cancel()
        repeatTask?.cancel()
        shuffleTask?.cancel()
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
        // Poll every 0.25s for smooth UI progress extrapolation and responsive live state sync
        pollTimer = Timer.publish(every: 0.25, on: .main, in: .common)
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
        let rawElapsed = (info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue ?? 0
        let rawRate = (info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue ?? 0
        let isPlaying = rawRate > 0.0
        let externalID = (info["MPNowPlayingInfoPropertyExternalContentIdentifier"] as? String) ?? "\(title)|\(artist)"

        let isTrackChanged = (state.currentTrack?.title != title || state.currentTrack?.artistName != artist)
        let now = Date()

        if isTrackChanged {
            // Track changed: resync anchor immediately to Spotify's value
            anchor = PlaybackAnchor(elapsed: rawElapsed, timestamp: now, rate: rawRate)
            ignoreNowPlayingUntil = .distantPast
        } else if now < ignoreNowPlayingUntil {
            // Within 2.5s window after seek: ignore nowPlayingInfo elapsed values that differ by > 3s
            let extrapolated = anchor.extrapolated(at: now, duration: duration)
            if abs(rawElapsed - extrapolated) <= 3.0 {
                // Spotify's reported position now agrees with the seek target (caught up); resync anchor
                ignoreNowPlayingUntil = .distantPast
                anchor = PlaybackAnchor(elapsed: rawElapsed, timestamp: now, rate: rawRate)
            } else {
                // Ignore Spotify's stale nowPlayingInfo elapsed value, extrapolate from anchor
                if anchor.rate != rawRate {
                    anchor = PlaybackAnchor(elapsed: extrapolated, timestamp: now, rate: rawRate)
                }
            }
        } else {
            // Outside ignore window: resync to Spotify's value once it agrees or changes significantly
            if abs(rawElapsed - anchor.elapsed) > 0.5 || rawRate != anchor.rate {
                anchor = PlaybackAnchor(elapsed: rawElapsed, timestamp: now, rate: rawRate)
            }
        }

        var next = state
        next.isPlaying = isPlaying
        next.duration = duration
        next.progress = anchor.extrapolated(at: now, duration: duration)

        if !title.isEmpty {
            if isTrackChanged {
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

        // Live cover missing retry: if artwork is not yet cached for current URI, retry every poll
        if let current = next.currentTrack, !STInProcessArtworkService.shared.hasCachedArtwork(for: current.id) {
            if let resolved = STInProcessArtworkService.shared.tryResolveLiveArtwork(for: current.id) {
                next.currentTrack?.artworkMatrixRows = resolved.matrix.rows
                next.currentTrack?.artworkAccentHex = resolved.accentHex
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

    private func sendMRCommand(_ command: UInt32) {
        STMediaRemoteModeLadder.sendMRCommand(command)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pollNowPlaying()
        }
    }

    func sendRawCommand(_ command: UInt32) {
        _ = sendRawCommand(command, options: nil)
    }

    @discardableResult
    func sendRawCommand(_ command: UInt32, options: [String: Any]?) -> Bool {
        STLog.log("SptTerm: raw MRMediaRemoteSendCommand(\(command), options: \(options ?? [:])) dispatched")
        return STMediaRemoteModeLadder.sendMRCommand(command, options: options)
    }

    func play() {
        let now = Date()
        let current = anchor.extrapolated(at: now, duration: state.duration)
        anchor = PlaybackAnchor(elapsed: current, timestamp: now, rate: 1.0)
        var next = state
        next.isPlaying = true
        publish(next)
        sendMRCommand(0) // Play = 0
    }

    func pause() {
        let now = Date()
        let current = anchor.extrapolated(at: now, duration: state.duration)
        anchor = PlaybackAnchor(elapsed: current, timestamp: now, rate: 0.0)
        var next = state
        next.isPlaying = false
        publish(next)
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
        let now = Date()
        anchor = PlaybackAnchor(elapsed: 0, timestamp: now, rate: state.isPlaying ? 1.0 : 0.0)
        ignoreNowPlayingUntil = .distantPast
        sendMRCommand(4) // Next = 4
    }

    func previous() {
        let now = Date()
        anchor = PlaybackAnchor(elapsed: 0, timestamp: now, rate: state.isPlaying ? 1.0 : 0.0)
        ignoreNowPlayingUntil = .distantPast
        sendMRCommand(5) // Previous = 5
    }

    // MARK: - Seek Ladder

    private typealias MRMediaRemoteSendCommandFunction = @convention(c) (UInt32, AnyObject?) -> Bool
    private typealias MRMediaRemoteSetElapsedTimeFunction = @convention(c) (Double) -> Void

    private func currentNowPlayingElapsed() -> Double {
        guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            return state.progress
        }
        return (info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue ?? state.progress
    }

    func seek(to progress: Double) {
        let seconds = min(max(progress, 0), max(state.duration, 0))
        let now = Date()
        let rate = state.isPlaying ? 1.0 : 0.0

        // Immediately anchor to the target on release and ignore divergent nowPlayingInfo values for up to 2.5s
        anchor = PlaybackAnchor(elapsed: seconds, timestamp: now, rate: rate)
        ignoreNowPlayingUntil = now.addingTimeInterval(2.5)

        var nextState = state
        nextState.progress = seconds
        publish(nextState)

        if seekUnsupportedSession {
            STLog.log("SptTerm: seek called but seek is unsupported for this session (\(STLog.seekNA))")
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

                let elapsedBeforeRaw = self.currentNowPlayingElapsed()
                let elapsedBeforeExtrap = self.anchor.extrapolated(at: Date(), duration: self.state.duration)
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

                let elapsedAfterRaw = self.currentNowPlayingElapsed()
                let nowCheck = Date()
                let expectedExtrap = self.anchor.extrapolated(at: nowCheck, duration: self.state.duration)
                let diff = abs(elapsedAfterRaw - expectedExtrap)
                let success = diff < 3.0

                STLog.log("SptTerm: seek attempt [\(strat)] cmd=\(cmd) option=\(optionKey) ret=\(ret ? 1 : 0) beforeRaw=\(String(format: "%.1f", elapsedBeforeRaw)) beforeExtrap=\(String(format: "%.1f", elapsedBeforeExtrap)) afterRaw=\(String(format: "%.1f", elapsedAfterRaw)) expectedExtrap=\(String(format: "%.1f", expectedExtrap)) diff=\(String(format: "%.1f", diff)) target=\(String(format: "%.1f", seconds)) -> \(success ? "SUCCESS" : "FAILED")")

                if success {
                    anySucceeded = true
                    self.consecutiveSeekFailures = 0
                    self.tweakDefaults.set(strat, forKey: self.winningStrategyKey)
                    STLog.log("SptTerm: seek winning strategy remembered: \(strat)")
                    self.anchor = PlaybackAnchor(elapsed: elapsedAfterRaw, timestamp: nowCheck, rate: self.state.isPlaying ? 1.0 : 0.0)
                    await MainActor.run {
                        self.pollNowPlaying()
                    }
                    break
                }
            }

            if !anySucceeded {
                if self.state.isPlaying {
                    self.consecutiveSeekFailures += 1
                    STLog.log("SptTerm: seek ladder failed (consecutive failures: \(self.consecutiveSeekFailures)/2)")
                    if self.consecutiveSeekFailures >= 2 {
                        self.seekUnsupportedSession = true
                        STLog.log("SptTerm: seek 2 consecutive full-ladder failures while playing, marking seek unsupported for this session (\(STLog.seekNA))")
                        await MainActor.run {
                            var unsupp = self.state
                            unsupp.isSeekSupported = false
                            self.publish(unsupp)
                        }
                    }
                } else {
                    STLog.log("SptTerm: seek ladder failed while paused; not incrementing consecutive failures")
                }
            }
        }
    }

    // MARK: - Repeat Ladder

    func setRepeatMode(_ mode: RepeatMode) {
        let previousMode = state.repeatMode

        if repeatUnsupportedSession {
            STLog.log("SptTerm: repeat called but repeat is unsupported for this session (\(STLog.repeatNA))")
            return
        }

        repeatTask?.cancel()
        repeatTask = Task { [weak self] in
            guard let self else { return }

            let result = await STMediaRemoteModeLadder.executeRepeatLadder(target: mode)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                var upd = self.state
                switch result {
                case .verified(let verifiedMode):
                    upd.repeatMode = verifiedMode
                    upd.isRepeatSupported = true
                    upd.isRepeatUnverified = false
                case .unverified:
                    upd.repeatMode = previousMode
                    upd.isRepeatSupported = true
                    upd.isRepeatUnverified = true
                case .unsupported:
                    self.repeatUnsupportedSession = true
                    upd.repeatMode = previousMode
                    upd.isRepeatSupported = false
                    upd.isRepeatUnverified = false
                }
                self.publish(upd)
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

    // MARK: - Shuffle Ladder

    func toggleShuffle() {
        setShuffle(!state.isShuffled)
    }

    func setShuffle(_ enabled: Bool) {
        let previousShuffled = state.isShuffled

        if shuffleUnsupportedSession {
            STLog.log("SptTerm: shuffle called but shuffle is unsupported for this session (\(STLog.shuffleNA))")
            return
        }

        shuffleTask?.cancel()
        shuffleTask = Task { [weak self] in
            guard let self else { return }

            let result = await STMediaRemoteModeLadder.executeShuffleLadder(target: enabled)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                var upd = self.state
                switch result {
                case .verified(let verifiedShuffled):
                    upd.isShuffled = verifiedShuffled
                    upd.isShuffleSupported = true
                    upd.isShuffleUnverified = false
                case .unverified:
                    upd.isShuffled = previousShuffled
                    upd.isShuffleSupported = true
                    upd.isShuffleUnverified = true
                case .unsupported:
                    self.shuffleUnsupportedSession = true
                    upd.isShuffled = previousShuffled
                    upd.isShuffleSupported = false
                    upd.isShuffleUnverified = false
                }
                self.publish(upd)
            }
        }
    }

    func setVolume(_ value: Double) {
        var next = state
        next.volume = min(max(value, 0), 1)
        publish(next)
    }
}
