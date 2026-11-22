import Foundation
import MediaPlayer

enum STRepeatLadderResult {
    case verified(RepeatMode)
    case assumed(RepeatMode)
    case unverified(RepeatMode)
    case unsupported
}

enum STShuffleLadderResult {
    case verified(Bool)
    case assumed(Bool)
    case unverified(Bool)
    case unsupported
}

final class STMediaRemoteModeLadder {
    private typealias MRMediaRemoteSendCommandFunction = @convention(c) (UInt32, AnyObject?) -> Bool

    struct StrategyEntry {
        let id: String
        let cmd: UInt32?
        let optionKey: String?
        let isUIHook: Bool
        let isAdvance: Bool
        let description: String
    }

    static let repeatStrategies: [StrategyEntry] = [
        StrategyEntry(id: "R1", cmd: 25, optionKey: "kMRMediaRemoteOptionRepeatMode", isUIHook: false, isAdvance: false, description: "cmd 25, kMRMediaRemoteOptionRepeatMode (0,1,2)"),
        StrategyEntry(id: "R2", cmd: 25, optionKey: "RepeatMode", isUIHook: false, isAdvance: false, description: "cmd 25, RepeatMode (0,1,2)"),
        StrategyEntry(id: "R3", cmd: 25, optionKey: "kMRMediaRemoteOptionRepeatMode", isUIHook: false, isAdvance: false, description: "cmd 25, kMRMediaRemoteOptionRepeatMode (1,2,3)"),
        StrategyEntry(id: "R4", cmd: 25, optionKey: "RepeatMode", isUIHook: false, isAdvance: false, description: "cmd 25, RepeatMode (1,2,3)"),
        StrategyEntry(id: "R5", cmd: 7, optionKey: nil, isUIHook: false, isAdvance: true, description: "cmd 7 AdvanceRepeatMode (no options)"),
        StrategyEntry(id: "RH", cmd: nil, optionKey: nil, isUIHook: true, isAdvance: false, description: "UI hook: press Spotify on-screen repeat button")
    ]

    static let shuffleStrategies: [StrategyEntry] = [
        StrategyEntry(id: "S1", cmd: 26, optionKey: "kMRMediaRemoteOptionShuffleMode", isUIHook: false, isAdvance: false, description: "cmd 26, kMRMediaRemoteOptionShuffleMode (0,1)"),
        StrategyEntry(id: "S2", cmd: 26, optionKey: "ShuffleMode", isUIHook: false, isAdvance: false, description: "cmd 26, ShuffleMode (0,1)"),
        StrategyEntry(id: "S3", cmd: 26, optionKey: "kMRMediaRemoteOptionShuffleMode", isUIHook: false, isAdvance: false, description: "cmd 26, kMRMediaRemoteOptionShuffleMode (1,2)"),
        StrategyEntry(id: "S4", cmd: 26, optionKey: "ShuffleMode", isUIHook: false, isAdvance: false, description: "cmd 26, ShuffleMode (1,2)"),
        StrategyEntry(id: "S5", cmd: 6, optionKey: nil, isUIHook: false, isAdvance: true, description: "cmd 6 AdvanceShuffleMode (no options)"),
        StrategyEntry(id: "SH", cmd: nil, optionKey: nil, isUIHook: true, isAdvance: false, description: "UI hook: press Spotify on-screen shuffle button")
    ]

    private static let pinnedRepeatKey = "sptterm.repeat.pinned_strategy"
    private static let pinnedRepeatVersionKey = "sptterm.repeat.pinned_version"
    private static let pinnedShuffleKey = "sptterm.shuffle.pinned_strategy"
    private static let pinnedShuffleVersionKey = "sptterm.shuffle.pinned_version"

    private static var tweakDefaults: UserDefaults {
        UserDefaults(suiteName: "com.aditya.sptterm.tweak") ?? .standard
    }

    private static var consecutiveRepeatFailures = 0
    private static var consecutiveShuffleFailures = 0

    static func spotifyVersionString() -> String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short)+\(build)"
    }

    static func pinnedRepeatStrategy() -> String? {
        guard let strat = tweakDefaults.string(forKey: pinnedRepeatKey),
              let ver = tweakDefaults.string(forKey: pinnedRepeatVersionKey),
              ver == spotifyVersionString() else { return nil }
        return strat
    }

    static func pinRepeatStrategy(_ id: String) {
        tweakDefaults.set(id.uppercased(), forKey: pinnedRepeatKey)
        tweakDefaults.set(spotifyVersionString(), forKey: pinnedRepeatVersionKey)
    }

    static func unpinRepeatStrategy() {
        tweakDefaults.removeObject(forKey: pinnedRepeatKey)
        tweakDefaults.removeObject(forKey: pinnedRepeatVersionKey)
        consecutiveRepeatFailures = 0
    }

    static func pinnedShuffleStrategy() -> String? {
        guard let strat = tweakDefaults.string(forKey: pinnedShuffleKey),
              let ver = tweakDefaults.string(forKey: pinnedShuffleVersionKey),
              ver == spotifyVersionString() else { return nil }
        return strat
    }

    static func pinShuffleStrategy(_ id: String) {
        tweakDefaults.set(id.uppercased(), forKey: pinnedShuffleKey)
        tweakDefaults.set(spotifyVersionString(), forKey: pinnedShuffleVersionKey)
    }

    static func unpinShuffleStrategy() {
        tweakDefaults.removeObject(forKey: pinnedShuffleKey)
        tweakDefaults.removeObject(forKey: pinnedShuffleVersionKey)
        consecutiveShuffleFailures = 0
    }

    @discardableResult
    static func sendMRCommand(_ command: UInt32, options: [String: Any]? = nil) -> Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else {
            STLog.log("SptTerm: dlopen MediaRemote failed for cmd \(command)")
            return false
        }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "MRMediaRemoteSendCommand") else {
            STLog.log("SptTerm: dlsym MRMediaRemoteSendCommand failed for cmd \(command)")
            return false
        }
        let sendCmd = unsafeBitCast(sym, to: MRMediaRemoteSendCommandFunction.self)
        let opts = options as NSDictionary?
        let result = sendCmd(command, opts)
        STLog.log("SptTerm: MRMediaRemoteSendCommand(\(command), options: \(options ?? [:])) = \(result ? 1 : 0)")
        return result
    }

    // MARK: - Single-Send Repeat

    static func executeRepeat(target: RepeatMode, explicitID: String? = nil) async -> STRepeatLadderResult {
        let stratID = (explicitID ?? pinnedRepeatStrategy() ?? "R1").uppercased()
        guard let strat = repeatStrategies.first(where: { $0.id == stratID }) else {
            return .unsupported
        }

        let isPinned = (pinnedRepeatStrategy() == stratID)

        if strat.isUIHook {
            let res = await STSpotifyUIHook.press(type: "repeat")
            if let parsed = STModeMappings.parseRepeatText(res.after) {
                consecutiveRepeatFailures = 0
                return .verified(parsed)
            }
            if isPinned {
                return .assumed(target)
            }
            return .unverified(target)
        }

        guard let cmd = strat.cmd else { return .unsupported }
        let value = STModeMappings.valueForRepeatStrategy(id: stratID, mode: target)
        var options: [String: Any]? = nil
        if let key = strat.optionKey, let val = value {
            options = [key: NSNumber(value: val)]
        }

        let ret = sendMRCommand(cmd, options: options)
        STLog.log("SptTerm: repeat try [\(stratID)] cmd=\(cmd) key=\(strat.optionKey ?? "nil") val=\(value ?? -1) ret=\(ret ? 1 : 0)")

        if !ret {
            consecutiveRepeatFailures += 1
            if consecutiveRepeatFailures >= 3 {
                return .unsupported
            }
        } else {
            consecutiveRepeatFailures = 0
        }

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let readBackType = MPRemoteCommandCenter.shared().changeRepeatModeCommand.currentRepeatType
        let readBackMode = STModeMappings.mapRepeatType(readBackType)
        STLog.log("SptTerm: repeat [\(stratID)] read-back after 1s: raw=\(readBackType.rawValue) mapped=\(readBackMode.rawValue) target=\(target.rawValue)")

        if readBackMode == target {
            return .verified(readBackMode)
        }

        if isPinned {
            return .assumed(target)
        }

        return .unverified(target)
    }

    // MARK: - Single-Send Shuffle

    static func executeShuffle(target: Bool, explicitID: String? = nil) async -> STShuffleLadderResult {
        let stratID = (explicitID ?? pinnedShuffleStrategy() ?? "S1").uppercased()
        guard let strat = shuffleStrategies.first(where: { $0.id == stratID }) else {
            return .unsupported
        }

        let isPinned = (pinnedShuffleStrategy() == stratID)

        if strat.isUIHook {
            let res = await STSpotifyUIHook.press(type: "shuffle")
            if let parsed = STModeMappings.parseShuffleText(res.after) {
                consecutiveShuffleFailures = 0
                return .verified(parsed)
            }
            if isPinned {
                return .assumed(target)
            }
            return .unverified(target)
        }

        guard let cmd = strat.cmd else { return .unsupported }
        let value = STModeMappings.valueForShuffleStrategy(id: stratID, enabled: target)
        var options: [String: Any]? = nil
        if let key = strat.optionKey, let val = value {
            options = [key: NSNumber(value: val)]
        }

        let ret = sendMRCommand(cmd, options: options)
        STLog.log("SptTerm: shuffle try [\(stratID)] cmd=\(cmd) key=\(strat.optionKey ?? "nil") val=\(value ?? -1) ret=\(ret ? 1 : 0)")

        if !ret {
            consecutiveShuffleFailures += 1
            if consecutiveShuffleFailures >= 3 {
                return .unsupported
            }
        } else {
            consecutiveShuffleFailures = 0
        }

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let readBackType = MPRemoteCommandCenter.shared().changeShuffleModeCommand.currentShuffleType
        let readBackBool = STModeMappings.mapShuffleType(readBackType)
        STLog.log("SptTerm: shuffle [\(stratID)] read-back after 1s: raw=\(readBackType.rawValue) mapped=\(readBackBool) target=\(target)")

        if readBackBool == target {
            return .verified(readBackBool)
        }

        if isPinned {
            return .assumed(target)
        }

        return .unverified(target)
    }

    // MARK: - Registration of Exploration EXEC Commands

    @MainActor
    static func registerExplorationCommands() {
        STMediaRemoteExplorationCommands.register()
    }
}
