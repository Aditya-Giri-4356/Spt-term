import UIKit

/// Result of a UI hook press operation.
struct UIHookPressResult {
    let candidateFound: Bool
    let activated: Bool
    let beforeDesc: String
    let afterLabel: String
    let afterValue: String
    let isSelected: Bool
}

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

    /// Deduplicates candidates sharing the same window frame.
    /// Prefers (a) non-empty accessibilityIdentifier, then (b) UIControl, then (c) first.
    static func deduplicateCandidates(_ candidates: [Candidate]) -> [Candidate] {
        var groups: [String: [Candidate]] = [:]
        var order: [String] = []

        for c in candidates {
            let r = c.windowFrame
            let key = "\(Int(r.origin.x.rounded())),\(Int(r.origin.y.rounded())),\(Int(r.size.width.rounded())),\(Int(r.size.height.rounded()))"
            if groups[key] == nil {
                order.append(key)
                groups[key] = []
            }
            groups[key]?.append(c)
        }

        var results: [Candidate] = []
        for key in order {
            guard let list = groups[key] else { continue }
            let sorted = list.sorted { a, b in
                let aHasId = !a.identifier.isEmpty
                let bHasId = !b.identifier.isEmpty
                if aHasId != bHasId {
                    return aHasId && !bHasId
                }
                let aIsCtrl = a.view is UIControl
                let bIsCtrl = b.view is UIControl
                if aIsCtrl != bIsCtrl {
                    return aIsCtrl && !bIsCtrl
                }
                return false
            }
            if let best = sorted.first {
                results.append(best)
            }
        }
        return results
    }

    /// One-shot press of Spotify's repeat or shuffle button.
    /// Chooses the best visible on-screen candidate (deduped by frame), triggers once.
    /// For shuffle: handles second-mode menu diffing and activation.
    /// Waits 0.6s and returns the read-back.
    static func press(type: String) async -> UIHookPressResult {
        let isShuffle = type.lowercased().contains("shuffle")
        let query = isShuffle ? "shuffle" : "repeat"

        // 1. Pre-press element snapshot for shuffle diffing
        let prePressElements: [STUIElementSnapshot] = await MainActor.run {
            if isShuffle {
                return STSpotifyUIElements.snapshotAllAccessibleElements()
            }
            return []
        }

        // 2. Discover candidates and pick best candidate
        let chosenCandidate = await MainActor.run { () -> Candidate? in
            let raw = scanCandidates(matching: query)
            let deduped = deduplicateCandidates(raw)
            for c in deduped {
                STLog.log("SptTerm: uihook candidate: \(c.summary)")
            }
            let onScreen = deduped.filter { $0.isOnScreen }
            let sorted = onScreen.sorted { a, b in
                let aHasId = !a.identifier.isEmpty
                let bHasId = !b.identifier.isEmpty
                if aHasId != bHasId { return aHasId && !bHasId }
                let aIsCtrl = a.view is UIControl
                let bIsCtrl = b.view is UIControl
                if aIsCtrl != bIsCtrl { return aIsCtrl && !bIsCtrl }
                return false
            }
            return sorted.first ?? deduped.first
        }

        guard let best = chosenCandidate else {
            STLog.log("SptTerm: uihook \(query) no candidates (full-screen player probably not open)")
            return UIHookPressResult(
                candidateFound: false,
                activated: false,
                beforeDesc: "none",
                afterLabel: "",
                afterValue: "",
                isSelected: false
            )
        }

        let beforeDesc = "label=\"\(best.label)\" val=\"\(best.value)\" selected=\(best.isSelected ? 1 : 0)"
        STLog.log("SptTerm: uihook press [\(query)] BEFORE: \(best.className) \(beforeDesc)")

        // 3. Press once only
        let activated = await MainActor.run { () -> Bool in
            var ok = best.view.accessibilityActivate()
            if !ok, let control = best.view as? UIControl {
                control.sendActions(for: .touchUpInside)
                ok = true
            }
            return ok
        }

        // 4. Wait 0.6 s
        try? await Task.sleep(nanoseconds: 600_000_000)

        // 5. Post-press inspection and shuffle second-mode menu handling
        let (afterLabel, afterVal, curSel) = await MainActor.run { () -> (String, String, Bool) in
            if isShuffle {
                let postPressElements = STSpotifyUIElements.snapshotAllAccessibleElements()
                let preKeys = Set(prePressElements.map(\.key))
                let newElements = postPressElements.filter { !preKeys.contains($0.key) }

                for elem in newElements {
                    STLog.log("SptTerm: uihook new element: [\(elem.className)] label=\"\(elem.label)\" id=\"\(elem.identifier)\" val=\"\(elem.value)\" frame=\(NSCoder.string(for: elem.frame))")
                }

                if !newElements.isEmpty {
                    let candidates = newElements.filter { elem in
                        guard elem.isOnScreen else { return false }
                        let lower = elem.label.lowercased()
                        return lower.contains("shuffle") &&
                            !lower.contains("smart") &&
                            !lower.contains("ai") &&
                            !lower.contains("dj") &&
                            !lower.contains("enhance") &&
                            !lower.contains("auto")
                    }

                    if candidates.count == 1 {
                        let target = candidates[0]
                        if let view = target.view {
                            var ok = view.accessibilityActivate()
                            if !ok, let control = view as? UIControl {
                                control.sendActions(for: .touchUpInside)
                                ok = true
                            }
                            STLog.log("SptTerm: uihook activated standard shuffle option: [\(target.className)] label=\"\(target.label)\" ret=\(ok ? 1 : 0)")
                        }
                    } else if candidates.count > 1 {
                        STLog.log("SptTerm: uihook shuffle menu ambiguous (\(candidates.count) matches)")
                    } else {
                        STLog.log("SptTerm: uihook shuffle menu ambiguous (no standard shuffle option)")
                    }
                }
            }

            let curLabel = best.view.accessibilityLabel ?? ""
            let curVal = best.view.accessibilityValue ?? ""
            let curSel = (best.view as? UIControl)?.isSelected ?? false
            STLog.log("SptTerm: uihook press [\(query)] AFTER (0.6s): label=\"\(curLabel)\" val=\"\(curVal)\" selected=\(curSel ? 1 : 0)")
            return (curLabel, curVal, curSel)
        }

        return UIHookPressResult(
            candidateFound: true,
            activated: activated,
            beforeDesc: beforeDesc,
            afterLabel: afterLabel,
            afterValue: afterVal,
            isSelected: curSel
        )
    }
}
