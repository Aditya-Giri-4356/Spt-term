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

    /// Result of parsing shuffle text, indicating whether Smart/AI shuffle was detected.
    struct ShuffleParseResult: Equatable {
        let isShuffled: Bool
        let isSmart: Bool
    }

    /// Parses accessibility label or text from Spotify UI into a RepeatMode.
    /// Check negatives first:
    /// - containing "no repeat", "not", "off", "disabled" -> .off
    /// - containing "one", "track", "song", "1" -> .one
    /// - containing "all", "playlist", "context", "repeat" (after negative check) -> .all
    /// - Unknown strings: nil (state unchanged, raw string logged by caller)
    static func parseRepeatText(_ text: String) -> RepeatMode? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return nil }

        // 1. Negatives first
        if lower.contains("no repeat") || lower.contains("not") || lower.contains("off") || lower.contains("disabled") {
            return .off
        }
        // 2. Repeat one
        if lower.contains("one") || lower.contains("track") || lower.contains("song") || lower.contains("1") {
            return .one
        }
        // 3. Repeat all (checked after negative check)
        if lower.contains("all") || lower.contains("playlist") || lower.contains("context") || lower.contains("repeat") {
            return .all
        }
        return nil
    }

    /// Parses accessibility label or value text from Spotify UI into a ShuffleParseResult.
    /// Check negatives first:
    /// - containing "off", "disabled", "not" -> isShuffled: false, isSmart: false
    /// - containing "smart", "ai", "enhanced" -> isShuffled: true, isSmart: true
    /// - containing "on", "enabled", "shuffle" (after off check) -> isShuffled: true, isSmart: false
    /// - Unknown strings: nil (state unchanged, raw string logged by caller)
    static func parseShuffleResult(_ text: String) -> ShuffleParseResult? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return nil }

        // 1. Negatives first
        if lower.contains("off") || lower.contains("disabled") || lower.contains("not") {
            return ShuffleParseResult(isShuffled: false, isSmart: false)
        }
        // 2. Smart / AI shuffle
        if lower.contains("smart") || lower.contains("ai") || lower.contains("enhanced") {
            return ShuffleParseResult(isShuffled: true, isSmart: true)
        }
        // 3. On / enabled / shuffle (after off check)
        if lower.contains("on") || lower.contains("enabled") || lower.contains("shuffle") {
            return ShuffleParseResult(isShuffled: true, isSmart: false)
        }
        return nil
    }

    /// Convenience for callers needing only Bool
    static func parseShuffleText(_ text: String) -> Bool? {
        parseShuffleResult(text)?.isShuffled
    }

    /// Resolves RepeatMode from candidate value (preferred) or label.
    static func parseRepeatCandidate(label: String, value: String) -> RepeatMode? {
        if !value.isEmpty, let mode = parseRepeatText(value) {
            return mode
        }
        return parseRepeatText(label)
    }

    /// Resolves ShuffleParseResult from candidate value (preferred) or label.
    static func parseShuffleCandidate(label: String, value: String) -> ShuffleParseResult? {
        if !value.isEmpty, let res = parseShuffleResult(value) {
            return res
        }
        return parseShuffleResult(label)
    }
}
