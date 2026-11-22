import Foundation
import QuartzCore

/// Performance and hitch diagnostics logger.
final class STPerfLogger: NSObject {
    static let shared = STPerfLogger()

    private(set) var isEnabled: Bool = false
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    var currentScreen: String = "play"

    private override init() {
        super.init()
    }

    func setEnabled(_ enabled: Bool) {
        if Thread.isMainThread {
            applyEnabled(enabled)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.applyEnabled(enabled)
            }
        }
    }

    private func applyEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        stop()
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(handleFrame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = 0
    }

    @objc private func handleFrame(_ link: CADisplayLink) {
        if lastTimestamp > 0 {
            let gap = (link.timestamp - lastTimestamp) * 1000.0
            if gap > 50.0 {
                let ms = Int(gap.rounded())
                STLog.log("hitch \(ms) ms screen=\(currentScreen)")
            }
        }
        lastTimestamp = link.timestamp
    }

    func measureBlock<T>(label: String, thresholdMs: Double = 8.0, action: () throws -> T) rethrows -> T {
        guard isEnabled else { return try action() }
        let start = CACurrentMediaTime()
        let result = try action()
        let elapsedMs = (CACurrentMediaTime() - start) * 1000.0
        if elapsedMs > thresholdMs {
            let ms = Int(elapsedMs.rounded())
            STLog.log("main-thread block \(ms) ms: \(label)")
        }
        return result
    }
}
