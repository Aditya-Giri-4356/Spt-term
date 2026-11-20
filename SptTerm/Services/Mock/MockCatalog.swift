import Foundation

enum MockCatalog {
    // MARK: Artists

    static let artists: [Artist] = [
        Artist(id: "ar1", name: "HOME", albumIDs: ["a1"], trackCount: 4, followers: 890_214, popularity: 88, isVerified: true),
        Artist(id: "ar2", name: "Kavinsky", albumIDs: ["a2"], trackCount: 3, followers: 1_240_933, popularity: 82, isVerified: true),
        Artist(id: "ar3", name: "Tycho", albumIDs: ["a3"], trackCount: 4, followers: 738_100, popularity: 79, isVerified: true),
        Artist(id: "ar4", name: "Daft Punk", albumIDs: ["a4"], trackCount: 3, followers: 8_210_455, popularity: 95, isVerified: true),
        Artist(id: "ar5", name: "Carpenter Brut", albumIDs: ["a5"], trackCount: 3, followers: 402_118, popularity: 76, isVerified: true),
        Artist(id: "ar6", name: "The Midnight", albumIDs: ["a6"], trackCount: 3, followers: 512_900, popularity: 81, isVerified: true),
        Artist(id: "ar7", name: "GUNSHIP", albumIDs: ["a7"], trackCount: 3, followers: 366_540, popularity: 74, isVerified: true),
        Artist(id: "ar8", name: "Aphex Twin", albumIDs: ["a8"], trackCount: 3, followers: 3_122_880, popularity: 89, isVerified: true)
    ]

    // MARK: Albums

    static let albums: [Album] = [
        Album(id: "a1", title: "Odyssey", artistID: "ar1", artistName: "HOME", year: 2014, genre: "Synthwave", trackIDs: ["t1", "t2", "t3", "t4"], formatLabel: "FLAC / 24-bit / 96kHz", summary: "Analog synth wanderlust recorded straight to tape."),
        Album(id: "a2", title: "OutRun", artistID: "ar2", artistName: "Kavinsky", year: 2013, genre: "Outrun", trackIDs: ["t5", "t6", "t7"], formatLabel: "FLAC / 16-bit / 44.1kHz", summary: "Midnight highway cinema in eleven movements."),
        Album(id: "a3", title: "Awake", artistID: "ar3", artistName: "Tycho", year: 2014, genre: "Ambient Electronic", trackIDs: ["t8", "t9", "t10", "t11"], formatLabel: "ALAC / 24-bit / 48kHz", summary: "Sunlit modular textures and patient drums."),
        Album(id: "a4", title: "Discovery", artistID: "ar4", artistName: "Daft Punk", year: 2001, genre: "French House", trackIDs: ["t12", "t13", "t14"], formatLabel: "FLAC / 16-bit / 44.1kHz", summary: "Filtered disco for the chrome generation."),
        Album(id: "a5", title: "Trilogy", artistID: "ar5", artistName: "Carpenter Brut", year: 2015, genre: "Darksynth", trackIDs: ["t15", "t16", "t17"], formatLabel: "FLAC / 24-bit / 96kHz", summary: "Saturating analog horror with a live drummer."),
        Album(id: "a6", title: "Endless Summer", artistID: "ar6", artistName: "The Midnight", year: 2016, genre: "Synthpop", trackIDs: ["t18", "t19", "t20"], formatLabel: "FLAC / 16-bit / 44.1kHz", summary: "Neon nostalgia with saxophone and tape hiss."),
        Album(id: "a7", title: "Dark All Day", artistID: "ar7", artistName: "GUNSHIP", year: 2018, genre: "Synthwave", trackIDs: ["t21", "t22", "t23"], formatLabel: "FLAC / 24-bit / 48kHz", summary: "Cyberpunk anthems engineered for night drives."),
        Album(id: "a8", title: "Selected Ambient Works 85-92", artistID: "ar8", artistName: "Aphex Twin", year: 1992, genre: "Ambient Techno", trackIDs: ["t24", "t25", "t26"], formatLabel: "WAV / 16-bit / 44.1kHz", summary: "Bedroom recordings that defined a genre."),
        Album(id: "a9", title: "Phosphor Sessions", artistID: "ar1", artistName: "HOME", year: 2021, genre: "Synthwave", trackIDs: ["t1", "t8"], formatLabel: "FLAC / 24-bit / 96kHz", summary: "Live terminal-session renditions of the catalog.")
    ]

    // MARK: Tracks

    static let tracks: [Track] = [
        t("t1", 1, "Resonance", "HOME", "ar1", "Odyssey", "a1", 2014, 212, "FLAC 44.1k"),
        t("t2", 2, "Decay", "HOME", "ar1", "Odyssey", "a1", 2014, 274, "FLAC 44.1k"),
        t("t3", 3, "Half Moon", "HOME", "ar1", "Odyssey", "a1", 2014, 268, "FLAC 44.1k"),
        t("t4", 4, "Native End", "HOME", "ar1", "Odyssey", "a1", 2014, 251, "FLAC 44.1k"),
        t("t5", 1, "Nightcall", "Kavinsky", "ar2", "OutRun", "a2", 2013, 258, "FLAC 44.1k"),
        t("t6", 2, "Protovision", "Kavinsky", "ar2", "OutRun", "a2", 2013, 214, "FLAC 44.1k"),
        t("t7", 3, "Roadgame", "Kavinsky", "ar2", "OutRun", "a2", 2013, 231, "FLAC 44.1k"),
        t("t8", 1, "Awake", "Tycho", "ar3", "Awake", "a3", 2014, 260, "ALAC 48k"),
        t("t9", 2, "Montana", "Tycho", "ar3", "Awake", "a3", 2014, 274, "ALAC 48k"),
        t("t10", 3, "L", "Tycho", "ar3", "Awake", "a3", 2014, 300, "ALAC 48k"),
        t("t11", 4, "Spectre", "Tycho", "ar3", "Awake", "a3", 2014, 222, "ALAC 48k"),
        t("t12", 1, "Veridis Quo", "Daft Punk", "ar4", "Discovery", "a4", 2001, 284, "FLAC 44.1k"),
        t("t13", 2, "Voyager", "Daft Punk", "ar4", "Discovery", "a4", 2001, 227, "FLAC 44.1k"),
        t("t14", 3, "Digital Love", "Daft Punk", "ar4", "Discovery", "a4", 2001, 301, "FLAC 44.1k"),
        t("t15", 1, "Turbo Killer", "Carpenter Brut", "ar5", "Trilogy", "a5", 2015, 234, "FLAC 96k"),
        t("t16", 2, "Roller Mobster", "Carpenter Brut", "ar5", "Trilogy", "a5", 2015, 219, "FLAC 96k"),
        t("t17", 3, "Division Ruine", "Carpenter Brut", "ar5", "Trilogy", "a5", 2015, 245, "FLAC 96k"),
        t("t18", 1, "Sunset", "The Midnight", "ar6", "Endless Summer", "a6", 2016, 273, "FLAC 44.1k"),
        t("t19", 2, "Days of Thunder", "The Midnight", "ar6", "Endless Summer", "a6", 2016, 283, "FLAC 44.1k"),
        t("t20", 3, "Vampires", "The Midnight", "ar6", "Endless Summer", "a6", 2016, 261, "FLAC 44.1k"),
        t("t21", 1, "Tech Noir", "GUNSHIP", "ar7", "Dark All Day", "a7", 2018, 305, "FLAC 48k"),
        t("t22", 2, "Dark All Day", "GUNSHIP", "ar7", "Dark All Day", "a7", 2018, 297, "FLAC 48k"),
        t("t23", 3, "When You Grow Up", "GUNSHIP", "ar7", "Dark All Day", "a7", 2018, 246, "FLAC 48k"),
        t("t24", 1, "Xtal", "Aphex Twin", "ar8", "Selected Ambient Works 85-92", "a8", 1992, 292, "WAV 44.1k"),
        t("t25", 2, "Tha", "Aphex Twin", "ar8", "Selected Ambient Works 85-92", "a8", 1992, 429, "WAV 44.1k"),
        t("t26", 3, "Ageispolis", "Aphex Twin", "ar8", "Selected Ambient Works 85-92", "a8", 1992, 340, "WAV 44.1k")
    ]

    // MARK: Playlists

    static let playlists: [Playlist] = [
        Playlist(id: "p1", name: "Synthwave & Cyberpunk", summary: "Neon dusk drives, analog arps and chrome skylines.", owner: "@term.fm", trackIDs: ["t5", "t15", "t21", "t18", "t6", "t16", "t22"], saves: 42_890, tag: "CURATED", isLikedSongs: false),
        Playlist(id: "p2", name: "Late Night Coding", summary: "High-BPM focus loops for long terminal sessions.", owner: "@root", trackIDs: ["t1", "t8", "t12", "t24", "t9", "t3"], saves: 11_402, tag: "USER_CURATED", isLikedSongs: false),
        Playlist(id: "p3", name: "Lo-Fi Terminal Beats", summary: "Tape-saturated downtempo for the small hours.", owner: "@term.fm", trackIDs: ["t25", "t13", "t10", "t26"], saves: 8_760, tag: "CURATED", isLikedSongs: false),
        Playlist(id: "p4", name: "Japanese City Pop 80s", summary: "Marina breezes, chorus guitars and FM bells.", owner: "@term.fm", trackIDs: ["t14", "t19", "t23", "t7"], saves: 6_318, tag: "CURATED", isLikedSongs: false),
        Playlist(id: "p5", name: "Liked Songs", summary: "Everything starred from the transport bar.", owner: "@root", trackIDs: ["t1", "t5", "t15", "t18", "t22", "t8", "t24", "t12"], saves: 1_248, tag: "SYSTEM", isLikedSongs: true)
    ]

    // MARK: Home

    static let homeSections: [HomeSection] = [
        HomeSection(id: "h1", title: "On Deck", subtitle: "Resonance — HOME", kind: .hero, albumIDs: ["a1"]),
        HomeSection(id: "h2", title: "Recently Played", subtitle: "4 buffered streams", kind: .recentlyPlayed, trackIDs: ["t1", "t5", "t15", "t22"]),
        HomeSection(id: "h3", title: "New In The Vault", subtitle: "synced 06:14 ago", kind: .newReleases, albumIDs: ["a7", "a5", "a6", "a3"]),
        HomeSection(id: "h4", title: "Mounted Playlists", subtitle: "4 directories", kind: .playlists, playlistIDs: ["p1", "p2", "p3", "p4"]),
        HomeSection(id: "h5", title: "Followed Artists", subtitle: "8 nodes", kind: .artists, artistIDs: ["ar1", "ar2", "ar5", "ar6"]),
        HomeSection(id: "h6", title: "System Log", subtitle: "daemon: 4 directories, 2841 files", kind: .systemLog, trackIDs: ["t24"])
    ]

    // MARK: Lyrics

    static let resonanceLyrics: [LyricsLine] = [
        LyricsLine(time: 0, text: "── resonance :: side A ──"),
        LyricsLine(time: 14, text: "Boot the sequence, watch the cursor glow"),
        LyricsLine(time: 27, text: "Low frequency pressure in the undertow"),
        LyricsLine(time: 41, text: "Every waveform a memory we overflow"),
        LyricsLine(time: 58, text: "Sampling the silence in the afterglow"),
        LyricsLine(time: 74, text: "Trace the signal through the copper wire"),
        LyricsLine(time: 91, text: "All our circuits humming higher and higher"),
        LyricsLine(time: 108, text: "Just echo lines across the digital sea"),
        LyricsLine(time: 130, text: "Neon reflections on the monitor glass"),
        LyricsLine(time: 144, text: "Synchronizing beats to the master clock"),
        LyricsLine(time: 151, text: "Fade into the phosphor green glow"),
        LyricsLine(time: 172, text: "── end of stream ──")
    ]

    // MARK: Lookup

    static let trackByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
    static let albumByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
    static let artistByID = Dictionary(uniqueKeysWithValues: artists.map { ($0.id, $0) })
    static let playlistByID = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, $0) })

    static func tracks(for ids: [String]) -> [Track] {
        ids.compactMap { trackByID[$0] }
    }

    // MARK: Builders

    private static func t(
        _ id: String,
        _ number: Int,
        _ title: String,
        _ artist: String,
        _ artistID: String,
        _ album: String,
        _ albumID: String,
        _ year: Int,
        _ duration: Double,
        _ format: String
    ) -> Track {
        Track(
            id: id,
            title: title,
            artistID: artistID,
            artistName: artist,
            albumID: albumID,
            albumTitle: album,
            year: year,
            trackNumber: number,
            duration: duration,
            formatLabel: format,
            bitrateLabel: format.contains("96k") ? "2840kbps" : "1411kbps",
            lyrics: id == "t1" ? resonanceLyrics : []
        )
    }
}
