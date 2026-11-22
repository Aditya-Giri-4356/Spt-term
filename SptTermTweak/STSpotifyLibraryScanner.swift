import UIKit

/// Represents an on-screen accessible element with ancestor hierarchy and classification details.
struct STScannedElement {
    let className: String
    let accessibilityIdentifier: String
    let label: String
    let value: String
    let frame: CGRect
    let ancestors: [String]
    let isPlaylistCandidate: Bool
    let isTrackCandidate: Bool
    let parsedName: String?
    weak var view: UIView?

    var summary: String {
        let idPart = accessibilityIdentifier.isEmpty ? "" : " id=\"\(accessibilityIdentifier)\""
        let valPart = value.isEmpty ? "" : " val=\"\(value)\""
        let typePart = isPlaylistCandidate ? " [PLAYLIST: \(parsedName ?? "")]" : (isTrackCandidate ? " [TRACK]" : "")
        let ancPart = ancestors.isEmpty ? "" : " anc=\(ancestors.joined(separator: "->"))"
        return "[\(className)] label=\"\(label)\"\(idPart)\(valPart) frame=(\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.width)),\(Int(frame.height)))\(ancPart)\(typePart)"
    }
}

/// Scans on-screen accessible elements from Spotify's non-overlay windows,
/// applies strict classification for playlists and tracks, and coordinates with stores.
@MainActor
final class STSpotifyLibraryScanner {

    /// Registers the library and track EXEC commands into the passed-in registry instance (not .shared).
    static func registerCommands(into registry: STExecCommandRegistry) {
        registry.register(STExecCommand(name: "libscan", usage: "libscan [all]", help: "dump on-screen elements or auto-scroll (all)") { _, args, _ in
            if args.first?.lowercased() == "all" {
                STLibraryBatchScanner.startScanAll()
                return ["> libscan all: started auto-scroll scan (up to 40 steps, check `log`)"]
            }
            return runScanCommand()
        })

        registry.register(STExecCommand(name: "libclear", usage: "libclear", help: "clear cached Spotify playlists") { _, _, _ in
            STLibraryCache.shared.clear()
            return ["> libclear: cleared playlist cache (0 entries)"]
        })

        registry.register(STExecCommand(name: "libtap", usage: "libtap <substring>", help: "activate on-screen Library row matching substring") { _, args, _ in
            return runLibTapCommand(args: args)
        })

        registry.register(STExecCommand(name: "trkclear", usage: "trkclear", help: "clear opened-playlist tracks list") { _, _, _ in
            STOpenedPlaylistTracks.shared.clear()
            return ["> trkclear: cleared opened-playlist tracks list (0 tracks)"]
        })

        registry.register(STExecCommand(name: "trktap", usage: "trktap <substring>", help: "activate on-screen track row matching substring") { _, args, _ in
            return runTrkTapCommand(args: args)
        })
    }

    /// Enumerates up to 200 on-screen labelled accessible elements across non-overlay windows.
    static func scanOnScreenElements(logSummary: Bool = false) -> [STScannedElement] {
        var elements: [STScannedElement] = []
        let screenBounds = UIScreen.main.bounds
        var playlistsKept = 0
        var tracksKept = 0
        var skipped = 0

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if window is STTweakWindow || window.windowLevel > UIWindow.Level.alert { continue }
                collectElements(in: window, window: window, bounds: screenBounds, elements: &elements, pKept: &playlistsKept, tKept: &tracksKept, skipped: &skipped)
                if elements.count >= 200 { break }
            }
            if elements.count >= 200 { break }
        }

        if logSummary {
            STLog.log("SptTerm: scan: playlists kept \(playlistsKept), tracks kept \(tracksKept), skipped \(skipped)")
        }
        return elements
    }

    private static func collectElements(
        in view: UIView,
        window: UIWindow,
        bounds: CGRect,
        elements: inout [STScannedElement],
        pKept: inout Int,
        tKept: inout Int,
        skipped: inout Int
    ) {
        if elements.count >= 200 { return }
        let rawLabel = view.accessibilityLabel ?? ""
        let trimmedLabel = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedLabel.isEmpty {
            let winFrame = view.convert(view.bounds, to: window)
            let isOnScreen = !view.isHidden && view.alpha > 0.01 && view.isUserInteractionEnabled && !winFrame.isEmpty && bounds.intersects(winFrame)

            if isOnScreen {
                var ancestors: [String] = []
                var curr = view.superview
                while let parent = curr, ancestors.count < 6 {
                    ancestors.append(NSStringFromClass(type(of: parent)))
                    curr = parent.superview
                }

                let hasNowPlaying = ancestors.contains { $0.contains("NowPlaying") }
                let hasYourLibrary = ancestors.contains { $0.contains("YourLibrary") }

                var isPlaylist = false
                var isTrack = false
                var parsedName: String? = nil

                if !hasNowPlaying && hasYourLibrary {
                    if let (name, _) = STLibraryLabelParser.parseLibraryLabel(trimmedLabel) {
                        isPlaylist = true
                        parsedName = name
                        pKept += 1
                    } else {
                        skipped += 1
                    }
                } else if STLibraryLabelParser.isOpenedPlaylistTrackRow(label: trimmedLabel, frame: winFrame, ancestors: ancestors) {
                    isTrack = true
                    tKept += 1
                } else {
                    skipped += 1
                }

                elements.append(STScannedElement(
                    className: NSStringFromClass(type(of: view)),
                    accessibilityIdentifier: view.accessibilityIdentifier ?? "",
                    label: trimmedLabel,
                    value: view.accessibilityValue ?? "",
                    frame: winFrame,
                    ancestors: ancestors,
                    isPlaylistCandidate: isPlaylist,
                    isTrackCandidate: isTrack,
                    parsedName: parsedName,
                    view: view
                ))
                if elements.count >= 200 { return }
            }
        }

        for subview in view.subviews {
            collectElements(in: subview, window: window, bounds: bounds, elements: &elements, pKept: &pKept, tKept: &tKept, skipped: &skipped)
            if elements.count >= 200 { return }
        }
    }

    /// Scans elements, merges playlists into STLibraryCache, merges tracks into STOpenedPlaylistTracks, and returns playlists.
    static func scanAndCachePlaylists() -> [STCachedPlaylist] {
        let elements = scanOnScreenElements(logSummary: true)

        let playlists = elements.filter { $0.isPlaylistCandidate }.compactMap { c in
            c.parsedName.map { STCachedPlaylist(name: $0, lastLabel: c.label) }
        }
        if !playlists.isEmpty { STLibraryCache.shared.merge(playlists: playlists) }

        let trackElements = elements.filter { $0.isTrackCandidate }.sorted { $0.frame.origin.y < $1.frame.origin.y }
        let trackLabels = trackElements.map { $0.label }
        if !trackLabels.isEmpty { STOpenedPlaylistTracks.shared.merge(newScanLabels: trackLabels) }

        return STLibraryCache.shared.allPlaylists()
    }

    /// Activates an on-screen playlist element with matching name or label using STRowActivator.
    static func activatePlaylist(nameOrLabel: String) -> (success: Bool, message: String) {
        let target = nameOrLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let elements = scanOnScreenElements(logSummary: false)

        guard let match = elements.first(where: {
            ($0.parsedName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target)
            || ($0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target)
        }), let targetView = match.view else {
            STLog.log("SptTerm: activatePlaylist NOT ON SCREEN: '\(nameOrLabel)'")
            return (false, "NOT ON SCREEN - open Spotify Library")
        }

        let targetName = match.parsedName ?? match.label
        let res = STRowActivator.activate(view: targetView, targetName: targetName)
        return (res.success, res.success ? "ACTIVATED" : res.message)
    }

    /// Activates an on-screen track row using STRowActivator.
    static func activateTrack(label: String) -> (success: Bool, message: String) {
        let target = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let elements = scanOnScreenElements(logSummary: false)

        guard let match = elements.first(where: {
            $0.isTrackCandidate && $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target
        }), let targetView = match.view else {
            STLog.log("SptTerm: activateTrack NOT ON SCREEN: '\(label)'")
            return (false, "NOT ON SCREEN - scroll Spotify to this track")
        }

        let res = STRowActivator.activate(view: targetView, targetName: match.label)
        return (res.success, res.success ? "ACTIVATED" : res.message)
    }

    private static func runLibTapCommand(args: [String]) -> [String] {
        guard !args.isEmpty else { return ["usage: libtap <substring>"] }
        let sub = args.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = scanOnScreenElements(logSummary: false).filter {
            $0.ancestors.contains { $0.contains("YourLibrary") } && (($0.parsedName ?? $0.label).lowercased().contains(sub) || $0.label.lowercased().contains(sub))
        }
        if matches.isEmpty { return ["> libtap: no on-screen library rows matching '\(sub)'"] }
        if matches.count > 1 {
            return ["> libtap: multiple matches (\(matches.count)), ambiguous - did nothing:"] + matches.map { "  [\($0.parsedName ?? $0.label)]" }
        }
        guard let view = matches[0].view else { return ["> libtap: matched element view is nil"] }
        let name = matches[0].parsedName ?? matches[0].label
        let res = STRowActivator.activate(view: view, targetName: name)
        return ["> libtap: \(res.success ? "activated" : "failed") '\(name)' via \(res.method ?? "none")"]
    }

    private static func runTrkTapCommand(args: [String]) -> [String] {
        guard !args.isEmpty else { return ["usage: trktap <substring>"] }
        let sub = args.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = scanOnScreenElements(logSummary: false).filter {
            $0.isTrackCandidate && $0.label.lowercased().contains(sub)
        }
        if matches.isEmpty { return ["> trktap: no on-screen track rows matching '\(sub)'"] }
        if matches.count > 1 {
            return ["> trktap: multiple matches (\(matches.count)), ambiguous - did nothing:"] + matches.map { "  [\($0.label)]" }
        }
        guard let view = matches[0].view else { return ["> trktap: matched element view is nil"] }
        let res = STRowActivator.activate(view: view, targetName: matches[0].label)
        return ["> trktap: \(res.success ? "activated" : "failed") '\(matches[0].label)' via \(res.method ?? "none")"]
    }

    /// Executes `libscan` command logic.
    static func runScanCommand() -> [String] {
        _ = scanAndCachePlaylists()
        let elements = scanOnScreenElements(logSummary: false)
        let candidates = elements.filter { $0.isPlaylistCandidate || $0.isTrackCandidate }

        var lines: [String] = [
            "> libscan: scanned \(elements.count) element(s), \(candidates.count) classified candidate(s):"
        ]
        if elements.isEmpty { lines.append("  (no on-screen labelled elements found in non-overlay windows)") }
        for (idx, elem) in elements.enumerated() { lines.append("  [\(idx + 1)] \(elem.summary)") }
        return lines
    }
}
