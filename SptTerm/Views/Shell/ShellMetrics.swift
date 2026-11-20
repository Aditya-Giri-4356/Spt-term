import SwiftUI

struct ShellMetricsKey: EnvironmentKey {
    static var defaultValue: ShellMetrics = ShellMetrics()
}

struct ShellMetrics {
    var miniPlayerHeight: CGFloat = 60
    var tabBarHeight: CGFloat = 64
    var contentBottomInset: CGFloat

    init(theme: TerminalTheme? = nil) {
        miniPlayerHeight = 60
        tabBarHeight = 64
        contentBottomInset = miniPlayerHeight + tabBarHeight + 16
    }
}

extension EnvironmentValues {
    var shellMetrics: ShellMetrics {
        get { self[ShellMetricsKey.self] }
        set { self[ShellMetricsKey.self] = newValue }
    }
}
