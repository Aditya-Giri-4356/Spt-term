import SwiftUI

/// Horizontal ASCII slider: `BASS BOOST   [+=====>------] +4.0dB`.
/// Used for bass/treble/width/compressor/limiter parameters.
struct TermSlider: View {
    @EnvironmentObject private var theme: TerminalTheme

    @Binding var value: Double
    var label: String
    var valueText: String
    var range: ClosedRange<Double> = 0...1
    var cells: Int = 14
    var detent: Double? = nil

    @State private var isAtDetent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: TermSpace.xs) {
                Text(label)
                    .termType(TermType.labelSM, color: theme.palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: TermSpace.xs)
                Text(valueText)
                    .termType(TermType.telemetryTight, color: theme.palette.cyan)
                    .lineLimit(1)
            }
            GeometryReader { proxy in
                ZStack {
                    ASCIIProgressBar(progress: normalized, width: cells, showsHead: true, fontSize: 11)
                        .padding(.horizontal, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            update(at: gesture.location.x, width: proxy.size.width)
                        }
                )
            }
            .frame(height: 28)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
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

    private func update(at x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let fraction = Double(x / width).clampedUnit
        let span = range.upperBound - range.lowerBound
        value = range.lowerBound + fraction * span
        if let detent {
            let near = abs(value - detent) <= span * 0.04
            if near, !isAtDetent {
                isAtDetent = true
                TermHaptic.detent()
            } else if !near {
                isAtDetent = false
            }
        }
    }
}

struct TermSlider_Previews: PreviewProvider {
    static var previews: some View {
        TerminalPreview {
            SliderPreview()
        }
    }

    private struct SliderPreview: View {
        @State private var bass = 4.0
        @State private var width = 0.6

        var body: some View {
            VStack(spacing: TermSpace.md) {
                TermSlider(
                    value: $bass,
                    label: "BASS BOOST",
                    valueText: TermFormat.decibels(bass),
                    range: -12...12,
                    detent: 0
                )
                TermSlider(value: $width, label: "STEREO WIDTH", valueText: TermFormat.percent(width, decimals: 0))
            }
        }
    }
}
