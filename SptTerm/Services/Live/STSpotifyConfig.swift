import Foundation

/// Compile-time Spotify configuration. Register an app at
/// developer.spotify.com with `redirectURI` as a redirect, then paste the
/// client ID in.
enum STSpotifyConfig {
    static let clientID = "YOUR_CLIENT_ID"
    static let redirectURI = "sptterm://auth"

    static let apiBase = URL(string: "https://api.spotify.com/v1")!
    static let accountsBase = URL(string: "https://accounts.spotify.com")!

    static let scopes = [
        "user-library-read",
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-read-private",
        "app-remote-control",
        "streaming",
    ]

    static var scopeString: String { scopes.joined(separator: " ") }
    static var isConfigured: Bool { clientID != "YOUR_CLIENT_ID" }
}
