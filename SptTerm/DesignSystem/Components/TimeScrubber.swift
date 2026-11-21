import SwiftUI

/// Draggable terminal scrubber with a live timecode readout and 10% detents.
struct TimeScrubber: View {
    @EnvironmentObject private var theme: TerminalTheme

    @Binding var progress: Double
    var duration: Double
    var onSeek: (Double) -> Void = { _ in }
    var onScrubbingChanged: (Bool) -> Void = { _ in }
    var isReadOnly: Bool = false

    @State private var isScrubbing = false
    @State private var dragProgress: Double?
    @State private var lastDetent = -1

    private var activeProgress: Double {
        dragProgress ?? progress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TermSpace.xs) {
            header
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: TermRadius.card)
                        .fill(theme.palette.panelRaised)
                    ASCIIProgressBar(progress: activeProgress, width: 34)
                        .padding(.horizontal, TermSpace.sm)
                }
                .contentShape(Rectangle())
                .gesture(
                    isReadOnly ? nil : DragGesture(minimumDistance: 0)
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
                            let finalValue = dragProgress ?? progress
                            dragProgress = nil
                            progress = finalValue
                            onSeek(finalValue)
                        }
                )
            }
            .frame(height: TermSpace.hit)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seek position")
        .accessibilityValue("\(TermFormat.duration(activeProgress * duration)) of \(TermFormat.duration(duration))")
        .accessibilityAdjustableAction { direction in
            guard !isReadOnly else { return }
            let step = 0.05
            var next = activeProgress
            switch direction {
            case .increment:
                next = (next + step).clampedUnit
            case .decrement:
                next = (next - step).clampedUnit
            @unknown default:
                break
            }
            progress = next
            onSeek(next)
        }
    }

    private var header: some View {
        HStack(spacing: TermSpace.xs) {
            if isReadOnly {
                Text("[SEEK N/A]")
                    .termType(TermType.telemetryTight, color: theme.palette.amber)
            }
            Text("SEEK_CURSOR :: POS: \(TermFormat.percent(activeProgress.clampedUnit))")
                .termType(TermType.telemetryTight, color: theme.palette.accentDim)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: TermSpace.xs)
            timecode
        }
    }

    private var timecode: some View {
        HStack(spacing: 3) {
            Text(TermFormat.duration(activeProgress * duration))
                .termType(TermType.telemetryTight, color: theme.palette.accent)
            Text("/")
                .termType(TermType.telemetryTight, color: theme.palette.textMuted)
            Text(TermFormat.duration(duration))
                .termType(TermType.telemetryTight, color: theme.palette.textSecondary)
            Text("(\(TermFormat.signedDuration(activeProgress * duration - duration)))")
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
        dragProgress = newValue
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
