import SwiftUI

/// Placeholder views for tabs that are not yet implemented.
/// - Tag: [3:EXEC] and [4:THEME] tabs.
enum TemporaryPlaceholders {
    /// Placeholder for the Executive Controls tab ([3:EXEC]).
    static func execPlaceholder() -> some View {
        ExecPlaceholderView()
    }

    /// Placeholder for the Settings tab ([4:THEME]).
    static func themePlaceholder() -> some View {
        ThemePlaceholderView()
    }
}

struct ExecPlaceholderView: View {
    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            ASCIIPanel(title: "AUDIO TUNING", trailing: "pending") {
                Text("EXECUTIVE CONTROLS — PENDING IMPLEMENTATION")
                    .termType(TermType.bodySM, color: theme.palette.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(TermSpace.md)
        }
        .accessibilityLabel("Executive controls placeholder")
    }
}

struct ThemePlaceholderView: View {
    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            ASCIIPanel(title: "SETTINGS", trailing: "pending") {
                Text("SETTINGS — PENDING IMPLEMENTATION")
                    .termType(TermType.bodySM, color: theme.palette.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(TermSpace.md)
        }
        .accessibilityLabel("Settings placeholder")
    }
}

struct TemporaryPlaceholders_Previews: PreviewProvider {
    static var previews: some View {
        TerminalAppPreview {
            VStack(spacing: TermSpace.lg) {
                ExecPlaceholderView()
                ThemePlaceholderView()
            }
        }
    }
}
