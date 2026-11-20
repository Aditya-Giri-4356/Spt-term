import SwiftUI

/// Draggable terminal scrubber with a live timecode readout and 10% detents.
struct TimeScrubber: View {
    @EnvironmentObject private var theme: TerminalTheme

    @Binding var progress: Double
    var duration: Double
    var onSeek: (Double) -> Void = { _ in }
    var onScrubbingChanged: (Bool) -> Void = { _ in }

    @State private var isScrubbing = false
    @State private var lastDetent = -1

    var body: some View {
        VStack(alignment: .leading, spacing: TermSpace.xs) {
            header
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: TermRadius.card)
                        .fill(theme.palette.panelRaised)
                    ASCIIProgressBar(progress: progress, width: 34)
                        .padding(.horizontal, TermSpace.sm)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isScrubbing {
                                isScrubbing = true
                                onScrubbingChanged(true)
                            }
                            update(at: value.location.x, width: proxy.size.width)
                        }
                        .onEnded { _ in
                            isScrubbing = false
                            onScrubbingChanged(false)
                            onSeek(progress)
                        }
                )
            }
            .frame(height: TermSpace.hit)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seek position")
        .accessibilityValue("\(TermFormat.duration(progress * duration)) of \(TermFormat.duration(duration))")
        .accessibilityAdjustableAction { direction in
            let step = 0.05
            switch direction {
            case .increment:
                progress = (progress + step).clampedUnit
            case .decrement:
                progress = (progress - step).clampedUnit
            @unknown default:
                break
            }
            onSeek(progress)
        }
    }

    private var header: some View {
        HStack(spacing: TermSpace.xs) {
            Text("SEEK_CURSOR :: POS: \(TermFormat.percent(progress.clampedUnit))")
                .termType(TermType.telemetryTight, color: theme.palette.accentDim)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: TermSpace.xs)
            timecode
        }
    }

    private var timecode: some View {
        HStack(spacing: 3) {
            Text(TermFormat.duration(progress * duration))
                .termType(TermType.telemetryTight, color: theme.palette.accent)
            Text("/")
                .termType(TermType.telemetryTight, color: theme.palette.textMuted)
            Text(TermFormat.duration(duration))
                .termType(TermType.telemetryTight, color: theme.palette.textSecondary)
            Text("(\(TermFormat.signedDuration(progress * duration - duration)))")
                .termType(TermType.telemetryTight, color: theme.palette.cyan)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
    }

    private func update(at x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let newValue = Double(x / width).clampedUnit
        progress = newValue
        let detent = Int(newValue * 10)
        if detent != lastDetent {
            lastDetent = detent
            TermHaptic.detent()
        }
    }
}

struct TimeScrubber_Previews: PreviewProvider {
    static var previews: some View {
        TerminalPreview {
            ScrubberPreview()
        }
    }

    private struct ScrubberPreview: View {
        @State private var progress = 0.65

        var body: some View {
            TimeScrubber(progress: $progress, duration: 212)
        }
    }
}
