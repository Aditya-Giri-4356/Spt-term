import UIKit

/// Inspects and interacts with Spotify's native on-screen player controls.
/// Runs exclusively on the main thread and touches Spotify views only to read
/// accessibility properties or perform a single activated press.
final class STSpotifyUIHook {
    struct Candidate {
        let view: UIView
        let className: String
        let label: String
        let identifier: String
        let value: String
        let traits: UInt64
        let isHidden: Bool
        let alpha: CGFloat
        let isUserInteractionEnabled: Bool
        let isSelected: Bool
        let windowFrame: CGRect
        let isOnScreen: Bool

        var summary: String {
            "[\(className)] label=\"\(label)\" id=\"\(identifier)\" val=\"\(value)\" selected=\(isSelected ? 1 : 0) onScreen=\(isOnScreen ? 1 : 0) frame=\(NSCoder.string(for: windowFrame))"
        }
    }

    /// Recursively scans Spotify windows (excluding SptTerm overlay window) for repeat/shuffle controls.
    static func scanCandidates(matching query: String? = nil) -> [Candidate] {
        guard Thread.isMainThread else {
            return DispatchQueue.main.sync {
                scanCandidates(matching: query)
            }
        }

        var results: [Candidate] = []
        let screenBounds = UIScreen.main.bounds

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                // Exclude SptTerm tweak window
                if window is STTweakWindow || window.windowLevel > UIWindow.Level.alert {
                    continue
                }
                collectCandidates(in: window, window: window, screenBounds: screenBounds, query: query, results: &results)
            }
        }

        return results
    }

    private static func collectCandidates(
        in view: UIView,
        window: UIWindow,
        screenBounds: CGRect,
        query: String?,
        results: inout [Candidate]
    ) {
        let label = view.accessibilityLabel ?? ""
        let identifier = view.accessibilityIdentifier ?? ""
        let val = view.accessibilityValue ?? ""
        let className = NSStringFromClass(type(of: view))

        let combined = "\(label) \(identifier) \(val)".lowercased()
        let matchesQuery: Bool
        if let query = query?.lowercased() {
            matchesQuery = combined.contains(query)
        } else {
            matchesQuery = combined.contains("repeat") || combined.contains("shuffle")
        }

        if matchesQuery {
            let winFrame = view.convert(view.bounds, to: window)
            let isOnScreen = !view.isHidden && view.alpha > 0.01 && view.isUserInteractionEnabled && !winFrame.isEmpty && screenBounds.intersects(winFrame)
            let isSelected = (view as? UIControl)?.isSelected ?? false

            let candidate = Candidate(
                view: view,
                className: className,
                label: label,
                identifier: identifier,
                value: val,
                traits: view.accessibilityTraits.rawValue,
                isHidden: view.isHidden,
                alpha: view.alpha,
                isUserInteractionEnabled: view.isUserInteractionEnabled,
                isSelected: isSelected,
                windowFrame: winFrame,
                isOnScreen: isOnScreen
            )
            results.append(candidate)
        }

        for subview in view.subviews {
            collectCandidates(in: subview, window: window, screenBounds: screenBounds, query: query, results: &results)
        }
    }

    /// One-shot press of Spotify's repeat or shuffle button.
    /// Chooses the best visible on-screen candidate, triggers once, logs before and after 0.6s.
    static func press(type: String) async -> (success: Bool, before: String, after: String, candidate: Candidate?) {
        let targetType = type.lowercased()
        let query = targetType.contains("repeat") ? "repeat" : "shuffle"

        let candidates = await MainActor.run { () -> [Candidate] in
            let all = scanCandidates(matching: query)
            for c in all {
                STLog.log("SptTerm: uihook candidate: \(c.summary)")
            }
            return all
        }

        guard let best = (candidates.first(where: { $0.isOnScreen }) ?? candidates.first) else {
            STLog.log("SptTerm: uihook no candidates (full-screen player probably not open)")
            return (false, "none", "none", nil)
        }

        let beforeDesc = "label=\"\(best.label)\" val=\"\(best.value)\" selected=\(best.isSelected ? 1 : 0)"
        STLog.log("SptTerm: uihook press [\(query)] BEFORE: \(best.className) \(beforeDesc)")

        let activated = await MainActor.run { () -> Bool in
            var ok = best.view.accessibilityActivate()
            if !ok, let control = best.view as? UIControl {
                control.sendActions(for: .touchUpInside)
                ok = true
            }
            return ok
        }

        try? await Task.sleep(nanoseconds: 600_000_000)

        let afterDesc = await MainActor.run { () -> String in
            let curLabel = best.view.accessibilityLabel ?? ""
            let curVal = best.view.accessibilityValue ?? ""
            let curSel = (best.view as? UIControl)?.isSelected ?? false
            let desc = "label=\"\(curLabel)\" val=\"\(curVal)\" selected=\(curSel ? 1 : 0)"
            STLog.log("SptTerm: uihook press [\(query)] AFTER (0.6s): \(desc)")
            return desc
        }

        return (activated, beforeDesc, afterDesc, best)
    }
}
