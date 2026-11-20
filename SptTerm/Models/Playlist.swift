import Foundation

struct Playlist: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let summary: String
    let owner: String
    let trackIDs: [String]
    let saves: Int
    let tag: String
    let isLikedSongs: Bool

    var savesLabel: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: saves)) ?? "\(saves)"
    }
}

struct HomeSection: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case hero
        case recentlyPlayed
        case newReleases
        case playlists
        case artists
        case systemLog
    }

    let id: String
    let title: String
    var subtitle: String?
    let kind: Kind
    var trackIDs: [String] = []
    var albumIDs: [String] = []
    var playlistIDs: [String] = []
    var artistIDs: [String] = []
}

struct SearchResults: Equatable {
    let query: String
    let artists: [Artist]
    let albums: [Album]
    let tracks: [Track]
    let playlists: [Playlist]

    var isEmpty: Bool {
        artists.isEmpty && albums.isEmpty && tracks.isEmpty && playlists.isEmpty
    }

    var total: Int {
        artists.count + albums.count + tracks.count + playlists.count
    }
}
