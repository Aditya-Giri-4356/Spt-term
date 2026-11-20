import SwiftUI

struct TerminalTypeModifier: ViewModifier {
    let token: TermTypeToken
    let color: Color?
    let uppercase: Bool

    @ScaledMetric private var scale: CGFloat

    init(token: TermTypeToken, color: Color?, uppercase: Bool) {
        self.token = token
        self.color = color
        self.uppercase = uppercase
        _scale = ScaledMetric(wrappedValue: 1, relativeTo: token.relativeTo)
    }

    func body(content: Content) -> some View {
        content
            .font(TermFont.mono(token.scaled(by: scale), token.weight))
            .tracking(token.tracking)
            .foregroundColor(color)
            .textCase(uppercase || token.isUppercase ? .uppercase : nil)
    }
}

extension View {
    /// Applies a typography token. Growth is capped at 1.25× so the fixed
    /// character grid survives accessibility sizes.
    func termType(
        _ token: TermTypeToken,
        color: Color? = nil,
        uppercase: Bool = false
    ) -> some View {
        modifier(TerminalTypeModifier(token: token, color: color, uppercase: uppercase))
    }
}
