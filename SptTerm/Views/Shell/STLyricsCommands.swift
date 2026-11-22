import Foundation

/// Registers lyrics-related EXEC commands.
final class STLyricsCommands {
    @MainActor
    static func register(into registry: STExecCommandRegistry? = nil) {
        let reg = registry ?? STExecCommandRegistry.shared

        reg.register(STExecCommand(name: "lyrics", usage: "lyrics [on|off|show|status]", help: "synced lyrics toggle and viewer") { _, args, ctx in
            let sub = args.first?.lowercased() ?? "status"
            if sub == "on" {
                STLyricsService.shared.isEnabled = true
                if let current = ctx.player.state.currentTrack {
                    Task {
                        _ = await STLyricsService.shared.fetchLyrics(for: current)
                    }
                }
                return ["> lyrics: on (fetching from lrclib.net)"]
            } else if sub == "off" {
                STLyricsService.shared.isEnabled = false
                STLyricsService.shared.cancelCurrentFetch()
                return ["> lyrics: off"]
            } else if sub == "status" {
                if STLyricsService.shared.isEnabled {
                    let count = STLyricsService.shared.cacheCount
                    return ["> lyrics: on (cache: \(count) tracks)"]
                } else {
                    return ["lyrics: off (type `lyrics on`)"]
                }
            } else if sub == "show" {
                guard STLyricsService.shared.isEnabled else {
                    return ["lyrics: off (type `lyrics on`)"]
                }
                guard let current = ctx.player.state.currentTrack else {
                    return ["> no track currently playing"]
                }
                if let plain = STLyricsService.shared.cachedPlainLyrics(for: current.id), !plain.isEmpty {
                    return ["> plain lyrics for \(current.title):"] + plain.components(separatedBy: .newlines).prefix(30)
                }
                return ["> plain lyrics not cached for current track (type `lyrics on` to fetch)"]
            } else {
                return ["usage: lyrics [on|off|show|status]"]
            }
        })
    }
}
