import SwiftUI

/// Unicode-style separators rendered as strokes so they stay pixel sharp.
struct ASCIIRule: View {
    enum Style {
        case thin
        case thick
        case dashed
    }

    @EnvironmentObject private var theme: TerminalTheme
    var style: Style = .thin

    @ViewBuilder
    var body: some View {
        switch style {
        case .thin:
            Rectangle()
                .fill(theme.palette.hairline)
                .frame(height: 1)
        case .thick:
            Rectangle()
                .fill(theme.palette.accentDeep)
                .frame(height: 2)
        case .dashed:
            DashLine()
                .stroke(
                    theme.palette.hairline,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
                .frame(height: 1)
        }
    }
}

private struct DashLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

struct ASCIIRule_Previews: PreviewProvider {
    static var previews: some View {
        TerminalPreview {
            VStack(spacing: TermSpace.md) {
                ASCIIRule(style: .thin)
                ASCIIRule(style: .thick)
                ASCIIRule(style: .dashed)
            }
        }
    }
}
