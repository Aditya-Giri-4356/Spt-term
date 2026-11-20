import SwiftUI

/// Vertical segmented fader used by the 10-band EQ. Fills from the bottom in
/// discrete cells and snaps a haptic when crossing a detent.
struct FaderSlider: View {
    @EnvironmentObject private var theme: TerminalTheme

    @Binding var value: Double
    var label: String
    var range: ClosedRange<Double> = -12...12
    var cells: Int = 10
    var detents: [Double] = [0]
    var height: CGFloat = 96

    @State private var lastDetentIndex = -1

    var body: some View {
        VStack(spacing: TermSpace.xs) {
            Text(label)
                .termType(TermType.telemetryTight, color: theme.palette.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            GeometryReader { proxy in
                VStack(spacing: 2) {
                    ForEach(0..<cells, id: \.self) { index in
                        let threshold = 1 - Double(index + 1) / Double(cells)
                        Rectangle()
                            .fill(
                                normalized > threshold
                                    ? theme.palette.accent
                                    : TermColorMath.withAlpha(theme.palette.accentDeep, 0.35)
                            )
                            .frame(height: cellHeight(for: proxy.size.height))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            update(at: gesture.location.y, height: proxy.size.height)
                        }
                        .onEnded { _ in
                            TermHaptic.tap()
                        }
                )
            }
            .frame(height: height)

            Text(valueText)
                .termType(TermType.telemetryTight, color: theme.palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(minWidth: TermSpace.hit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(label) gain"))
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 24
            switch direction {
            case .increment:
                value = min(value + step, range.upperBound)
            case .decrement:
                value = max(value - step, range.lowerBound)
            @unknown default:
                break
            }
        }
    }

    private var normalized: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return ((value - range.lowerBound) / span).clampedUnit
    }

    private var valueText: String {
        String(format: "%+.1f", value)
    }

    private func cellHeight(for totalHeight: CGFloat) -> CGFloat {
        max((totalHeight - CGFloat(cells - 1) * 2) / CGFloat(cells), 1)
    }

    private func update(at y: CGFloat, height: CGFloat) {
        guard height > 0 else { return }
        let fraction = (1 - Double(y / height)).clampedUnit
        let span = range.upperBound - range.lowerBound
        value = min(max(range.lowerBound + fraction * span, range.lowerBound), range.upperBound)
        checkDetents(span: span)
    }

    private func checkDetents(span: Double) {
        for (index, detent) in detents.enumerated() {
            if abs(value - detent) <= span * 0.04, lastDetentIndex != index {
                lastDetentIndex = index
                TermHaptic.detent()
                return
            }
        }
    }
}

struct FaderSlider_Previews: PreviewProvider {
    static var previews: some View {
        TerminalPreview {
            FaderPreview()
        }
    }

    private struct FaderPreview: View {
        @State private var low = -6.0
        @State private var flat = 0.0
        @State private var high = 7.5

        var body: some View {
            HStack(alignment: .bottom, spacing: TermSpace.lg) {
                FaderSlider(value: $low, label: "60Hz")
                FaderSlider(value: $flat, label: "1kHz")
                FaderSlider(value: $high, label: "16kHz")
            }
        }
    }
}
