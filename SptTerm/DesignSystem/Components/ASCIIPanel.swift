import SwiftUI

enum ASCIIFrameStyle {
    case single
    case double
}

/// The core enclosure of the app: a bordered terminal panel with an inlaid
/// title row. Borders are drawn as strokes (crisper under Dynamic Type than
/// literal box-drawing characters) while titles keep the TUI glyph style.
struct ASCIIPanel<Content: View>: View {
    @EnvironmentObject private var theme: TerminalTheme

    private let title: String?
    private let trailing: String?
    private let frameStyle: ASCIIFrameStyle
    private let contentPadding: CGFloat
    private let content: Content

    init(
        title: String? = nil,
        trailing: String? = nil,
        frameStyle: ASCIIFrameStyle = .single,
        contentPadding: CGFloat = TermSpace.sm,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = trailing
        self.frameStyle = frameStyle
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || trailing != nil {
                header
                Rectangle()
                    .fill(theme.palette.hairline)
                    .frame(height: 1)
            }
            content
                .padding(contentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.palette.panel)
        .overlay(
            Rectangle()
                .strokeBorder(theme.palette.accentDeep, lineWidth: frameStyle == .double ? 2 : 1)
        )
        .overlay {
            if frameStyle == .double {
                Rectangle()
                    .strokeBorder(TermColorMath.withAlpha(theme.palette.accentDim, 0.4), lineWidth: 1)
                    .padding(3)
            }
        }
        .clipShape(Rectangle())
    }

    private var header: some View {
        HStack(spacing: TermSpace.xs) {
            if let title {
                Text("┌── [\(title.uppercased())]")
                    .termType(TermType.labelSM, color: theme.palette.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: TermSpace.xs)
            if let trailing {
                Text(trailing)
                    .termType(TermType.labelSM, color: theme.palette.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, TermSpace.sm)
        .padding(.vertical, 6)
    }
}

struct ASCIIPanel_Previews: PreviewProvider {
    static var previews: some View {
        TerminalPreview {
            VStack(spacing: TermSpace.sm) {
                ASCIIPanel(title: "Now Playing :: PID 4092", trailing: "[v2.4-stable]") {
                    Text("Track: Cybernetic Drift")
                        .termType(TermType.bodyMD, color: .white)
                }
                ASCIIPanel(title: "Mounted Playlist", trailing: "RO:TRUE", frameStyle: .double) {
                    Text("└── [END DIRECTORY TREE]")
                        .termType(TermType.telemetry, color: .green)
                }
            }
        }
    }
}
