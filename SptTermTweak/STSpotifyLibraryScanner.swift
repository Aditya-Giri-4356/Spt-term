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
    let parsedName: String?
    let matchedRule: String?
    weak var view: UIView?

    var summary: String {
        let idPart = accessibilityIdentifier.isEmpty ? "" : " id=\"\(accessibilityIdentifier)\""
        let valPart = value.isEmpty ? "" : " val=\"\(value)\""
        let candPart = isPlaylistCandidate ? " [PLAYLIST: \(parsedName ?? "") via \(matchedRule ?? "")]" : ""
        let ancPart = ancestors.isEmpty ? "" : " ancestors=\(ancestors.joined(separator: "->"))"
        return "[\(className)] label=\"\(label)\"\(idPart)\(valPart) frame=(\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.width)),\(Int(frame.height)))\(ancPart)\(candPart)"
    }
}

/// Scans on-screen accessible elements from Spotify's non-overlay windows,
/// applies strict heuristic classification, and synchronizes with STLibraryCache v2.
@MainActor
final class STSpotifyLibraryScanner {

    /// Registers the `libscan`, `libclear`, and `libtap` commands into the passed-in registry instance (not .shared).
    static func registerCommands(into registry: STExecCommandRegistry) {
        registry.register(STExecCommand(
            name: "libscan",
            usage: "libscan",
            help: "dump on-screen labelled elements & classify playlist rows"
        ) { _, _, _ in
            return runScanCommand()
        })

        registry.register(STExecCommand(
            name: "libclear",
            usage: "libclear",
            help: "clear cached Spotify playlists"
        ) { _, _, _ in
            STLibraryCache.shared.clear()
            return ["> libclear: cleared playlist cache (0 entries)"]
        })

        registry.register(STExecCommand(
            name: "libtap",
            usage: "libtap <substring>",
            help: "activate single on-screen Library row matching substring"
        ) { _, args, _ in
            guard !args.isEmpty else { return ["usage: libtap <substring>"] }
            let sub = args.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let elements = scanOnScreenElements(logSummary: false)
            let libraryRows = elements.filter { $0.ancestors.contains { $0.contains("YourLibrary") } }
            let matches = libraryRows.filter {
                ($0.parsedName ?? $0.label).lowercased().contains(sub) || $0.label.lowercased().contains(sub)
            }
            if matches.isEmpty {
                return ["> libtap: no on-screen library rows matching '\(sub)'"]
            }
            if matches.count > 1 {
                var lines = ["> libtap: multiple matches (\(matches.count)), ambiguous - did nothing:"]
                for (idx, m) in matches.enumerated() {
                    lines.append("  [\(idx + 1)] \(m.parsedName ?? m.label)")
                }
                return lines
            }
            let match = matches[0]
            guard let view = match.view else { return ["> libtap: matched element view is nil"] }
            let targetName = match.parsedName ?? match.label
            let res = STRowActivator.activate(view: view, targetName: targetName)
            return ["> libtap: \(res.success ? "activated" : "failed") '\(targetName)' via \(res.method ?? "none")"]
        })
    }

    /// Enumerates up to 200 on-screen labelled accessible elements across non-overlay windows.
    static func scanOnScreenElements(logSummary: Bool = false) -> [STScannedElement] {
        var elements: [STScannedElement] = []
        let screenBounds = UIScreen.main.bounds

        var keptCount = 0
        var skippedKind = 0
        var skippedNowPlaying = 0
        var skippedNoParse = 0

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if window is STTweakWindow || window.windowLevel > UIWindow.Level.alert {
                    continue
                }
                collectElements(
                    in: window,
                    window: window,
                    screenBounds: screenBounds,
                    elements: &elements,
                    keptCount: &keptCount,
                    skippedKind: &skippedKind,
                    skippedNowPlaying: &skippedNowPlaying,
                    skippedNoParse: &skippedNoParse
                )
                if elements.count >= 200 { break }
            }
            if elements.count >= 200 { break }
        }

        if logSummary {
            let totalSkipped = skippedKind + skippedNowPlaying + skippedNoParse
            STLog.log("SptTerm: libscan: kept \(keptCount), skipped \(totalSkipped) (kind=\(skippedKind), nowplaying=\(skippedNowPlaying), noparse=\(skippedNoParse))")
        }

        return elements
    }

    private static func collectElements(
        in view: UIView,
        window: UIWindow,
        screenBounds: CGRect,
        elements: inout [STScannedElement],
        keptCount: inout Int,
        skippedKind: inout Int,
        skippedNowPlaying: inout Int,
        skippedNoParse: inout Int
    ) {
        if elements.count >= 200 { return }

        let rawLabel = view.accessibilityLabel ?? ""
        let trimmedLabel = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedLabel.isEmpty {
            let winFrame = view.convert(view.bounds, to: window)
            let isOnScreen = !view.isHidden
                && view.alpha > 0.01
                && view.isUserInteractionEnabled
                && !winFrame.isEmpty
                && screenBounds.intersects(winFrame)

            if isOnScreen {
                let className = NSStringFromClass(type(of: view))
                let id = view.accessibilityIdentifier ?? ""
                let val = view.accessibilityValue ?? ""

                // Collect ancestor chain up to 6 levels
                var ancestors: [String] = []
                var curr = view.superview
                while let parent = curr, ancestors.count < 6 {
                    ancestors.append(NSStringFromClass(type(of: parent)))
                    curr = parent.superview
                }

                var isCandidate = false
                var parsedName: String? = nil
                var matchedRule: String? = nil

                switch classifyStrictPlaylistRow(label: trimmedLabel, ancestors: ancestors) {
                case .kept(let name, let rule):
                    isCandidate = true
                    parsedName = name
                    matchedRule = rule
                    keptCount += 1
                case .skippedNowPlaying: skippedNowPlaying += 1
                case .skippedKind: skippedKind += 1
                case .skippedNoParse: skippedNoParse += 1
                case .skippedNotYourLibrary: break
                }

                elements.append(STScannedElement(
                    className: className,
                    accessibilityIdentifier: id,
                    label: trimmedLabel,
                    value: val,
                    frame: winFrame,
                    ancestors: ancestors,
                    isPlaylistCandidate: isCandidate,
                    parsedName: parsedName,
                    matchedRule: matchedRule,
                    view: view
                ))

                if elements.count >= 200 { return }
            }
        }

        for subview in view.subviews {
            collectElements(
                in: subview,
                window: window,
                screenBounds: screenBounds,
                elements: &elements,
                keptCount: &keptCount,
                skippedKind: &skippedKind,
                skippedNowPlaying: &skippedNowPlaying,
                skippedNoParse: &skippedNoParse
            )
            if elements.count >= 200 { return }
        }
    }

    private enum STPlaylistRowResult {
        case kept(name: String, rule: String)
        case skippedNowPlaying
        case skippedKind(kind: String)
        case skippedNoParse
        case skippedNotYourLibrary
    }

    /// Evaluates strict playlist row rules:
    /// (a) Some ancestor class name contains "YourLibrary"
    /// (b) No ancestor class name contains "NowPlaying"
    /// (c) The label parses as kind Playlist
    private static func classifyStrictPlaylistRow(
        label: String,
        ancestors: [String]
    ) -> STPlaylistRowResult {
        // (b) No ancestor class name contains "NowPlaying"
        if ancestors.contains(where: { $0.contains("NowPlaying") }) {
            return .skippedNowPlaying
        }

        // (a) Some ancestor class name contains "YourLibrary"
        guard ancestors.contains(where: { $0.contains("YourLibrary") }) else {
            return .skippedNotYourLibrary
        }

        // (c) Label parsing
        let parsed = STLibraryLabelParser.classifyLibraryLabel(label)
        switch parsed {
        case .playlist(let name):
            return .kept(name: name, rule: "YourLibrary + kind Playlist")
        case .otherKind(let kind):
            return .skippedKind(kind: kind)
        case .noParse:
            return .skippedNoParse
        }
    }

    /// Scans on-screen elements, extracts playlist candidates, merges into cache v2, and returns all cached items.
    static func scanAndCachePlaylists() -> [STCachedPlaylist] {
        let candidates = scanOnScreenElements(logSummary: true).filter { $0.isPlaylistCandidate }
        let discovered = candidates.compactMap { c in c.parsedName.map { STCachedPlaylist(name: $0, lastLabel: c.label) } }
        if !discovered.isEmpty { STLibraryCache.shared.merge(playlists: discovered) }
        return STLibraryCache.shared.allPlaylists()
    }

    /// Activates an on-screen element with matching name or label using STRowActivator.
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

    /// Executes `libscan` command logic.
    static func runScanCommand() -> [String] {
        let elements = scanOnScreenElements(logSummary: true)
        let candidates = elements.filter { $0.isPlaylistCandidate }
        let discovered = candidates.compactMap { c in c.parsedName.map { STCachedPlaylist(name: $0, lastLabel: c.label) } }
        if !discovered.isEmpty { STLibraryCache.shared.merge(playlists: discovered) }

        var lines = ["> libscan: scanned \(elements.count) element(s), \(candidates.count) playlist candidate(s):"]
        if elements.isEmpty { lines.append("  (no on-screen labelled elements found in non-overlay windows)") }
        for (idx, elem) in elements.enumerated() { lines.append("  [\(idx + 1)] \(elem.summary)") }
        return lines
    }
}
