import Foundation
#if canImport(UIKit)
import UIKit
#endif

final class STLog {
    static let shared = STLog()
    static let logCopy = "log copy"
    static let seekNA = "SEEK N/A"
    static let repeatNA = "REPEAT N/A"
    static let repeatUnverified = "REPEAT (UNVERIFIED)"
    static let shuffleNA = "SHUFFLE N/A"
    static let shuffleUnverified = "SHUFFLE (UNVERIFIED)"
    static let artworkNilPrefix = "artwork nil for"

    private var buffer: [String] = []
    private let lock = NSLock()
    private let maxCapacity = 600

    static func log(_ message: String) {
        shared.append(message)
    }

    func append(_ message: String) {
        let line = message.hasPrefix("SptTerm:") ? message : "SptTerm: \(message)"
        NSLog("%@", line)
        lock.lock()
        defer { lock.unlock() }
        buffer.append(line)
        if buffer.count > maxCapacity {
            buffer.removeFirst(buffer.count - maxCapacity)
        }
    }

    func lastLines(_ count: Int = 40) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(buffer.suffix(count))
    }

    func allLines() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
    }

    func grep(_ pattern: String) -> [String] {
        guard !pattern.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        let needle = pattern.lowercased()
        return buffer.filter { $0.lowercased().contains(needle) }
    }

    static func sanitizeUserIDs(_ text: String) -> String {
        var result = text.replacingOccurrences(
            of: "spotify:user:[a-zA-Z0-9_\\-\\.]+",
            with: "spotify:user:XXXX",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "/users/[a-zA-Z0-9_\\-\\.]+",
            with: "/users/XXXX",
            options: .regularExpression
        )
        return result
    }

    func copyToPasteboard() {
        let text = Self.sanitizeUserIDs(allLines().joined(separator: "\n"))
        #if canImport(UIKit)
        DispatchQueue.main.async {
            UIPasteboard.general.string = text
        }
        #endif
    }
}
