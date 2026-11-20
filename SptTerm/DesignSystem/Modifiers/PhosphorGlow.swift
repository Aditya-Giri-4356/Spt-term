import SwiftUI

extension View {
    /// Two stacked soft shadows approximate the CRT phosphor bloom used in
    /// the design (`drop-shadow: 0 0 4px currentColor` plus panel ambient).
    func phosphorGlow(_ color: Color, radius: CGFloat = 5, intensity: Double = 1) -> some View {
        self
            .shadow(color: TermColorMath.withAlpha(color, 0.55 * intensity), radius: radius * 0.45)
            .shadow(color: TermColorMath.withAlpha(color, 0.30 * intensity), radius: radius)
    }
}
