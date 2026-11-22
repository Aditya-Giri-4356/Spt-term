import UIKit
import SwiftUI
import MediaPlayer

final class STInProcessArtworkService: ArtworkProviding {
    static let shared = STInProcessArtworkService()

    private let fallback = MockArtworkService()
    private var cache: [String: TrackArtwork] = [:]
    private var currentURI: String?
    private var currentGeneration: Int = 0
    private var retryTask: Task<Void, Never>?
    private let lock = NSLock()

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleAppDidBecomeActive() {
        lock.lock()
        let uri = currentURI
        let hasCache = uri != nil ? (cache[uri!] != nil) : false
        lock.unlock()

        if let uri = uri, !hasCache {
            STLog.log("SptTerm: artwork app became active, retrying for \(uri)")
            startRetrySequence(for: uri) { _ in }
        }
    }

    func artwork(for track: Track, columns: Int = 16) -> TrackArtwork {
        let uri = track.id
        lock.lock()
        let previousURI = currentURI
        let isChanged = (previousURI != uri)
        if isChanged {
            currentURI = uri
            currentGeneration += 1
            STLog.log("SptTerm: artwork (a) track changed for \(uri) (gen \(currentGeneration))")
        }
        let cached = cache[uri]
        let storedRows = track.artworkMatrixRows
        let storedAccentHex = track.artworkAccentHex
        lock.unlock()

        // 1. Stored ASCII matrix from session history
        if let rows = storedRows, !rows.isEmpty {
            let accent = storedAccentHex.map { Color(termHex: $0) } ?? Color(red: 0.0, green: 1.0, blue: 0.4)
            let art = TrackArtwork(matrix: ASCIIGlyphMatrix(rows: rows), accent: accent, accentHex: storedAccentHex)
            lock.lock()
            cache[uri] = art
            lock.unlock()
            return art
        }

        // 2. Cached artwork for this exact URI
        if let cached {
            return cached
        }

        // 3. Cover missing: trigger background resolution with retry sequence, return placeholder frame
        if isChanged {
            startRetrySequence(for: uri) { _ in }
        }

        let seedKey = uri.hasPrefix("spotify:") ? "placeholder::\(uri)" : "fallback::\(track.title)|\(track.artistName)"
        return fallback.artwork(seed: seedKey, columns: columns)
    }

    func artwork(seed: String, columns: Int) -> TrackArtwork {
        return fallback.artwork(seed: seed, columns: columns)
    }

    func hasCachedArtwork(for uri: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cache[uri] != nil
    }

    /// Triggers the backoff retry sequence: 0.25, 0.5, 1, 2, 4, 8, 15 s after track change.
    func startRetrySequence(for uri: String, onResolved: @escaping (TrackArtwork) -> Void) {
        lock.lock()
        let gen = currentGeneration
        retryTask?.cancel()
        lock.unlock()

        retryTask = Task { [weak self] in
            let intervals: [TimeInterval] = [0.0, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 15.0]
            for delay in intervals {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                guard !Task.isCancelled else { return }
                guard let self else { return }

                if !self.shouldProceedWithRetry(for: uri, generation: gen) { return }

                if let resolved = await self.fetchAndProcessArtwork(for: uri, generation: gen) {
                    await MainActor.run {
                        STPerfLogger.shared.measureBlock(label: "artwork-apply") {
                            onResolved(resolved)
                        }
                    }
                    return
                }
            }
        }
    }

    private func shouldProceedWithRetry(for uri: String, generation gen: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentGeneration == gen && cache[uri] == nil
    }

    private func commitArtworkIfCurrent(for uri: String, generation: Int, artwork: TrackArtwork) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard currentGeneration == generation else { return false }
        cache[uri] = artwork
        return true
    }

    /// Fetches image from MPNowPlayingInfoCenter and converts off main thread.
    func fetchAndProcessArtwork(for uri: String, generation: Int, columns: Int = 16) async -> TrackArtwork? {
        let cols = max(columns, 8)
        let rows = max(Int((Double(cols) * 0.72).rounded()), 6)

        // Stage (b) & (c): inspect nowPlayingInfo on main thread
        let uiImage: UIImage? = await MainActor.run { () -> UIImage? in
            guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
                STLog.log("SptTerm: artwork (b) nowPlaying has artwork=false for \(uri) (info nil)")
                return nil
            }
            guard let artwork = info[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork else {
                STLog.log("SptTerm: artwork (b) nowPlaying has artwork=false for \(uri)")
                return nil
            }
            STLog.log("SptTerm: artwork (b) nowPlaying has artwork=true for \(uri)")

            // Try candidate sizes: 300x300, artwork.bounds.size, 600x600, 128x128
            let candidateSizes: [CGSize] = [
                CGSize(width: 300, height: 300),
                artwork.bounds.size,
                CGSize(width: 600, height: 600),
                CGSize(width: 128, height: 128)
            ]

            for size in candidateSizes where size.width > 0 && size.height > 0 {
                if let img = artwork.image(at: size) {
                    STLog.log("SptTerm: artwork (c) image(at: \(Int(size.width))x\(Int(size.height))) result=ok for \(uri)")
                    return img
                } else {
                    STLog.log("SptTerm: artwork (c) image(at: \(Int(size.width))x\(Int(size.height))) result=nil for \(uri)")
                }
            }
            return nil
        }

        guard let image = uiImage else { return nil }

        // Stage (d): decode image & convert to ASCII off the main thread
        let processed: TrackArtwork? = await Task.detached(priority: .userInitiated) { [weak self] () -> TrackArtwork? in
            guard let self, let matrix = self.convertToASCIIMatrix(image: image, columns: cols, rows: rows) else {
                STLog.log("SptTerm: artwork (d) ASCII conversion failure for \(uri)")
                return nil
            }
            STLog.log("SptTerm: artwork (d) ASCII conversion success for \(uri)")
            let dominant = self.dominantColor(from: image)
            let accent = dominant?.color ?? Color(red: 0.0, green: 1.0, blue: 0.4)
            let hex = dominant?.hex ?? "#00FF66"
            return TrackArtwork(matrix: matrix, accent: accent, accentHex: hex)
        }.value

        guard let artworkResult = processed else { return nil }

        // Stage (e): check generation token before caching and applying
        guard commitArtworkIfCurrent(for: uri, generation: generation, artwork: artworkResult) else {
            STLog.log("SptTerm: artwork (e) result discarded (generation mismatch for \(uri))")
            return nil
        }

        STLog.log("SptTerm: artwork (e) result applied to UI for \(uri)")
        return artworkResult
    }

    private func convertToASCIIMatrix(image: UIImage, columns: Int, rows: Int) -> ASCIIGlyphMatrix? {
        guard let cgImage = image.cgImage else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [UInt8](repeating: 0, count: columns * rows * 4)
        guard let context = CGContext(
            data: &pixelData,
            width: columns,
            height: rows,
            bitsPerComponent: 8,
            bytesPerRow: columns * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: columns, height: rows))

        let ramp = Array(" .:-=+*#%@")
        var lines: [String] = []

        for row in 0..<rows {
            var line = ""
            for col in 0..<columns {
                let offset = (row * columns + col) * 4
                let r = Double(pixelData[offset])
                let g = Double(pixelData[offset + 1])
                let b = Double(pixelData[offset + 2])
                let lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                let index = min(max(Int(lum * Double(ramp.count - 1)), 0), ramp.count - 1)
                line.append(ramp[index])
            }
            lines.append(line)
        }

        return ASCIIGlyphMatrix(rows: lines)
    }

    private func dominantColor(from image: UIImage) -> (color: Color, hex: String)? {
        guard let cgImage = image.cgImage else { return nil }
        let sampleSize = 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        guard let context = CGContext(
            data: &pixelData,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: sampleSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        var totalR: Double = 0
        var totalG: Double = 0
        var totalB: Double = 0
        var count: Double = 0

        for i in 0..<(sampleSize * sampleSize) {
            let offset = i * 4
            let a = Double(pixelData[offset + 3]) / 255.0
            if a > 0.3 {
                totalR += Double(pixelData[offset]) * a
                totalG += Double(pixelData[offset + 1]) * a
                totalB += Double(pixelData[offset + 2]) * a
                count += a
            }
        }

        guard count > 0 else { return nil }
        let r = min(max((totalR / count) / 255.0, 0), 1)
        let g = min(max((totalG / count) / 255.0, 0), 1)
        let b = min(max((totalB / count) / 255.0, 0), 1)
        let hex = String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        return (Color(red: r, green: g, blue: b), hex)
    }
}
