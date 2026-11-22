import Foundation

/// Registers exploration and diagnostic EXEC commands for MediaRemote repeat and shuffle.
final class STMediaRemoteExplorationCommands {
    @MainActor
    static func register() {
        let reg = STExecCommandRegistry.shared

        reg.register(STExecCommand(name: "strategies", usage: "strategies", help: "list repeat/shuffle strategies and pinned IDs") { _, _, _ in
            var lines = ["STRATEGIES TABLE:"]
            let pinnedR = STMediaRemoteModeLadder.pinnedRepeatStrategy()
            lines.append("REPEAT CANDIDATES:")
            for s in STMediaRemoteModeLadder.repeatStrategies {
                let isPin = (s.id == pinnedR) ? " [PINNED]" : ""
                lines.append("  \(s.id): \(s.description)\(isPin)")
            }
            let pinnedS = STMediaRemoteModeLadder.pinnedShuffleStrategy()
            lines.append("SHUFFLE CANDIDATES:")
            for s in STMediaRemoteModeLadder.shuffleStrategies {
                let isPin = (s.id == pinnedS) ? " [PINNED]" : ""
                lines.append("  \(s.id): \(s.description)\(isPin)")
            }
            return lines
        })

        reg.register(STExecCommand(name: "try", usage: "try <repeat|shuffle> <id> [mode]", help: "test a specific strategy ID once") { _, args, ctx in
            guard args.count >= 2 else {
                return ["usage: try repeat <R1-R5|RH> [off|all|one] | try shuffle <S1-S5|SH> [on|off]"]
            }
            let kind = args[0].lowercased()
            let id = args[1].uppercased()

            if kind == "repeat" {
                let target: RepeatMode
                if args.count > 2 {
                    target = RepeatMode(rawValue: args[2].lowercased()) ?? .all
                } else {
                    target = .all
                }
                Task {
                    _ = await STMediaRemoteModeLadder.executeRepeat(target: target, explicitID: id)
                }
                return ["> try repeat [\(id)] target=\(target.rawValue): sent, waiting for read-back"]
            } else if kind == "shuffle" {
                let target: Bool
                if args.count > 2 {
                    target = (args[2].lowercased() == "on" || args[2].lowercased() == "true")
                } else {
                    target = true
                }
                Task {
                    _ = await STMediaRemoteModeLadder.executeShuffle(target: target, explicitID: id)
                }
                return ["> try shuffle [\(id)] target=\(target ? "ON" : "OFF"): sent, waiting for read-back"]
            } else {
                return ["invalid try kind: \(kind) (use repeat or shuffle)"]
            }
        })

        reg.register(STExecCommand(name: "pin", usage: "pin <repeat|shuffle> <id>", help: "pin winning strategy for this Spotify version") { _, args, _ in
            guard args.count >= 2 else { return ["usage: pin <repeat|shuffle> <id>"] }
            let kind = args[0].lowercased()
            let id = args[1].uppercased()
            let ver = STMediaRemoteModeLadder.spotifyVersionString()
            if kind == "repeat" {
                guard STMediaRemoteModeLadder.repeatStrategies.contains(where: { $0.id == id }) else {
                    return ["invalid repeat strategy: \(id) (use `strategies`)"]
                }
                STMediaRemoteModeLadder.pinRepeatStrategy(id)
                STLog.log("SptTerm: repeat pinned to \(id) (version \(ver))")
                return ["> repeat pinned to \(id) (version \(ver))"]
            } else if kind == "shuffle" {
                guard STMediaRemoteModeLadder.shuffleStrategies.contains(where: { $0.id == id }) else {
                    return ["invalid shuffle strategy: \(id) (use `strategies`)"]
                }
                STMediaRemoteModeLadder.pinShuffleStrategy(id)
                STLog.log("SptTerm: shuffle pinned to \(id) (version \(ver))")
                return ["> shuffle pinned to \(id) (version \(ver))"]
            } else {
                return ["usage: pin <repeat|shuffle> <id>"]
            }
        })

        reg.register(STExecCommand(name: "unpin", usage: "unpin <repeat|shuffle>", help: "remove pinned strategy") { _, args, _ in
            guard !args.isEmpty else { return ["usage: unpin <repeat|shuffle>"] }
            let kind = args[0].lowercased()
            if kind == "repeat" {
                STMediaRemoteModeLadder.unpinRepeatStrategy()
                return ["> repeat unpinned, reverted to default (R1)"]
            } else if kind == "shuffle" {
                STMediaRemoteModeLadder.unpinShuffleStrategy()
                return ["> shuffle unpinned, reverted to default (S1)"]
            } else if kind.contains("repeat") || kind.contains("shuffle") {
                STMediaRemoteModeLadder.unpinRepeatStrategy()
                STMediaRemoteModeLadder.unpinShuffleStrategy()
                return ["> repeat and shuffle unpinned"]
            } else {
                return ["usage: unpin <repeat|shuffle>"]
            }
        })

        reg.register(STExecCommand(name: "mrstate", usage: "mrstate", help: "dump MPRemoteCommandCenter and NowPlaying state") { _, _, _ in
            return STMRStateDump.dumpState()
        })

        reg.register(STExecCommand(name: "uihook", usage: "uihook <scan|press repeat|press shuffle>", help: "scan or press Spotify on-screen controls") { _, args, _ in
            guard !args.isEmpty else {
                return ["usage: uihook scan | uihook press <repeat|shuffle>"]
            }
            let sub = args[0].lowercased()
            if sub == "scan" {
                let candidates = STSpotifyUIHook.scanCandidates()
                if candidates.isEmpty {
                    STLog.log("SptTerm: uihook no candidates (full-screen player probably not open)")
                    return ["> uihook: no candidates (full-screen player probably not open)"]
                }
                var lines = ["> uihook scan found \(candidates.count) candidate(s):"]
                for (idx, c) in candidates.enumerated() {
                    let desc = "[\(idx + 1)] \(c.summary)"
                    STLog.log("SptTerm: uihook \(desc)")
                    lines.append("  \(desc)")
                }
                return lines
            } else if sub == "press" {
                guard args.count > 1 else { return ["usage: uihook press <repeat|shuffle>"] }
                let target = args[1].lowercased()
                Task {
                    _ = await STSpotifyUIHook.press(type: target)
                }
                return ["> uihook: pressing \(target) button... (check `log`)"]
            } else {
                return ["usage: uihook scan | uihook press <repeat|shuffle>"]
            }
        })
    }
}
