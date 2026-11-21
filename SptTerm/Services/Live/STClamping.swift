import Foundation

// ST-prefixed: `clampedUnit` already exists on Double in this repo.
extension Double {
    var stClampedUnit: Double { min(max(self, 0), 1) }
    var stClampedGain: Double { min(max(self, -12), 12) }
    var stClampedThreshold: Double { min(max(self, -6), 0) }
}
