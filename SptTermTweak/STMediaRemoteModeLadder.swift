import Foundation
import MediaPlayer

/// Result of executing a repeat mode ladder attempt.
enum STRepeatLadderResult {
    case verified(RepeatMode)
    case unverified(RepeatMode)
    case unsupported
}

/// Result of executing a shuffle mode ladder attempt.
enum STShuffleLadderResult {
    case verified(Bool)
    case unverified(Bool)
    case unsupported
}

/// Executes MediaRemote ladder commands for repeat and shuffle with MPRemoteCommandCenter read-back verification.
///
/// NOTE: MediaRemote command numbers 6 (AdvanceShuffleMode), 7 (AdvanceRepeatMode),
/// 25 (ChangeRepeatMode), and 26 (ChangeShuffleMode) are UNVERIFIED MEMORY and not from official headers.
final class STMediaRemoteModeLadder {
    private typealias MRMediaRemoteSendCommandFunction = @convention(c) (UInt32, AnyObject?) -> Bool

    private struct ModeStrategy {
        let name: String
        let cmd: UInt32
        let optionKey: String?
        let isAdvance: Bool
    }

    private static let winningRepeatStrategyKey = "sptterm.repeat.winning_strategy"
    private static let repeatStrategyVersionKey = "sptterm.repeat.strategy_version"

    private static let winningShuffleStrategyKey = "sptterm.shuffle.winning_strategy"
    private static let shuffleStrategyVersionKey = "sptterm.shuffle.strategy_version"

    private static var tweakDefaults: UserDefaults {
        UserDefaults(suiteName: "com.aditya.sptterm.tweak") ?? .standard
    }

    /// Current Spotify host app version string for strategy persistence gating
    static func spotifyVersionString() -> String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short)+\(build)"
    }

    /// Sends a raw MediaRemote command with optional options payload.
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
        STLog.log("SptTerm: MRMediaRemoteSendCommand(\(command)) = \(result ? 1 : 0)")
        return result
    }

    // MARK: - Explicit Type Mappings

    /// Maps MPRepeatType explicitly to our RepeatMode enum.
    static func mapRepeatType(_ type: MPRepeatType) -> RepeatMode {
        switch type {
        case .off:
            return .off
        case .one:
            return .one
        case .all:
            return .all
        @unknown default:
            return .off
        }
    }

    /// Maps MPShuffleType explicitly to a Bool.
    static func mapShuffleType(_ type: MPShuffleType) -> Bool {
        switch type {
        case .off:
            return false
        case .items, .collections:
            return true
        @unknown default:
            return false
        }
    }

    // MARK: - Repeat Ladder

    static func executeRepeatLadder(target: RepeatMode) async -> STRepeatLadderResult {
        let targetInt: Int
        switch target {
        case .off: targetInt = 0
        case .one: targetInt = 1
        case .all: targetInt = 2
        }

        let strategies: [ModeStrategy] = [
            ModeStrategy(name: "ChangeRepeatMode(25,kMRMediaRemoteOptionRepeatMode)", cmd: 25, optionKey: "kMRMediaRemoteOptionRepeatMode", isAdvance: false),
            ModeStrategy(name: "ChangeRepeatMode(25,RepeatMode)", cmd: 25, optionKey: "RepeatMode", isAdvance: false),
            ModeStrategy(name: "AdvanceRepeatMode(7)", cmd: 7, optionKey: nil, isAdvance: true)
        ]

        let version = spotifyVersionString()
        var ordered = strategies
        if let winning = tweakDefaults.string(forKey: winningRepeatStrategyKey),
           let savedVersion = tweakDefaults.string(forKey: repeatStrategyVersionKey),
           savedVersion == version,
           let idx = ordered.firstIndex(where: { $0.name == winning }) {
            let w = ordered.remove(at: idx)
            ordered.insert(w, at: 0)
        }

        var anyCommandAccepted = false
        var advanceSent = false

        for strat in ordered {
            if Task.isCancelled { return .unverified(target) }

            if strat.isAdvance {
                if advanceSent { continue }
                advanceSent = true
            }

            STLog.log("SptTerm: repeat trying candidate cmd=\(strat.cmd) name=\(strat.name) target=\(targetInt)(\(target.rawValue))")

            let commandCenter = MPRemoteCommandCenter.shared()
            let repeatCmd = commandCenter.changeRepeatModeCommand
            let typeBefore = repeatCmd.currentRepeatType

            let options: [String: Any]?
            if let key = strat.optionKey {
                options = [key: NSNumber(value: targetInt)]
            } else {
                options = nil
            }

            let ret = sendMRCommand(strat.cmd, options: options)
            if ret {
                anyCommandAccepted = true
            }

            // Wait 1.0 s to verify with MPRemoteCommandCenter
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return .unverified(target) }

            let typeAfter = repeatCmd.currentRepeatType
            let mapped = mapRepeatType(typeAfter)

            STLog.log("SptTerm: repeat candidate cmd=\(strat.cmd) ret=\(ret ? 1 : 0) before=\(typeBefore.rawValue) after=\(typeAfter.rawValue) mapped=\(mapped.rawValue) target=\(target.rawValue)")

            if mapped == target {
                tweakDefaults.set(strat.name, forKey: winningRepeatStrategyKey)
                tweakDefaults.set(version, forKey: repeatStrategyVersionKey)
                STLog.log("SptTerm: repeat winning strategy verified: \(strat.name) (version \(version))")
                return .verified(mapped)
            }

            // If advance command was sent and read-back was not verified, stop immediately
            if strat.isAdvance {
                STLog.log("SptTerm: repeat advance command 7 sent but unverified; stopping ladder (\(STLog.repeatUnverified))")
                break
            }
        }

        if anyCommandAccepted {
            STLog.log("SptTerm: repeat state cannot be read back from MPRemoteCommandCenter (\(STLog.repeatUnverified))")
            return .unverified(target)
        } else {
            STLog.log("SptTerm: repeat all strategies failed, marking repeat unsupported (\(STLog.repeatNA))")
            return .unsupported
        }
    }

    // MARK: - Shuffle Ladder

    static func executeShuffleLadder(target: Bool) async -> STShuffleLadderResult {
        let targetInt = target ? 1 : 0

        let strategies: [ModeStrategy] = [
            ModeStrategy(name: "ChangeShuffleMode(26,kMRMediaRemoteOptionShuffleMode)", cmd: 26, optionKey: "kMRMediaRemoteOptionShuffleMode", isAdvance: false),
            ModeStrategy(name: "ChangeShuffleMode(26,ShuffleMode)", cmd: 26, optionKey: "ShuffleMode", isAdvance: false),
            ModeStrategy(name: "AdvanceShuffleMode(6)", cmd: 6, optionKey: nil, isAdvance: true)
        ]

        let version = spotifyVersionString()
        var ordered = strategies
        if let winning = tweakDefaults.string(forKey: winningShuffleStrategyKey),
           let savedVersion = tweakDefaults.string(forKey: shuffleStrategyVersionKey),
           savedVersion == version,
           let idx = ordered.firstIndex(where: { $0.name == winning }) {
            let w = ordered.remove(at: idx)
            ordered.insert(w, at: 0)
        }

        var anyCommandAccepted = false
        var advanceSent = false

        for strat in ordered {
            if Task.isCancelled { return .unverified(target) }

            if strat.isAdvance {
                if advanceSent { continue }
                advanceSent = true
            }

            STLog.log("SptTerm: shuffle trying candidate cmd=\(strat.cmd) name=\(strat.name) target=\(targetInt)(\(target ? "ON" : "OFF"))")

            let commandCenter = MPRemoteCommandCenter.shared()
            let shuffleCmd = commandCenter.changeShuffleModeCommand
            let typeBefore = shuffleCmd.currentShuffleType

            let options: [String: Any]?
            if let key = strat.optionKey {
                options = [key: NSNumber(value: targetInt)]
            } else {
                options = nil
            }

            let ret = sendMRCommand(strat.cmd, options: options)
            if ret {
                anyCommandAccepted = true
            }

            // Wait 1.0 s to verify with MPRemoteCommandCenter
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return .unverified(target) }

            let typeAfter = shuffleCmd.currentShuffleType
            let mapped = mapShuffleType(typeAfter)

            STLog.log("SptTerm: shuffle candidate cmd=\(strat.cmd) ret=\(ret ? 1 : 0) before=\(typeBefore.rawValue) after=\(typeAfter.rawValue) mapped=\(mapped ? 1 : 0) target=\(target ? 1 : 0)")

            if mapped == target {
                tweakDefaults.set(strat.name, forKey: winningShuffleStrategyKey)
                tweakDefaults.set(version, forKey: shuffleStrategyVersionKey)
                STLog.log("SptTerm: shuffle winning strategy verified: \(strat.name) (version \(version))")
                return .verified(mapped)
            }

            // If advance command was sent and read-back was not verified, stop immediately
            if strat.isAdvance {
                STLog.log("SptTerm: shuffle advance command 6 sent but unverified; stopping ladder (\(STLog.shuffleUnverified))")
                break
            }
        }

        if anyCommandAccepted {
            STLog.log("SptTerm: shuffle state cannot be read back from MPRemoteCommandCenter (\(STLog.shuffleUnverified))")
            return .unverified(target)
        } else {
            STLog.log("SptTerm: shuffle all strategies failed, marking shuffle unsupported (\(STLog.shuffleNA))")
            return .unsupported
        }
    }
}
