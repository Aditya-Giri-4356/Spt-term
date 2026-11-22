import UIKit

/// Snapshot of an accessible element in the Spotify view hierarchy.
struct STUIElementSnapshot: Equatable {
    let className: String
    let label: String
    let identifier: String
    let value: String
    let frame: CGRect
    let isOnScreen: Bool
    weak var view: UIView?

    var key: String {
        "\(className)|\(label)|\(identifier)|\(Int(frame.origin.x.rounded())),\(Int(frame.origin.y.rounded())),\(Int(frame.size.width.rounded())),\(Int(frame.size.height.rounded()))"
    }

    static func == (lhs: STUIElementSnapshot, rhs: STUIElementSnapshot) -> Bool {
        lhs.key == rhs.key
    }
}

/// Tools to snapshot and interact with arbitrary on-screen elements across non-overlay windows.
@MainActor
final class STSpotifyUIElements {
    /// Captures all accessible elements across non-overlay windows.
    static func snapshotAllAccessibleElements() -> [STUIElementSnapshot] {
        var elements: [STUIElementSnapshot] = []
        let screenBounds = UIScreen.main.bounds

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if window is STTweakWindow || window.windowLevel > UIWindow.Level.alert {
                    continue
                }
                collectElements(in: window, window: window, screenBounds: screenBounds, elements: &elements)
            }
        }
        return elements
    }

    private static func collectElements(
        in view: UIView,
        window: UIWindow,
        screenBounds: CGRect,
        elements: inout [STUIElementSnapshot]
    ) {
        let label = view.accessibilityLabel ?? ""
        let id = view.accessibilityIdentifier ?? ""
        let val = view.accessibilityValue ?? ""
        let className = NSStringFromClass(type(of: view))

        if !label.isEmpty || !id.isEmpty || !val.isEmpty || (view is UIControl) {
            let winFrame = view.convert(view.bounds, to: window)
            let isOnScreen = !view.isHidden && view.alpha > 0.01 && view.isUserInteractionEnabled && !winFrame.isEmpty && screenBounds.intersects(winFrame)
            elements.append(STUIElementSnapshot(
                className: className,
                label: label,
                identifier: id,
                value: val,
                frame: winFrame,
                isOnScreen: isOnScreen,
                view: view
            ))
        }

        for subview in view.subviews {
            collectElements(in: subview, window: window, screenBounds: screenBounds, elements: &elements)
        }
    }

    /// Dumps up to `limit` on-screen accessible elements that have a non-empty label.
    static func dumpOnScreenElements(limit: Int = 150) -> [STUIElementSnapshot] {
        let all = snapshotAllAccessibleElements()
        return all
            .filter { $0.isOnScreen && !$0.label.isEmpty }
            .prefix(limit)
            .map { $0 }
    }

    /// Activates a single on-screen element whose label contains the substring (case-insensitive).
    /// If more than one match, lists them and does nothing.
    /// Press once; logs before and after.
    static func tapElement(matching substring: String) -> [String] {
        let query = substring.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return ["usage: uihook tap <substring>"]
        }

        let candidates = snapshotAllAccessibleElements().filter {
            $0.isOnScreen && $0.label.localizedCaseInsensitiveContains(query)
        }

        if candidates.isEmpty {
            STLog.log("SptTerm: uihook tap no matches for '\(query)'")
            return ["> uihook tap: no elements matching '\(query)'"]
        }

        if candidates.count > 1 {
            STLog.log("SptTerm: uihook tap ambiguous (\(candidates.count) matches for '\(query)')")
            var lines = ["> uihook tap: multiple elements matching '\(query)' (\(candidates.count)), ambiguous - did nothing:"]
            for (idx, c) in candidates.prefix(10).enumerated() {
                lines.append("  [\(idx + 1)] [\(c.className)] label=\"\(c.label)\" id=\"\(c.identifier)\" frame=\(NSCoder.string(for: c.frame))")
            }
            return lines
        }

        let target = candidates[0]
        let beforeVal = target.value
        STLog.log("SptTerm: uihook tap BEFORE: [\(target.className)] label=\"\(target.label)\" id=\"\(target.identifier)\" val=\"\(beforeVal)\"")

        guard let view = target.view else {
            return ["> uihook tap: element view is nil"]
        }

        var activated = view.accessibilityActivate()
        if !activated, let control = view as? UIControl {
            control.sendActions(for: .touchUpInside)
            activated = true
        }

        let afterVal = view.accessibilityValue ?? ""
        STLog.log("SptTerm: uihook tap AFTER: val=\"\(afterVal)\" ret=\(activated ? 1 : 0)")
        return ["> uihook tap: activated [\(target.className)] '\(target.label)' ret=\(activated ? 1 : 0)"]
    }
}
