import SwiftUI

/// Owns the live environment and holds the shell behind authorization.
/// RootView itself is untouched so previews keep using mocks.
struct STRootGate: View {
    @EnvironmentObject private var env: ServiceEnvironment
    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        Group {
            if env.isAuthorized {
                RootView()
            } else {
                signedOut
            }
        }
        .environment(\.serviceContainer, env.legacyContainer)
        .environment(\.libraryService, env.library)
        .environment(\.playerService, env.player)
        .environment(\.audioEffectsService, env.audioTweaks)
        .environment(\.artworkProvider, env.artwork)
        .task { env.start() }
        .onOpenURL { url in _ = env.handle(url: url) }
    }

    private var signedOut: some View {
        VStack(spacing: 16) {
            Text("NO SESSION")
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(theme.palette.textPrimary.opacity(0.6))

            Text("SIGN IN TO CONTINUE")
                .font(.system(.body, design: .monospaced).weight(.bold))

            Button {
                Task { try? await env.authorize() }
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
