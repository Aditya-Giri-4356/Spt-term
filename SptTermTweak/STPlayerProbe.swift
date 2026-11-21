import ObjectiveC
import UIKit

/// Dumps available selectors on first launch so the control layer can be
/// written against real names instead of guesses.
enum STPlayerProbe {
    static let reportPath = "/tmp/sptterm-probe.txt"

    private static let candidates = ["SPTPlayerImpl", "SPTCoreServiceHub", "SPTPlayer"]

    static func runIfNeeded() {
        guard !FileManager.default.fileExists(atPath: reportPath) else { return }

        var out = "SptTerm selector probe\n\n"
        for name in candidates {
            guard let cls = NSClassFromString(name) else {
                out += "\(name): NOT FOUND\n\n"
                continue
            }
            out += "\(name):\n"
            var count: UInt32 = 0
            if let methods = class_copyMethodList(cls, &count) {
                for index in 0..<Int(count) {
                    out += "  -\(NSStringFromSelector(method_getName(methods[index])))\n"
                }
                free(methods)
            }
            out += "\n"
        }

        try? out.write(toFile: reportPath, atomically: true, encoding: .utf8)
        NSLog("[SptTerm] probe written to %@", reportPath)
    }
}
