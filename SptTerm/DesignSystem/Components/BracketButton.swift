import SwiftUI

struct TermPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(TermMotion.snap, value: configuration.isPressed)
    }
}

/// `[ PLAY ]`-style action. `primary` is the inverted phosphor block.
struct BracketButton: View {
    enum Variant {
        case primary
        case ghost
        case quiet
    }

    @EnvironmentObject private var theme: TerminalTheme

    let title: String
    var glyph: String?
    var variant: Variant = .ghost
    var isActive: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button {
            TermHaptic.tap()
            action()
        } label: {
            HStack(spacing: TermSpace.xs) {
                if let glyph {
                    Text(glyph)
                        .termType(TermType.glyphSM)
                        .lineLimit(1)
                }
                Text(title)
                    .termType(TermType.labelSM)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity, minHeight: TermSpace.hit)
            .padding(.horizontal, TermSpace.sm)
            .background(backgroundColor)
            .overlay(Rectangle().strokeBorder(borderColor, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: TermRadius.button))
        }
        .buttonStyle(TermPressStyle())
        .phosphorGlow(theme.palette.accent, radius: 7, intensity: usesInvertedFill ? 0.55 : 0)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var usesInvertedFill: Bool {
        variant == .primary || isActive
    }

    private var foregroundColor: Color {
        if usesInvertedFill { return theme.palette.onAccent }
        return variant == .quiet ? theme.palette.textSecondary : theme.palette.accent
    }

    private var backgroundColor: Color {
        if usesInvertedFill { return theme.palette.accent }
        return variant == .quiet ? theme.palette.panelRaised : theme.palette.background
    }

    private var borderColor: Color {
        if usesInvertedFill { return theme.palette.accent }
        return variant == .quiet ? theme.palette.hairline : theme.palette.accentDeep
    }
}

struct BracketButton_Previews: PreviewProvider {
    static var previews: some View {
        TerminalPreview {
            VStack(spacing: TermSpace.sm) {
                BracketButton(title: "Shuffle All", glyph: "⚡", variant: .primary) {}
                BracketButton(title: "Sync Offline", glyph: "↓") {}
                BracketButton(title: "Sort: Recent", glyph: "⇅", variant: .quiet) {}
                BracketButton(title: "Selected", variant: .ghost, isActive: true) {}
            }
        }
    }
}
