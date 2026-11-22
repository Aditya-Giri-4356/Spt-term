import Foundation

/// Execution context provided to all EXEC commands.
struct STExecContext {
    let player: PlayerServiceProtocol
    let theme: TerminalTheme
    let audioEffects: AudioEffectsServiceProtocol?
}

/// A registered EXEC command entry.
struct STExecCommand {
    let name: String
    let aliases: [String]
    let usage: String
    let help: String
    let handler: (String, [String], STExecContext) -> [String]

    init(
        name: String,
        aliases: [String] = [],
        usage: String,
        help: String,
        handler: @escaping (String, [String], STExecContext) -> [String]
    ) {
        self.name = name
        self.aliases = aliases
        self.usage = usage
        self.help = help
        self.handler = handler
    }
}

/// Central registry of EXEC terminal commands.
@MainActor
final class STExecCommandRegistry {
    static let shared = STExecCommandRegistry()

    private var commands: [STExecCommand] = []

    private init() {
        registerBuiltIns()
        STLyricsCommands.register(into: self)
    }

    func register(_ command: STExecCommand) {
        if let idx = commands.firstIndex(where: { $0.name == command.name }) {
            commands[idx] = command
        } else {
            commands.append(command)
        }
    }

    func allCommands() -> [STExecCommand] {
        return commands
    }

    func execute(_ raw: String, context: STExecContext) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let verb = tokens.first?.lowercased() else { return [] }
        let args = Array(tokens.dropFirst())

        if verb == "help" {
            return generateHelp()
        }

        let cmd = commands.first { $0.name == verb || $0.aliases.contains(verb) }

        if let cmd {
            return cmd.handler(trimmed, args, context)
        }

        return ["not available in-process (type `help` for commands)"]
    }

    private func generateHelp() -> [String] {
        let sorted = commands.sorted(by: { $0.name < $1.name })

        var lines: [String] = ["AVAILABLE COMMANDS:"]
        for cmd in sorted {
            let padded = cmd.usage.padding(toLength: 26, withPad: " ", startingAt: 0)
            lines.append("  \(padded) - \(cmd.help)")
        }
        let helpPad = "help".padding(toLength: 26, withPad: " ", startingAt: 0)
        lines.append("  \(helpPad) - print this command list")
        return lines
    }

    private func registerBuiltIns() {
        // Transport
        register(STExecCommand(name: "play", usage: "play", help: "resume playback") { _, _, ctx in
            ctx.player.play()
            return ["> play: dispatched"]
        })

        register(STExecCommand(name: "pause", usage: "pause", help: "pause playback") { _, _, ctx in
            ctx.player.pause()
            return ["> pause: dispatched"]
        })

        register(STExecCommand(name: "next", usage: "next", help: "skip to next track") { _, _, ctx in
            ctx.player.next()
            return ["> next: dispatched"]
        })

        register(STExecCommand(name: "prev", aliases: ["previous"], usage: "prev", help: "previous track or restart") { _, _, ctx in
            ctx.player.previous()
            return ["> prev: dispatched"]
        })

        register(STExecCommand(name: "open", usage: "open <uri>", help: "open Spotify URI") { raw, args, ctx in
            guard !args.isEmpty else { return ["usage: open <uri>"] }
            let uri = String(raw.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            ctx.player.openURI(uri)
            return ["> open: \(uri)"]
        })

        register(STExecCommand(name: "seek", usage: "seek <seconds>", help: "scrub to playback position") { _, args, ctx in
            guard let first = args.first, let sec = Double(first) else {
                return ["usage: seek <seconds>"]
            }
            ctx.player.seek(to: sec)
            return ["> seek: \(sec)s"]
        })

        // Repeat & Shuffle (misleading feedback fixed: prints "sent, waiting for read-back")
        register(STExecCommand(name: "repeat", usage: "repeat [off|all|one]", help: "set or cycle repeat mode") { _, args, ctx in
            if args.isEmpty {
                let next: RepeatMode
                switch ctx.player.state.repeatMode {
                case .off: next = .all
                case .all: next = .one
                case .one: next = .off
                }
                ctx.player.setRepeatMode(next)
                return ["> repeat: sent, waiting for read-back"]
            }
            let modeStr = args[0].lowercased()
            if let mode = RepeatMode(rawValue: modeStr) {
                ctx.player.setRepeatMode(mode)
                return ["> repeat: sent, waiting for read-back"]
            } else {
                return ["invalid repeat mode: \(modeStr) (use off, all, one)"]
            }
        })

        register(STExecCommand(name: "shuffle", usage: "shuffle [on|off]", help: "toggle or set shuffle mode") { _, args, ctx in
            if args.isEmpty {
                ctx.player.toggleShuffle()
                return ["> shuffle: sent, waiting for read-back"]
            }
            let arg = args[0].lowercased()
            if arg == "on" || arg == "true" || arg == "1" {
                ctx.player.setShuffle(true)
                return ["> shuffle: sent, waiting for read-back"]
            } else if arg == "off" || arg == "false" || arg == "0" {
                ctx.player.setShuffle(false)
                return ["> shuffle: sent, waiting for read-back"]
            } else {
                return ["invalid shuffle argument: \(arg) (use on, off)"]
            }
        })

        // Manual raw commands
        register(STExecCommand(name: "cmd", usage: "cmd <number>", help: "manual raw MediaRemote command") { _, args, ctx in
            guard let first = args.first, let num = UInt32(first) else {
                return ["usage: cmd <number>"]
            }
            STLog.log("SptTerm: manual raw command \(num)")
            _ = ctx.player.sendRawCommand(num)
            return ["> cmd \(num): manual raw command, may have side effects"]
        })

        register(STExecCommand(name: "cmdopt", usage: "cmdopt <cmd> <key> <int>", help: "raw MR command with option key & int") { _, args, ctx in
            guard args.count >= 3,
                  let cmdNum = UInt32(args[0]),
                  let intVal = Int(args[2]) else {
                return ["usage: cmdopt <cmd> <optionKey> <int>"]
            }
            let key = args[1]
            let ret = ctx.player.sendRawCommand(cmdNum, options: [key: NSNumber(value: intVal)])
            STLog.log("SptTerm: manual raw cmdopt \(cmdNum) \(key)=\(intVal) ret=\(ret ? 1 : 0)")
            return [
                "> cmdopt \(cmdNum) \(key) \(intVal): manual raw command, may have side effects",
                "> cmdopt result: \(ret ? "SUCCESS" : "FAILED")"
            ]
        })

        // Sleep timer
        register(STExecCommand(name: "sleep", usage: "sleep [minutes|off]", help: "sleep timer to pause playback") { _, args, ctx in
            if args.isEmpty {
                return [STSleepTimer.shared.status()]
            }
            let arg = args[0].lowercased()
            if arg == "off" || arg == "cancel" {
                return [STSleepTimer.shared.cancel()]
            }
            if let mins = Double(arg) {
                return [STSleepTimer.shared.setTimer(minutes: mins, player: ctx.player)]
            }
            return ["usage: sleep <minutes> | sleep off | sleep"]
        })

        // Theme commands
        register(STExecCommand(name: "theme", usage: "theme [name|list|next|rand]", help: "switch or list themes") { raw, args, ctx in
            guard !args.isEmpty else {
                return ["> active theme: [\(ctx.theme.definition.listNumber)] \(ctx.theme.definition.name.uppercased())"]
            }
            let sub = args[0].lowercased()
            if sub == "list" {
                return [
                    "THEME MATRIX (\(ctx.theme.catalog.count) themes):",
                    ctx.theme.catalog.map { "[\($0.listNumber)] \($0.name)" }.joined(separator: ", ")
                ]
            } else if sub == "next" {
                let cat = ctx.theme.catalog
                let currentID = ctx.theme.themeID
                let idx = cat.firstIndex(where: { $0.id == currentID }) ?? 0
                let nextIdx = (idx + 1) % cat.count
                let target = cat[nextIdx]
                ctx.theme.select(target.id)
                return ["> theme: switched to [\(target.listNumber)] \(target.name.uppercased())"]
            } else if sub == "random" || sub == "rand" {
                let cat = ctx.theme.catalog
                guard let target = cat.randomElement() else { return ["> theme random: catalog empty"] }
                ctx.theme.select(target.id)
                return ["> theme: switched to [\(target.listNumber)] \(target.name.uppercased())"]
            } else {
                let arg = String(raw.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if let target = ctx.theme.catalog.first(where: {
                    $0.id.lowercased() == arg.lowercased() ||
                    $0.name.lowercased() == arg.lowercased() ||
                    $0.listNumber.lowercased() == arg.lowercased()
                }) {
                    ctx.theme.select(target.id)
                    return ["> theme: switched to [\(target.listNumber)] \(target.name.uppercased())"]
                } else {
                    return ["> theme not found: \(arg) (use `theme list`)"]
                }
            }
        })

        // Volume (skipped per specification)
        register(STExecCommand(name: "vol", aliases: ["volume"], usage: "vol", help: "hardware / Control Center only") { _, _, _ in
            return ["> vol: skipped (hardware buttons / Control Center only)"]
        })

        // Log diagnostics
        register(STExecCommand(name: "log", usage: "log [clear|tail <n>|grep <s>|copy]", help: "inspect or copy ring buffer") { raw, args, _ in
            if args.isEmpty {
                let lines = STLog.shared.lastLines(40)
                return lines.isEmpty ? ["> log buffer empty"] : lines
            }
            let sub = args[0].lowercased()
            if sub == "clear" {
                STLog.shared.clear()
                return ["> log cleared"]
            } else if sub == "tail" {
                let count = (args.count > 1 ? Int(args[1]) : 40) ?? 40
                let lines = STLog.shared.lastLines(count)
                return lines.isEmpty ? ["> log buffer empty"] : lines
            } else if sub == "grep" {
                guard args.count > 1 else { return ["usage: log grep <text>"] }
                let pattern = args.dropFirst().joined(separator: " ")
                let matches = STLog.shared.grep(pattern)
                if matches.isEmpty {
                    return ["> no log entries matching: \(pattern)"]
                }
                return matches.suffix(40).map { $0 }
            } else if sub == "copy" {
                let count = STLog.shared.allLines().count
                STLog.shared.copyToPasteboard()
                return ["> log copy: copied \(count) lines to pasteboard (user IDs sanitized)"]
            } else {
                return ["usage: log [clear|tail <n>|grep <text>|copy]"]
            }
        })

        // Performance diagnostics
        register(STExecCommand(name: "perf", usage: "perf [on|off]", help: "CADisplayLink hitch and main thread logger") { _, args, _ in
            guard let first = args.first?.lowercased() else {
                let status = STPerfLogger.shared.isEnabled ? "on" : "off"
                return ["> perf: \(status) (use `perf on` or `perf off`)"]
            }
            if first == "on" || first == "1" {
                STPerfLogger.shared.setEnabled(true)
                return ["> perf: on (logging hitches > 50ms, main-thread blocks > 8ms)"]
            } else if first == "off" || first == "0" {
                STPerfLogger.shared.setEnabled(false)
                return ["> perf: off"]
            } else {
                return ["usage: perf [on|off]"]
            }
        })
    }
}
