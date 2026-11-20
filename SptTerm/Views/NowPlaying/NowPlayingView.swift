import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var viewModel: NowPlayingViewModel
    @Binding var isExpanded: Bool
    var namespace: Namespace.ID

    @EnvironmentObject private var theme: TerminalTheme
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        let accent = viewModel.artwork.accent
        ZStack {
            theme.palette.background.ignoresSafeArea()
            RadialGradient(
                colors: [TermColorMath.withAlpha(accent, 0.22), .clear],
                center: .top,
                startRadius: 40,
                endRadius: 460
            )
            .ignoresSafeArea()
            .blendMode(.screen)
            ScanlineOverlay()

            VStack(spacing: 0) {
                // Top tactile grab bar for swipe-down / collapse
                pullDownBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: TermSpace.md) {
                        TerminalHeader(subtitle: "Now Playing")
                        NowPlayingMetadataPanel(viewModel: viewModel, namespace: namespace)
                        NowPlayingSpectrumPanel()
                        NowPlayingScrubberPanel(viewModel: viewModel)
                        NowPlayingTransportPanel(viewModel: viewModel)
                        NowPlayingLyricsPanel(viewModel: viewModel)
                        NowPlayingCommandLine(viewModel: viewModel)
                    }
                    .padding(.horizontal, TermSpace.gutter)
                    .padding(.top, TermSpace.xs)
                    .padding(.bottom, TermSpace.xl)
                }
            }
        }
        .offset(y: max(0, dragOffset))
        .simultaneousGesture(dismissGesture)
        .onDisappear {
            dragOffset = 0
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now Playing")
    }

    private var pullDownBar: some View {
        Button {
            TermHaptic.tap()
            withAnimation(TermMotion.expand) {
                isExpanded = false
            }
        } label: {
            VStack(spacing: 4) {
                // Tactile pill handle
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.palette.accent.opacity(0.7))
                    .frame(width: 44, height: 4)

                // ASCII terminal collapse prompt
                Text("[ ── ⌄ COLLAPSE ── ]")
                    .termType(TermType.labelSM, color: theme.palette.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, TermSpace.xs)
            .padding(.bottom, TermSpace.xs)
            .background(theme.palette.panelRaised.opacity(0.95))
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.palette.hairline).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TermPressStyle())
        .accessibilityLabel("Collapse to mini player")
        .highPriorityGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .local)
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    handleDragEnded(value)
                }
        )
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                // Only capture downward drags where vertical displacement is dominant
                if value.translation.height > 0 && value.translation.height > abs(value.translation.width) {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                handleDragEnded(value)
            }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let velocityY = value.predictedEndTranslation.height - value.translation.height
        let isPastThreshold = value.translation.height > 70 || velocityY > 200

        if isPastThreshold {
            TermHaptic.tap()
            withAnimation(TermMotion.expand) {
                isExpanded = false
            }
        } else {
            withAnimation(TermMotion.snap) {
                dragOffset = 0
            }
        }
    }
}

struct NowPlayingView_Previews: PreviewProvider {
    static var previews: some View {
        TerminalAppPreview {
            NowPlayingPreview()
        }
    }

    private struct NowPlayingPreview: View {
        @State private var isExpanded = true
        @Namespace private var namespace
        @StateObject private var viewModel = NowPlayingViewModel(
            player: PreviewServices().player,
            artworkProvider: PreviewServices().artwork
        )

        var body: some View {
            NowPlayingView(viewModel: viewModel, isExpanded: $isExpanded, namespace: namespace)
        }
    }
}
