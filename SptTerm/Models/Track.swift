import Foundation

struct LyricsLine: Identifiable, Codable, Hashable {
    let time: Double
    let text: String

    var id: Double { time }

    var timeLabel: String { TermFormat.duration(time) }
}

struct Track: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let artistID: String
    let artistName: String
    let albumID: String
    let albumTitle: String
    let year: Int
    let trackNumber: Int
    let duration: Double
    let formatLabel: String
    let bitrateLabel: String
    var lyrics: [LyricsLine]
    var artworkMatrixRows: [String]? = nil
    var artworkAccentHex: String? = nil

    init(
        id: String,
        title: String,
        artistID: String,
        artistName: String,
        albumID: String,
        albumTitle: String,
        year: Int,
        trackNumber: Int,
        duration: Double,
        formatLabel: String,
        bitrateLabel: String,
        lyrics: [LyricsLine],
        artworkMatrixRows: [String]? = nil,
        artworkAccentHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artistID = artistID
        self.artistName = artistName
        self.albumID = albumID
        self.albumTitle = albumTitle
        self.year = year
        self.trackNumber = trackNumber
        self.duration = duration
        self.formatLabel = formatLabel
        self.bitrateLabel = bitrateLabel
        self.lyrics = lyrics
        self.artworkMatrixRows = artworkMatrixRows
        self.artworkAccentHex = artworkAccentHex
    }

    var durationLabel: String { TermFormat.duration(duration) }

    var subtitleLabel: String {
        "\(albumTitle) (\(year)) • \(formatLabel)"
    }

    /// `01  03:42  Resonance.flac`
    var treeLine: String {
        let index = String(format: "%02d", trackNumber)
        return "\(index)  \(durationLabel)  \(title)"
    }

    /// Loose matching used by the mock search service.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let needle = query.lowercased()
        return title.lowercased().contains(needle)
            || artistName.lowercased().contains(needle)
            || albumTitle.lowercased().contains(needle)
    }
}
