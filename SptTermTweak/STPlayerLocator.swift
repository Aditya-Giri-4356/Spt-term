import ObjectiveC
import UIKit

/// Breadth-first walk from the app delegate over known key paths until a
/// player-like object answers `currentTrack`.
enum STPlayerLocator {
    private static let keyPaths = [
        "player", "playerService", "playerImplementation", "core", "serviceHub",
    ]

    static func find() -> NSObject? {
        guard let delegate = UIApplication.shared.delegate as? NSObject else { return nil }

        var frontier: [NSObject] = [delegate]
        var seen = Set<ObjectIdentifier>([ObjectIdentifier(delegate)])

        for _ in 0..<3 {
            var next: [NSObject] = []
            for node in frontier {
                if isPlayer(node) { return node }
                for path in keyPaths {
                    let selector = NSSelectorFromString(path)
                    guard node.responds(to: selector),
                          let value = node.value(forKey: path) as? NSObject,
                          seen.insert(ObjectIdentifier(value)).inserted else { continue }
                    next.append(value)
                }
            }
            frontier = next
        }
        return nil
    }

    private static func isPlayer(_ object: NSObject) -> Bool {
        let name = String(describing: type(of: object))
        guard name.contains("Player") else { return false }
        return object.responds(to: NSSelectorFromString("currentTrack"))
    }
}
