import Foundation

/// Library surface over the Web API. Metadata only — playback lives in
/// `STRemotePlayerService`.
final class STWebLibraryService: LibraryServiceProtocol {
    private let api: STSpotifyWebAPI
    private var homeCache: (sections: [HomeSection], stamp: Date)?

    init(api: STSpotifyWebAPI) {
        self.api = api
    }

    func fetchHomeSections() async throws -> [HomeSection] {
        if let homeCache, Date().timeIntervalSince(homeCache.stamp) < 60 {
            return homeCache.sections
        }

        let saved = try await api.savedTracks()
        let recent = STSpotifyMapping.tracks(saved.items.map(\.track))

        var sections: [HomeSection] = [
            HomeSection(id: "hero", title: "NOW PLAYING", subtitle: "SESSION ACTIVE", kind: .hero),
            HomeSection(
                id: "recent",
                title: "CONTINUE",
                subtitle: "\(recent.count) TRACKS",
                kind: .recentlyPlayed,
                trackIDs: recent.map(\.id)
            ),
        ]

        let crates = try await fetchPlaylists()
        if !crates.isEmpty {
            sections.append(
                HomeSection(
                    id: "crates",
                    title: "CRATES",
                    subtitle: "\(crates.count) FOUND",
                    kind: .playlists,
                    playlistIDs: crates.map(\.id)
                )
            )
        }

        homeCache = (sections, Date())
        return sections
    }

    func fetchAlbums() async throws -> [Album] {
        STSpotifyMapping.albums(try await api.search("album").albums?.items)
    }

    func fetchAlbum(id: String) async throws -> Album? {
        let page = try await api.album(id)
        let tracks = STSpotifyMapping.tracks(page.tracks?.items)
        let base = STSpotifyMapping.album(page)
        return Album(
            id: base.id,
            title: base.title,
            artistID: base.artistID,
            artistName: base.artistName,
            year: base.year,
            genre: base.genre,
            trackIDs: tracks.map(\.id),
            formatLabel: base.formatLabel,
            summary: base.summary
        )
    }

    func fetchPlaylists() async throws -> [Playlist] {
        let saved = try await api.savedTracks()
        guard !saved.items.isEmpty else { return [] }
        return STSpotifyMapping.playlists(try await api.search("playlist").playlists?.items)
    }

    func fetchPlaylist(id: String) async throws -> Playlist? {
        let dto = try await api.playlist(id)
        let page = try await api.playlistTracks(id)
        let tracks = STSpotifyMapping.tracks(page.items?.compactMap(\.track))
        let base = STSpotifyMapping.playlist(dto)
        return Playlist(
            id: base.id,
            name: base.name,
            summary: base.summary,
            owner: base.owner,
            trackIDs: tracks.map(\.id),
            saves: base.saves,
            tag: base.tag,
            isLikedSongs: base.isLikedSongs
        )
    }

    func fetchArtists() async throws -> [Artist] {
        let saved = try await api.savedTracks()
        var seen = Set<String>()
        var out: [Artist] = []

        for track in saved.items.map(\STSavedTrackDTO.track) {
            for dto in track.artists ?? [] {
                let mapped = STSpotifyMapping.artist(dto)
                guard !mapped.id.isEmpty, seen.insert(mapped.id).inserted else { continue }
                out.append(mapped)
            }
        }
        return out
    }

    func fetchTracks(forAlbumID albumID: String) async throws -> [Track] {
        STSpotifyMapping.tracks(try await api.albumTracks(albumID).items)
    }

    func fetchTracks(forPlaylistID playlistID: String) async throws -> [Track] {
        let page = try await api.playlistTracks(playlistID)
        return STSpotifyMapping.tracks(page.items?.compactMap(\.track))
    }

    func fetchTracks(forArtistID artistID: String) async throws -> [Track] {
        STSpotifyMapping.tracks(try await api.search("artist:\(artistID)").tracks?.items)
    }

    func fetchTracks(ids: [String]) async throws -> [Track] {
        guard !ids.isEmpty else { return [] }
        return STSpotifyMapping.tracks(try await api.tracks(ids: ids))
    }

    func fetchLikedTracks() async throws -> [Track] {
        STSpotifyMapping.tracks(try await api.savedTracks().items.map(\.track))
    }

    func search(query: String) async throws -> SearchResults {
        guard !query.isEmpty else {
            return SearchResults(query: query, artists: [], albums: [], tracks: [], playlists: [])
        }
        return STSpotifyMapping.searchResults(try await api.search(query), query: query)
    }
}
