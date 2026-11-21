import Foundation

enum STSpotifyMapping {
    static func uri(_ id: String) -> String {
        id.hasPrefix("spotify:") ? id : "spotify:track:\(id)"
    }

    static func id(fromURI uri: String) -> String {
        uri.split(separator: ":").last.map(String.init) ?? uri
    }

    static func year(_ releaseDate: String?) -> Int {
        guard let releaseDate else { return 0 }
        return Int(releaseDate.prefix(4)) ?? 0
    }

    static func artistLine(_ dtos: [STArtistDTO]?) -> String {
        guard let dtos, !dtos.isEmpty else { return "UNKNOWN ARTIST" }
        return dtos.map(\.name).joined(separator: ", ")
    }

    static func track(_ dto: STTrackDTO) -> Track? {
        guard let album = dto.album else { return nil }
        return Track(
            id: dto.id,
            title: dto.name,
            artistID: dto.artists?.first?.id ?? "",
            artistName: artistLine(dto.artists),
            albumID: album.id,
            albumTitle: album.name,
            year: year(album.release_date),
            trackNumber: dto.track_number ?? 0,
            duration: Double(dto.duration_ms) / 1000,
            formatLabel: "AAC",
            bitrateLabel: "320K",
            lyrics: []
        )
    }

    static func tracks(_ dtos: [STTrackDTO]?) -> [Track] {
        (dtos ?? []).compactMap(track)
    }

    static func album(_ dto: STAlbumDTO) -> Album {
        Album(
            id: dto.id,
            title: dto.name,
            artistID: dto.artists?.first?.id ?? "",
            artistName: artistLine(dto.artists),
            year: year(dto.release_date),
            genre: "UNKNOWN",
            trackIDs: [],
            formatLabel: "AAC",
            summary: "\(artistLine(dto.artists)) • \(year(dto.release_date))"
        )
    }

    static func albums(_ dtos: [STAlbumDTO]?) -> [Album] {
        (dtos ?? []).map(album)
    }

    static func artist(_ dto: STArtistDTO) -> Artist {
        Artist(
            id: dto.id ?? "",
            name: dto.name,
            albumIDs: [],
            trackCount: 0,
            followers: 0,
            popularity: 0,
            isVerified: false
        )
    }

    static func artists(_ dtos: [STArtistDTO]?) -> [Artist] {
        (dtos ?? []).map(artist)
    }

    static func playlist(_ dto: STPlaylistDTO) -> Playlist {
        Playlist(
            id: dto.id,
            name: dto.name,
            summary: "\(dto.tracks?.total ?? 0) TRACKS",
            owner: dto.owner?.display_name ?? "UNKNOWN",
            trackIDs: [],
            saves: dto.tracks?.total ?? 0,
            tag: "IMPORTED",
            isLikedSongs: false
        )
    }

    static func playlists(_ dtos: [STPlaylistDTO]?) -> [Playlist] {
        (dtos ?? []).map(playlist)
    }

    static func searchResults(_ dto: STSearchDTO, query: String) -> SearchResults {
        SearchResults(
            query: query,
            artists: artists(dto.artists?.items),
            albums: albums(dto.albums?.items),
            tracks: tracks(dto.tracks?.items),
            playlists: playlists(dto.playlists?.items)
        )
    }
}
