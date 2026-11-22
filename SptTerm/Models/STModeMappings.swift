import Foundation
import MediaPlayer

/// Pure mapping and helper functions for Repeat and Shuffle modes.
/// Shared across targets and tested in unit tests without UI dependencies.
enum STModeMappings {
    // MARK: - Repeat Cycle

    /// Standard SptTerm repeat cycle: off -> all -> one -> off.
    static func nextRepeatMode(after current: RepeatMode) -> RepeatMode {
        switch current {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    // MARK: - MPRepeatType <-> RepeatMode

    static func mapRepeatType(_ type: MPRepeatType) -> RepeatMode {
        switch type {
        case .off:
            return .off
        case .one:
            return .one
        case .all:
            return .all
        @unknown default:
            return .off
        }
    }

    static func mapToMPRepeatType(_ mode: RepeatMode) -> MPRepeatType {
        switch mode {
        case .off:
            return .off
        case .one:
            return .one
        case .all:
            return .all
        }
    }

    // MARK: - MPShuffleType <-> Bool

    static func mapShuffleType(_ type: MPShuffleType) -> Bool {
        switch type {
        case .off:
            return false
        case .items, .collections:
            return true
        @unknown default:
            return false
        }
    }

    // MARK: - Value Encoding for Strategy Candidates

    /// Encodes target RepeatMode into candidate integer payload.
    /// R1/R2 use off=0, one=1, all=2.
    /// R3/R4 use off=1, one=2, all=3.
    static func valueForRepeatStrategy(id: String, mode: RepeatMode) -> Int? {
        let upper = id.uppercased()
        switch upper {
        case "R1", "R2":
            switch mode {
            case .off: return 0
            case .one: return 1
            case .all: return 2
            }
        case "R3", "R4":
            switch mode {
            case .off: return 1
            case .one: return 2
            case .all: return 3
            }
        default:
            return nil
        }
    }

    /// Encodes target Shuffle Bool into candidate integer payload.
    /// S1/S2 use off=0, on=1.
    /// S3/S4 use off=1, on=2.
    static func valueForShuffleStrategy(id: String, enabled: Bool) -> Int? {
        let upper = id.uppercased()
        switch upper {
        case "S1", "S2":
            return enabled ? 1 : 0
        case "S3", "S4":
            return enabled ? 2 : 1
        default:
            return nil
        }
    }

    // MARK: - Tolerant UI Hook Text Parsers

    /// Parses accessibility label or text from Spotify UI into a RepeatMode.
    static func parseRepeatText(_ text: String) -> RepeatMode? {
        let lower = text.lowercased()
        if lower.contains("repeat one") || lower.contains("repeat track") || lower.contains("one") {
            return .one
        }
        if lower.contains("repeat all") || lower.contains("repeat context") || lower.contains("all") {
            return .all
        }
        if lower.contains("disable repeat") || lower.contains("repeat off") || lower.contains("don't repeat") {
            return .off
        }
        if lower.contains("repeat") && (lower.contains("off") || lower.contains("disabled")) {
            return .off
        }
        if lower.contains("repeat") && (lower.contains("on") || lower.contains("enabled")) {
            return .all
        }
        return nil
    }

    /// Parses accessibility label or text from Spotify UI into a Shuffle Bool.
    static func parseShuffleText(_ text: String) -> Bool? {
        let lower = text.lowercased()
        if lower.contains("disable shuffle") || lower.contains("shuffle off") || lower.contains("don't shuffle") {
            return false
        }
        if lower.contains("enable shuffle") || lower.contains("shuffle on") {
            return true
        }
        if lower.contains("shuffle") && (lower.contains("off") || lower.contains("disabled")) {
            return false
        }
        if lower.contains("shuffle") && (lower.contains("on") || lower.contains("enabled")) {
            return true
        }
        return nil
    }
}
