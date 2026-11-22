import UIKit

/// Represents an on-screen accessible element with ancestor hierarchy and playlist-row classification.
struct STScannedElement {
    let className: String
    let accessibilityIdentifier: String
    let label: String
    let value: String
    let frame: CGRect
    let ancestors: [String]
    let isPlaylistCandidate: Bool
    let matchedRule: String?
    weak var view: UIView?

    var summary: String {
        let idPart = accessibilityIdentifier.isEmpty ? "" : " id=\"\(accessibilityIdentifier)\""
        let valPart = value.isEmpty ? "" : " val=\"\(value)\""
        let candPart = isPlaylistCandidate ? " [CANDIDATE: \(matchedRule ?? "")]" : ""
        let ancPart = ancestors.isEmpty ? "" : " ancestors=\(ancestors.joined(separator: "->"))"
        return "[\(className)] label=\"\(label)\"\(idPart)\(valPart) frame=(\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.width)),\(Int(frame.height)))\(ancPart)\(candPart)"
    }
}

/// Scans on-screen labelled accessible elements from Spotify's non-overlay windows,
/// classifies candidates for playlist rows using strict heuristics, and coordinates
/// with STLibraryCache.
@MainActor
final class STSpotifyLibraryScanner {

    /// Registers the `libscan` and `libclear` commands into the passed-in registry instance (not .shared).
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
    }

    /// Enumerates up to 200 on-screen labelled accessible elements across non-overlay windows.
    static func scanOnScreenElements() -> [STScannedElement] {
        var elements: [STScannedElement] = []
        let screenBounds = UIScreen.main.bounds

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if window is STTweakWindow || window.windowLevel > UIWindow.Level.alert {
                    continue
                }
                collectElements(in: window, window: window, screenBounds: screenBounds, elements: &elements)
                if elements.count >= 200 {
                    break
                }
            }
            if elements.count >= 200 {
                break
            }
        }
        return elements
    }

    private static func collectElements(
        in view: UIView,
        window: UIWindow,
        screenBounds: CGRect,
        elements: inout [STScannedElement]
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

                // Evaluate heuristic playlist-row classification
                let classification = classifyPlaylistRow(
                    view: view,
                    className: className,
                    label: trimmedLabel,
                    winFrame: winFrame,
                    ancestors: ancestors
                )

                if classification.isCandidate {
                    STLog.log("SptTerm: libscan candidate matched: [\(className)] label=\"\(trimmedLabel)\" rule=\(classification.rule ?? "")")
                }

                elements.append(STScannedElement(
                    className: className,
                    accessibilityIdentifier: id,
                    label: trimmedLabel,
                    value: val,
                    frame: winFrame,
                    ancestors: ancestors,
                    isPlaylistCandidate: classification.isCandidate,
                    matchedRule: classification.rule,
                    view: view
                ))

                if elements.count >= 200 { return }
            }
        }

        for subview in view.subviews {
            collectElements(in: subview, window: window, screenBounds: screenBounds, elements: &elements)
            if elements.count >= 200 { return }
        }
    }

    /// Evaluates whether an accessible element matches the heuristic playlist-row requirements:
    /// 1. Label length between 2 and 120 characters.
    /// 2. Frame width at least 200pt.
    /// 3. Inside a scrollable container ancestor (UICollectionView/UITableView/UIScrollView).
    /// 4. Cell-like or button-like element (UIControl, UICollectionViewCell, UITableViewCell, or matching class/trait).
    /// 5. NOT a tab-bar or navigation-bar item.
    static func classifyPlaylistRow(
        view: UIView,
        className: String,
        label: String,
        winFrame: CGRect,
        ancestors: [String]
    ) -> (isCandidate: Bool, rule: String?) {
        guard label.count >= 2 && label.count <= 120 else {
            return (false, nil)
        }

        guard winFrame.width >= 200.0 else {
            return (false, nil)
        }

        let lowerClass = className.lowercased()
        if lowerClass.contains("tabbar") || lowerClass.contains("navigationbar") || lowerClass.contains("navbar") {
            return (false, nil)
        }
        for anc in ancestors {
            let lowerAnc = anc.lowercased()
            if lowerAnc.contains("tabbar") || lowerAnc.contains("navigationbar") || lowerAnc.contains("navbar") {
                return (false, nil)
            }
        }

        var scrollAncestor: String? = nil
        var currentParent = view.superview
        while let p = currentParent {
            if p is UIScrollView {
                scrollAncestor = NSStringFromClass(type(of: p))
                break
            }
            let pName = NSStringFromClass(type(of: p)).lowercased()
            if pName.contains("scrollview") || pName.contains("collectionview") || pName.contains("tableview") {
                scrollAncestor = NSStringFromClass(type(of: p))
                break
            }
            currentParent = p.superview
        }
        guard let scrollName = scrollAncestor else {
            return (false, nil)
        }

        let isCellOrControl = (view is UIControl)
            || (view is UICollectionViewCell)
            || (view is UITableViewCell)
            || lowerClass.contains("cell")
            || lowerClass.contains("button")
            || lowerClass.contains("row")
            || lowerClass.contains("item")
            || lowerClass.contains("control")
            || (view.accessibilityTraits.rawValue & UIAccessibilityTraits.button.rawValue) != 0

        guard isCellOrControl else {
            return (false, nil)
        }

        let ruleDesc = "cell_or_btn in \(scrollName), w=\(Int(winFrame.width))>=200, len=\(label.count)"
        return (true, ruleDesc)
    }

    /// Scans on-screen elements, extracts playlist candidates, merges into cache, and returns all cached items.
    static func scanAndCachePlaylists() -> [STCachedPlaylist] {
        let elements = scanOnScreenElements()
        let candidates = elements.filter { $0.isPlaylistCandidate }

        var discovered: [STCachedPlaylist] = []
        for c in candidates {
            let rawLabel = c.label
            let cleanName: String
            if let first = rawLabel.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
                cleanName = first
            } else {
                cleanName = rawLabel
            }
            discovered.append(STCachedPlaylist(name: cleanName, label: rawLabel))
        }

        if !discovered.isEmpty {
            STLibraryCache.shared.merge(playlists: discovered)
        }

        return STLibraryCache.shared.allPlaylists()
    }

    /// Activates an on-screen element with matching label.
    static func activatePlaylist(label: String) -> (success: Bool, message: String) {
        let targetLabel = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let elements = scanOnScreenElements()

        guard let match = elements.first(where: {
            $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == targetLabel
        }), let targetView = match.view else {
            STLog.log("SptTerm: activatePlaylist NOT ON SCREEN: label=\"\(label)\"")
            return (false, "NOT ON SCREEN - open Spotify Library")
        }

        let beforeDesc = "[\(match.className)] label=\"\(match.label)\" val=\"\(match.value)\""
        STLog.log("SptTerm: activatePlaylist BEFORE: \(beforeDesc)")

        var activated = targetView.accessibilityActivate()
        if !activated, let control = targetView as? UIControl {
            control.sendActions(for: .touchUpInside)
            activated = true
        }

        let afterVal = targetView.accessibilityValue ?? ""
        STLog.log("SptTerm: activatePlaylist AFTER: activated=\(activated ? 1 : 0) val=\"\(afterVal)\"")
        return (true, "ACTIVATED")
    }

    /// Executes `libscan` command logic.
    static func runScanCommand() -> [String] {
        let elements = scanOnScreenElements()
        let candidates = elements.filter { $0.isPlaylistCandidate }

        // Also merge discovered playlist candidates into cache
        var discovered: [STCachedPlaylist] = []
        for c in candidates {
            let rawLabel = c.label
            let cleanName = rawLabel.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rawLabel
            discovered.append(STCachedPlaylist(name: cleanName.isEmpty ? rawLabel : cleanName, label: rawLabel))
        }
        if !discovered.isEmpty {
            STLibraryCache.shared.merge(playlists: discovered)
        }

        var lines: [String] = [
            "> libscan: scanned \(elements.count) element(s), \(candidates.count) playlist candidate(s):"
        ]

        if elements.isEmpty {
            lines.append("  (no on-screen labelled elements found in non-overlay windows)")
            return lines
        }

        for (idx, elem) in elements.enumerated() {
            lines.append("  [\(idx + 1)] \(elem.summary)")
        }

        return lines
    }
}
