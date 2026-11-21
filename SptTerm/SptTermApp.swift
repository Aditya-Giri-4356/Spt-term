import SwiftUI

@main
struct SptTermApp: App {
    @StateObject private var theme = TerminalTheme()
    @StateObject private var env = ServiceEnvironment.forApp()

    var body: some Scene {
        WindowGroup {
            STRootGate()
                .environmentObject(theme)
                .environmentObject(env)
        }
    }
}
