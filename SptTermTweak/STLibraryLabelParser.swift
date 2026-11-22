import Foundation

/// Classification of a Spotify library row label.
public enum STLibraryLabelKind: Equatable {
    case playlist(name: String)
    case otherKind(String)
    case noParse
}

/// Pure functions for parsing and classifying Spotify on-screen labels.
public final class STLibraryLabelParser {
    private static let otherKinds = [
        "Album", "Artist", "Podcast", "Show", "Episode", "Audiobook"
    ]

    /// Classifies an on-screen Spotify library row label.
    /// Finds the FIRST occurrence of ". Playlist" followed by "." or end of string.
    /// Name is text before it, trimmed. Rows with other known kind markers are classified as otherKind.
    public static func classifyLibraryLabel(_ label: String) -> STLibraryLabelKind {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .noParse }

        // 1. Check for ". Playlist" marker
        if let name = extractName(beforeMarker: "Playlist", in: trimmed) {
            return .playlist(name: name)
        }

        // 2. Check for other known kind markers (skipped kind)
        for kind in otherKinds {
            if extractName(beforeMarker: kind, in: trimmed) != nil {
                return .otherKind(kind)
            }
        }

        return .noParse
    }

    /// Pure function returning parsed name and "Playlist" kind if the label is a valid playlist row.
    public static func parseLibraryLabel(_ label: String) -> (name: String, kind: String)? {
        if case .playlist(let name) = classifyLibraryLabel(label) {
            return (name, "Playlist")
        }
        return nil
    }

    /// Pure function evaluating whether an element matches opened-playlist track row requirements:
    /// - Ancestor contains "ListUXPlatform" or "PlaylistImpl"
    /// - No ancestor contains "NowPlaying" or "YourLibrary"
    /// - Label length between 2 and 200 characters
    /// - Frame width at least 200pt
    public static func isOpenedPlaylistTrackRow(
        label: String,
        frame: CGRect,
        ancestors: [String]
    ) -> Bool {
        guard label.count >= 2 && label.count <= 200 else { return false }
        guard frame.width >= 200.0 else { return false }
        if ancestors.contains(where: { $0.contains("NowPlaying") || $0.contains("YourLibrary") }) {
            return false
        }
        return ancestors.contains(where: { $0.contains("ListUXPlatform") || $0.contains("PlaylistImpl") })
    }

    private static func extractName(beforeMarker kind: String, in text: String) -> String? {
        let marker = ". " + kind
        var searchStart = text.startIndex

        while searchStart < text.endIndex, let range = text.range(of: marker, range: searchStart..<text.endIndex) {
            let afterMarker = range.upperBound
            // Marker must be followed by "." or be at the end of the string
            if afterMarker == text.endIndex || text[afterMarker] == "." {
                let name = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    return name
                }
            }
            searchStart = text.index(after: range.lowerBound)
        }
        return nil
    }
}
