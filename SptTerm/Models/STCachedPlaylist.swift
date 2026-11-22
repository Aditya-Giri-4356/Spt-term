import Foundation

/// Represents a playlist discovered from Spotify's on-screen Library.
public struct STCachedPlaylist: Codable, Identifiable, Equatable {
    public var id: String { label }
    public let name: String
    public let label: String
    public let firstSeen: Date

    public init(name: String, label: String, firstSeen: Date = Date()) {
        self.name = name
        self.label = label
        self.firstSeen = firstSeen
    }
}
