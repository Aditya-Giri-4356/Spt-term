import SwiftUI

/// Chunky block bars as in the FFT panel. Values are 0...1.
struct SpectrumBars: View {
    @EnvironmentObject private var theme: TerminalTheme

    let values: [Double]
    var barSpacing: CGFloat = 3
    var cornerRadius: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let count = max(values.count, 1)
            let width = max((proxy.size.width - barSpacing * CGFloat(count - 1)) / CGFloat(count), 1)
            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    let height = max(2, proxy.size.height * CGFloat(value.clampedUnit))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(theme.palette.accent)
                        .frame(width: width, height: height)
                        .phosphorGlow(theme.palette.accent, radius: 6, intensity: 0.6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .animation(TermMotion.control, value: values)
        .accessibilityHidden(true)
    }
}

/// Fake analyser for Phase 1: deterministic pseudo-random walk so previews
/// and the prototype feel alive without any audio processing.
struct LiveSpectrumBars: View {
    var columns: Int = 9
    var period: TimeInterval = 0.1

    var body: some View {
        TimelineView(.periodic(from: .now, by: period)) { context in
            SpectrumBars(
                values: Self.values(
                    at: context.date.timeIntervalSinceReferenceDate,
                    columns: columns
                )
            )
        }
    }

    static func values(at time: TimeInterval, columns: Int) -> [Double] {
        guard columns > 0 else { return [] }
        return (0..<columns).map { index in
            let position = Double(index) / Double(max(columns - 1, 1))
            let envelope = 1.0 - 0.42 * position
            let wave = 0.5 + 0.5 * sin(time * 2.1 + Double(index) * 0.9)
            let jitter = pseudoRandom(time * 3.7 + Double(index) * 12.9898)
            let blended = 0.55 * wave + 0.45 * jitter
            return (0.12 + blended * envelope * 0.88).clampedUnit
        }
    }

    private static func pseudoRandom(_ seed: Double) -> Double {
        let value = sin(seed) * 43758.5453
        return value - value.rounded(.down)
    }
}

struct SpectrumBars_Previews: PreviewProvider {
    static var previews: some View {
        TerminalPreview {
            VStack(spacing: TermSpace.md) {
                LiveSpectrumBars(columns: 9)
                    .frame(height: 80)
                    .padding(TermSpace.sm)
                    .background(Color(termHex: "#050805"))
                SpectrumBars(values: [0.9, 0.6, 0.75, 0.35, 0.82, 0.5, 0.68, 0.3, 0.2])
                    .frame(height: 80)
                    .padding(TermSpace.sm)
                    .background(Color(termHex: "#050805"))
            }
        }
    }
}
