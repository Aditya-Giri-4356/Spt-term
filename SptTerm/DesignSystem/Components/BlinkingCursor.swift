import SwiftUI

/// `▋` block cursor used by the shell input and live lyrics line.
struct BlinkingCursor: View {
    @EnvironmentObject private var theme: TerminalTheme

    var width: CGFloat = 7
    var height: CGFloat = 14
    var color: Color?

    @State private var isDim = false

    var body: some View {
        Rectangle()
            .fill(color ?? theme.palette.accent)
            .frame(width: width, height: height)
            .opacity(isDim ? 0.12 : 1)
            .onAppear {
                withAnimation(TermMotion.blink.repeatForever(autoreverses: true)) {
                    isDim = true
                }
            }
            .accessibilityHidden(true)
    }
}

struct BlinkingCursor_Previews: PreviewProvider {
    static var previews: some View {
        TerminalPreview {
            HStack(spacing: TermSpace.xs) {
                Text("spt.term:~$")
                    .termType(TermType.telemetry, color: .gray)
                BlinkingCursor()
            }
        }
    }
}
