import SwiftUI

/// Wraps a view with a theme, background and screen padding for previews.
struct TerminalPreview<Content: View>: View {
    @StateObject private var theme: TerminalTheme
    private let content: Content

    init(themeID: String = ThemeCatalog.defaultID, @ViewBuilder content: () -> Content) {
        _theme = StateObject(wrappedValue: TerminalTheme.preview(themeID: themeID))
        self.content = content()
    }

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            content
                .padding(TermSpace.md)
                .foregroundColor(theme.palette.textPrimary)
        }
        .environmentObject(theme)
        .preferredColorScheme(theme.palette.isLight ? .light : .dark)
    }
}

/// Wraps a full screen preview without the extra padding.
struct TerminalScreenPreview<Content: View>: View {
    @StateObject private var theme: TerminalTheme
    private let content: Content

    init(themeID: String = ThemeCatalog.defaultID, @ViewBuilder content: () -> Content) {
        _theme = StateObject(wrappedValue: TerminalTheme.preview(themeID: themeID))
        self.content = content()
    }

    var body: some View {
        content
            .background(theme.palette.background.ignoresSafeArea())
            .foregroundColor(theme.palette.textPrimary)
            .environmentObject(theme)
            .preferredColorScheme(theme.palette.isLight ? .light : .dark)
    }
}
