import Foundation

enum RepeatMode: String, Codable, CaseIterable, Hashable {
    case off
    case all
    case one

    var label: String {
        switch self {
        case .off: return "OFF"
        case .all: return "ALL"
        case .one: return "ONE"
        }
    }
}

struct PlayerState: Equatable {
    var currentTrack: Track?
    var queue: [Track]
    var isPlaying: Bool
    var progress: Double
    var duration: Double
    var repeatMode: RepeatMode
    var isShuffled: Bool
    var volume: Double
    var likedTrackIDs: Set<String>
    var isSeekSupported: Bool = true
    var isRepeatSupported: Bool = true
    var isRepeatUnverified: Bool = false

    var isCurrentTrackLiked: Bool {
        guard let currentTrack else { return false }
        return likedTrackIDs.contains(currentTrack.id)
    }

    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return (progress / duration).clampedUnit
    }

    var remainingLabel: String {
        TermFormat.signedDuration(progress - duration)
    }

    var playbackLabel: String {
        isPlaying ? "PLAYING" : "PAUSED"
    }

    static let empty = PlayerState(
        currentTrack: nil,
        queue: [],
        isPlaying: false,
        progress: 0,
        duration: 0,
        repeatMode: .off,
        isShuffled: false,
        volume: 0.8,
        likedTrackIDs: [],
        isSeekSupported: true,
        isRepeatSupported: true,
        isRepeatUnverified: false
    )
}
