import Foundation
import MediaPlayer

/// Diagnostic inspection utility for MPRemoteCommandCenter and NowPlaying state.
final class STMRStateDump {
    private typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping (NSDictionary?) -> Void) -> Void

    static func dumpState() -> [String] {
        var lines: [String] = []

        lines.append("=== MPRemoteCommandCenter State ===")
        let center = MPRemoteCommandCenter.shared()

        let repCmd = center.changeRepeatModeCommand
        let repLine = "changeRepeatModeCommand: isEnabled=\(repCmd.isEnabled) currentType=\(repCmd.currentRepeatType.rawValue)"
        lines.append(repLine)
        STLog.log("SptTerm: mrstate \(repLine)")

        let shufCmd = center.changeShuffleModeCommand
        let shufLine = "changeShuffleModeCommand: isEnabled=\(shufCmd.isEnabled) currentType=\(shufCmd.currentShuffleType.rawValue)"
        lines.append(shufLine)
        STLog.log("SptTerm: mrstate \(shufLine)")

        let commands: [(String, MPRemoteCommand)] = [
            ("playCommand", center.playCommand),
            ("pauseCommand", center.pauseCommand),
            ("stopCommand", center.stopCommand),
            ("togglePlayPauseCommand", center.togglePlayPauseCommand),
            ("nextTrackCommand", center.nextTrackCommand),
            ("previousTrackCommand", center.previousTrackCommand),
            ("changePlaybackRateCommand", center.changePlaybackRateCommand),
            ("changePlaybackPositionCommand", center.changePlaybackPositionCommand),
            ("seekBackwardCommand", center.seekBackwardCommand),
            ("seekForwardCommand", center.seekForwardCommand),
            ("skipBackwardCommand", center.skipBackwardCommand),
            ("skipForwardCommand", center.skipForwardCommand),
            ("likeCommand", center.likeCommand),
            ("dislikeCommand", center.dislikeCommand),
            ("bookmarkCommand", center.bookmarkCommand),
            ("enableLanguageOptionCommand", center.enableLanguageOptionCommand),
            ("disableLanguageOptionCommand", center.disableLanguageOptionCommand)
        ]

        var enabledNames: [String] = []
        var disabledNames: [String] = []
        for (name, cmd) in commands {
            if cmd.isEnabled {
                enabledNames.append(name)
            } else {
                disabledNames.append(name)
            }
            STLog.log("SptTerm: mrstate cmd \(name): isEnabled=\(cmd.isEnabled)")
        }
        lines.append("Enabled commands: \(enabledNames.joined(separator: ", "))")
        lines.append("Disabled commands: \(disabledNames.joined(separator: ", "))")

        // MPNowPlayingInfoCenter inspection
        lines.append("=== MPNowPlayingInfoCenter Keys ===")
        if let npInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo, !npInfo.isEmpty {
            for (key, val) in npInfo {
                let keyStr = String(describing: key)
                let valType = String(describing: type(of: val))
                let lower = keyStr.lowercased()
                let isFlagged = lower.contains("repeat") || lower.contains("shuffle")
                let line = "key: \(keyStr) [\(valType)]\(isFlagged ? " [FLAGGED VALUE: \(val)]" : "")"
                lines.append(line)
                STLog.log("SptTerm: mrstate npInfo \(line)")
            }
        } else {
            lines.append("nowPlayingInfo is empty or nil")
            STLog.log("SptTerm: mrstate nowPlayingInfo is empty or nil")
        }

        // MRMediaRemoteGetNowPlayingInfo inspection via dlsym
        lines.append("=== MRMediaRemoteGetNowPlayingInfo Keys ===")
        if let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) {
            defer { dlclose(handle) }
            if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
                let getInfo = unsafeBitCast(sym, to: MRMediaRemoteGetNowPlayingInfoFunction.self)
                let sema = DispatchSemaphore(value: 0)
                getInfo(DispatchQueue.global(qos: .userInitiated)) { dict in
                    defer { sema.signal() }
                    guard let dict = dict as? [String: Any], !dict.isEmpty else {
                        lines.append("MRMediaRemoteGetNowPlayingInfo returned empty dictionary")
                        STLog.log("SptTerm: mrstate MRMediaRemote dict empty")
                        return
                    }
                    for (k, v) in dict {
                        let kLower = k.lowercased()
                        let isFlagged = kLower.contains("repeat") || kLower.contains("shuffle")
                        let line = "MRKey: \(k) [\(type(of: v))] \(isFlagged ? "[FLAGGED: \(v)]" : "")"
                        lines.append(line)
                        STLog.log("SptTerm: mrstate \(line)")
                    }
                }
                _ = sema.wait(timeout: .now() + 1.0)
            } else {
                lines.append("MRMediaRemoteGetNowPlayingInfo symbol not found via dlsym")
                STLog.log("SptTerm: mrstate MRMediaRemoteGetNowPlayingInfo not available via dlsym")
            }
        } else {
            lines.append("MediaRemote framework dlopen failed")
            STLog.log("SptTerm: mrstate dlopen MediaRemote failed")
        }

        return lines
    }
}
