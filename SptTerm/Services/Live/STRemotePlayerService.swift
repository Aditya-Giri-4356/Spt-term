import Combine
import Foundation
import SpotifyiOS

/// Drives the local Spotify app over App Remote. App Remote is used instead of
/// the Web API because Eevee's premium patch is local: the Web API still sees a
/// Free account and rejects transport commands.
final class STRemotePlayerService: NSObject, PlayerServiceProtocol {
    private let auth: STSpotifyAuth
    private let webAPI: STSpotifyWebAPI

    private let stateSubject = CurrentValueSubject<PlayerState, Never>(.empty)
    private var remote: SPTAppRemote?
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?

    var state: PlayerState { stateSubject.value }

    var statePublisher: AnyPublisher<PlayerState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    init(auth: STSpotifyAuth, webAPI: STSpotifyWebAPI) {
        self.auth = auth
        self.webAPI = webAPI
        super.init()
    }

    func connect() {
        guard STSpotifyConfig.isConfigured else { return }

        let configuration = SPTConfiguration(
            clientID: STSpotifyConfig.clientID,
            redirectURL: URL(string: STSpotifyConfig.redirectURI)!
        )

        let appRemote = SPTAppRemote(configuration: configuration, logLevel: .debug)
        appRemote.delegate = self
        remote = appRemote
        appRemote.connect()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        remote?.disconnect()
        remote = nil
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        let delay = min(pow(2, Double(reconnectAttempt)), 30)
        reconnectAttempt += 1

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    private func update(_ mutate: (inout PlayerState) -> Void) {
        var next = stateSubject.value
        mutate(&next)
        stateSubject.send(next)
    }

    func play() { remote?.playerAPI?.resume(nil) }
    func pause() { remote?.playerAPI?.pause(nil) }
    func togglePlayPause() { state.isPlaying ? pause() : play() }
    func next() { remote?.playerAPI?.skip(toNext: nil) }
    func previous() { remote?.playerAPI?.skip(toPrevious: nil) }

    func seek(to progress: Double) {
        remote?.playerAPI?.seek(toPosition: Int(progress * 1000), callback: nil)
    }

    func play(_ track: Track, in queue: [Track]) {
        update {
            $0.currentTrack = track
            $0.queue = queue
            $0.isPlaying = true
        }
        remote?.playerAPI?.play(STSpotifyMapping.uri(track.id), callback: nil)
    }

    func enqueue(_ track: Track) {
        update { $0.queue.append(track) }
    }

    func removeFromQueue(at offsets: IndexSet) {
        update { state in
            offsets.sorted(by: >).forEach { index in
                guard state.queue.indices.contains(index) else { return }
                state.queue.remove(at: index)
            }
        }
    }

    func moveQueue(from source: Int, to destination: Int) {
        update { state in
            guard state.queue.indices.contains(source) else { return }
            let item = state.queue.remove(at: source)
            state.queue.insert(item, at: min(destination, state.queue.count))
        }
    }

    func toggleLikeCurrentTrack() {
        guard let track = state.currentTrack else { return }
        let isLiked = state.likedTrackIDs.contains(track.id)

        update { state in
            if isLiked {
                state.likedTrackIDs.remove(track.id)
            } else {
                state.likedTrackIDs.insert(track.id)
            }
        }

        Task {
            do {
                if isLiked {
                    try await webAPI.unsaveTrack(track.id)
                } else {
                    try await webAPI.saveTrack(track.id)
                }
            } catch {
                update { $0.likedTrackIDs.formSymmetricDifference([track.id]) }
            }
        }
    }

    func setRepeatMode(_ mode: RepeatMode) {
        update { $0.repeatMode = mode }
        remote?.playerAPI?.setRepeatMode(remoteMode(mode), callback: nil)
    }

    func toggleShuffle() {
        let next = !state.isShuffled
        update { $0.isShuffled = next }
        remote?.playerAPI?.setShuffle(next, callback: nil)
    }

    /// App Remote exposes no volume control; the value is local-only.
    func setVolume(_ value: Double) {
        update { $0.volume = value.clampedUnit }
    }

    private func remoteMode(_ mode: RepeatMode) -> SPTAppRemoteRepeatMode {
        switch mode {
        case .off: return .off
        case .all: return .context
        case .one: return .track
        }
    }
}

extension STRemotePlayerService: SPTAppRemoteDelegate {
    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        reconnectAttempt = 0
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: { _, _ in })
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        update { $0.isPlaying = false }
        scheduleReconnect()
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        scheduleReconnect()
    }
}

extension STRemotePlayerService: SPTAppRemotePlayerStateDelegate {
    func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        let track = playerState.track
        let mapped = Track(
            id: STSpotifyMapping.id(fromURI: track.uri),
            title: track.name,
            artistID: "",
            artistName: track.artist.name,
            albumID: "",
            albumTitle: track.album.name,
            year: 0,
            trackNumber: 0,
            duration: Double(track.duration) / 1000,
            formatLabel: "AAC",
            bitrateLabel: "320K",
            lyrics: []
        )

        update { state in
            state.currentTrack = mapped
            state.isPlaying = !playerState.isPaused
            state.progress = Double(playerState.playbackPosition) / 1000
            state.isShuffled = playerState.isShuffleEnabled
            state.repeatMode = self.localMode(playerState.repeatMode)
        }
    }

    private func localMode(_ mode: SPTAppRemoteRepeatMode) -> RepeatMode {
        switch mode {
        case .context: return .all
        case .track: return .one
        default: return .off
        }
    }
}
