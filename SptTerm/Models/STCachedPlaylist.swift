import Foundation

/// Represents a playlist discovered from Spotify's on-screen Library.
public struct STCachedPlaylist: Codable, Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public var lastLabel: String
    public let firstSeen: Date

    public init(name: String, lastLabel: String, firstSeen: Date = Date()) {
        self.name = name
        self.lastLabel = lastLabel
        self.firstSeen = firstSeen
    }

    /// Accessor for on-screen matching
    public var label: String { lastLabel }
}
