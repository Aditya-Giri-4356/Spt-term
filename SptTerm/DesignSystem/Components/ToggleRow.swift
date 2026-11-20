import SwiftUI

/// Settings row rendered as `[X]` / `[ ]` with a 44pt touch envelope.
struct ToggleRow: View {
    @EnvironmentObject private var theme: TerminalTheme

    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
            TermHaptic.tap()
        } label: {
            HStack(spacing: TermSpace.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .termType(TermType.bodySM, color: theme.palette.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let detail {
                        Text(detail)
                            .termType(TermType.telemetryTight, color: theme.palette.textMuted)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: TermSpace.xs)
                Text(isOn ? "[X]" : "[ ]")
                    .termType(TermType.labelMD, color: isOn ? theme.palette.onAccent : theme.palette.textMuted)
                    .frame(width: 34, height: 26)
                    .background(isOn ? theme.palette.accent : Color.clear)
                    .overlay(
                        Rectangle()
                            .strokeBorder(isOn ? theme.palette.accent : theme.palette.accentDeep, lineWidth: 1)
                    )
            }
            .frame(minHeight: TermSpace.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(TermPressStyle())
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

struct ToggleRow_Previews: PreviewProvider {
    static var previews: some View {
        TerminalPreview {
            TogglePreview()
        }
    }

    private struct TogglePreview: View {
        @State private var scanlines = true
        @State private var bloom = false

        var body: some View {
            VStack(spacing: TermSpace.sm) {
                ToggleRow(
                    title: "CRT Scanline Raster Overlay",
                    detail: "Interlaced horizontal raster sweeps (3px pitch)",
                    isOn: $scanlines
                )
                ToggleRow(
                    title: "Phosphor Glow & Optical Bloom",
                    detail: "Simulates cathode ray tube light diffusion",
                    isOn: $bloom
                )
            }
        }
    }
}
