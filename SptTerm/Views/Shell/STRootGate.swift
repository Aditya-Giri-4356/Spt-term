import SwiftUI

/// Owns the live container and holds the shell behind authorization.
/// RootView itself is untouched so previews keep using mocks.
struct STRootGate: View {
    @StateObject private var container = STServiceContainer()
    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        Group {
            if container.isAuthorized {
                RootView()
            } else {
                signedOut
            }
        }
        .environment(\.libraryService, container.library)
        .environment(\.playerService, container.player)
        .environment(\.audioEffectsService, container.effects)
        .environment(\.artworkProvider, container.artwork)
        .task { container.start() }
        .onOpenURL { url in container.auth.handle(url: url) }
    }

    private var signedOut: some View {
        VStack(spacing: 16) {
            Text("NO SESSION")
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(theme.palette.textPrimary.opacity(0.6))

            Text("SIGN IN TO CONTINUE")
                .font(.system(.body, design: .monospaced).weight(.bold))

            Button {
                Task { try? await container.auth.authorize() }
            } label: {
                Text("[ CONNECT ]").font(.system(.body, design: .monospaced))
            }
            .padding(.top, 8)
        }
        .foregroundColor(theme.palette.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.background.ignoresSafeArea())
    }
}
