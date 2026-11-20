import Foundation

/// Central navigation destinations used across tabs.
public enum AppRoute: Hashable {
    case album(id: String)
    case playlist(id: String)
    case artist(id: String)
    case search
}
