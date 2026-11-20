import Foundation

extension Double {
    /// Clamped to 0...1.
    var clampedUnit: Double { Swift.min(Swift.max(self, 0), 1) }
}

enum TermFormat {
    /// 138 → "02:18"
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// -74 → "-01:14", positive values keep the "+" so the UI reads like telemetry.
    static func signedDuration(_ seconds: Double) -> String {
        let sign = seconds < 0 ? "-" : "+"
        return sign + duration(abs(seconds))
    }

    /// 0.6512 → "65.1%"
    static func percent(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f%%", value * 100)
    }

    /// -4.2 → "-4.2dB"
    static func decibels(_ value: Double) -> String {
        String(format: "%+.1fdB", value)
    }
}
