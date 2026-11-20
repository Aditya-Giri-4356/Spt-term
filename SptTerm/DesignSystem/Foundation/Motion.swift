import SwiftUI

enum TermMotion {
    /// Button press, selection flips, flag changes.
    static let snap = Animation.spring(response: 0.26, dampingFraction: 0.82)

    /// Panel content enter/exit, list row insertion.
    static let panel = Animation.spring(response: 0.34, dampingFraction: 0.86)

    /// Mini-player expansion into Now Playing.
    static let expand = Animation.spring(response: 0.46, dampingFraction: 0.88)

    /// Scrubber / fader follow.
    static let control = Animation.linear(duration: 0.08)

    /// Blinking terminal cursor.
    static let blink = Animation.easeInOut(duration: 0.7)

    static func pulse(_ duration: Double = 1.6) -> Animation {
        .easeInOut(duration: duration).repeatForever(autoreverses: true)
    }
}
