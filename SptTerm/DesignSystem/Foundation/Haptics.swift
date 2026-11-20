#if canImport(UIKit)
import UIKit

/// Central haptic vocabulary. Every control routes through here so intensity
/// stays consistent and can be disabled in one place later.
@MainActor
enum TermHaptic {
    static func tap() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light, intensity: CGFloat = 0.7) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred(intensity: intensity)
    }

    static func playPause() {
        impact(.medium, intensity: 0.9)
    }

    static func presetChange() {
        impact(.rigid, intensity: 0.8)
    }

    static func detent() {
        impact(.light, intensity: 0.5)
    }

    static func destructive() {
        impact(.heavy, intensity: 0.7)
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
#else
@MainActor
enum TermHaptic {
    static func tap() {}
    static func impact(_ style: Int = 0, intensity: Double = 0.7) {}
    static func playPause() {}
    static func presetChange() {}
    static func detent() {}
    static func destructive() {}
    static func success() {}
}
#endif
