import SwiftUI

@main
struct SptTermApp: App {
    @StateObject private var theme = TerminalTheme()

    var body: some Scene {
        WindowGroup {
            STRootGate()
                .environmentObject(theme)
        }
    }
}
