import Foundation
#if canImport(UIKit)
import UIKit
#endif

final class STLog {
    static let shared = STLog()
    static let logCopy = "log copy"
    static let seekNA = "SEEK N/A"

    private var buffer: [String] = []
    private let lock = NSLock()
    private let maxCapacity = 200

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

    func copyToPasteboard() {
        let text = allLines().joined(separator: "\n")
        #if canImport(UIKit)
        DispatchQueue.main.async {
            UIPasteboard.general.string = text
        }
        #endif
    }
}
