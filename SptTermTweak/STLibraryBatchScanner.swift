import UIKit

/// Performs multi-step automated scroll-scanning of a Spotify collection or table view.
/// User-triggered only, never automatic, never repeating.
@MainActor
final class STLibraryBatchScanner {

    /// Finds the UICollectionView or UITableView holding the most kept rows (playlist or track).
    private static func findTargetScrollView() -> UIScrollView? {
        let elements = STSpotifyLibraryScanner.scanOnScreenElements(logSummary: false)
        let keptElements = elements.filter { $0.isPlaylistCandidate || $0.isTrackCandidate }
        guard !keptElements.isEmpty else { return nil }

        var counts: [ObjectIdentifier: (view: UIScrollView, count: Int)] = [:]

        for elem in keptElements {
            guard let view = elem.view else { continue }
            var curr = view.superview
            while let p = curr {
                if (p is UICollectionView) || (p is UITableView), let sv = p as? UIScrollView {
                    let key = ObjectIdentifier(sv)
                    let current = counts[key]?.count ?? 0
                    counts[key] = (sv, current + 1)
                    break
                }
                curr = p.superview
            }
        }

        let sorted = counts.values.sorted { $0.count > $1.count }
        return sorted.first?.view
    }

    /// Asynchronous runner for `scanAll`.
    static func runScanAll() async -> (steps: Int, namesTotal: Int) {
        await withCheckedContinuation { continuation in
            startScanAll { steps, total in
                continuation.resume(returning: (steps, total))
            }
        }
    }

    /// Starts multi-step stepping scan down the target scroll view.
    static func startScanAll(completion: ((Int, Int) -> Void)? = nil) {
        guard let scrollView = findTargetScrollView() else {
            STLog.log("SptTerm: libscan all: no suitable scroll view found")
            completion?(0, 0)
            return
        }

        let initialOffset = scrollView.contentOffset
        let visibleHeight = scrollView.bounds.height
        let stepDelta = 0.8 * visibleHeight
        let maxOffsetY = max(0, scrollView.contentSize.height - visibleHeight)

        var step = 0
        var consecutiveNoNew = 0
        var totalPlaylistsBefore = STLibraryCache.shared.allPlaylists().count
        var totalTracksBefore = STOpenedPlaylistTracks.shared.allTracks().count

        STLog.log("SptTerm: libscan all starting on [\(NSStringFromClass(type(of: scrollView)))] (maxOffset: \(Int(maxOffsetY)), visibleH: \(Int(visibleHeight)))")

        func performStep() {
            _ = STSpotifyLibraryScanner.scanAndCachePlaylists()

            let currentP = STLibraryCache.shared.allPlaylists().count
            let currentT = STOpenedPlaylistTracks.shared.allTracks().count
            let newNames = (currentP - totalPlaylistsBefore) + (currentT - totalTracksBefore)

            totalPlaylistsBefore = currentP
            totalTracksBefore = currentT

            if newNames > 0 {
                consecutiveNoNew = 0
            } else {
                consecutiveNoNew += 1
            }

            let reachedBottom = scrollView.contentOffset.y >= maxOffsetY - 2.0
            let hitLimit = step >= 40
            let hitStall = consecutiveNoNew >= 2

            if hitLimit || hitStall || reachedBottom {
                scrollView.setContentOffset(initialOffset, animated: false)
                let totalNames = currentP + currentT
                STLog.log("SptTerm: libscan all: \(step) steps, \(totalNames) names total")
                completion?(step, totalNames)
                return
            }

            step += 1
            let nextY = min(maxOffsetY, scrollView.contentOffset.y + stepDelta)
            scrollView.setContentOffset(CGPoint(x: initialOffset.x, y: nextY), animated: false)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                performStep()
            }
        }

        performStep()
    }
}
