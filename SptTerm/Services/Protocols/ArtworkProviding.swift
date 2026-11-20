import SwiftUI

struct TrackArtwork: Equatable {
    let matrix: ASCIIGlyphMatrix
    let accent: Color
}

/// Album art is rendered as a deterministic glyph grid in this design.
/// Swapping in real cover images later only requires a new conformance.
protocol ArtworkProviding {
    func artwork(seed: String, columns: Int) -> TrackArtwork
}

extension ArtworkProviding {
    func artwork(for track: Track, columns: Int = 16) -> TrackArtwork {
        artwork(seed: "\(track.id)|\(track.albumTitle)|\(track.title)", columns: columns)
    }

    func artwork(for album: Album, columns: Int = 16) -> TrackArtwork {
        artwork(seed: "\(album.id)|\(album.title)", columns: columns)
    }

    func artwork(for playlist: Playlist, columns: Int = 16) -> TrackArtwork {
        artwork(seed: "\(playlist.id)|\(playlist.name)", columns: columns)
    }
}
