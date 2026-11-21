import UIKit
import SwiftUI
import MediaPlayer

final class STInProcessArtworkService: ArtworkProviding {
    static let shared = STInProcessArtworkService()

    private let fallback = MockArtworkService()
    private var cache: [String: TrackArtwork] = [:]
    private var loggedNilURIs = Set<String>()
    private var currentURI: String?
    private let lock = NSLock()

    func artwork(for track: Track, columns: Int = 16) -> TrackArtwork {
        let uri = track.id
        lock.lock()
        defer { lock.unlock() }

        if currentURI != uri {
            currentURI = uri
        }

        // 1. If stored ASCII matrix exists on the track itself (from session history), use it
        if let rows = track.artworkMatrixRows, !rows.isEmpty {
            let accent = track.artworkAccentHex.map { Color(termHex: $0) } ?? Color(red: 0.0, green: 1.0, blue: 0.4)
            let art = TrackArtwork(matrix: ASCIIGlyphMatrix(rows: rows), accent: accent)
            cache[uri] = art
            return art
        }

        // 2. If cached artwork exists for this exact URI, return it
        // ("If nowPlayingInfo has no artwork but the URI is unchanged, keep the cached cover")
        // ("Never show the previous track's cover for a new URI")
        if let cached = cache[uri] {
            return cached
        }

        // 3. Try to resolve live artwork from nowPlayingInfo
        if let live = resolveLiveArtworkLocked(uri: uri, columns: columns) {
            cache[uri] = live
            return live
        }

        // 4. Live artwork is nil for this URI:
        // ("If the URI changed and artwork is nil, show the placeholder and retry every poll until it arrives")
        // ("Log 'SptTerm: artwork nil for <uri>' once per track")
        if !loggedNilURIs.contains(uri) {
            loggedNilURIs.insert(uri)
            STLog.log("SptTerm: \(STLog.artworkNilPrefix) \(uri)")
        }

        return fallback.artwork(seed: "placeholder::\(uri)", columns: columns)
    }

    func artwork(seed: String, columns: Int) -> TrackArtwork {
        return fallback.artwork(seed: seed, columns: columns)
    }

    func hasCachedArtwork(for uri: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cache[uri] != nil
    }

    /// Attempts to fetch live artwork from nowPlayingInfo on the main thread and rasterize it.
    @discardableResult
    func tryResolveLiveArtwork(for uri: String, columns: Int = 16) -> TrackArtwork? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[uri] {
            return cached
        }
        if let live = resolveLiveArtworkLocked(uri: uri, columns: columns) {
            cache[uri] = live
            return live
        }
        return nil
    }

    private func resolveLiveArtworkLocked(uri: String, columns: Int) -> TrackArtwork? {
        let cols = max(columns, 8)
        let rows = max(Int((Double(cols) * 0.72).rounded()), 6)

        var uiImage: UIImage?
        let fetchBlock = { () -> UIImage? in
            guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo,
                  let artwork = info[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork else {
                return nil
            }
            // Request imageWithSize on main thread at 300x300, and if nil, at artwork's own bounds.size
            if let img = artwork.image(at: CGSize(width: 300, height: 300)) {
                return img
            }
            return artwork.image(at: artwork.bounds.size)
        }

        if Thread.isMainThread {
            uiImage = fetchBlock()
        } else {
            DispatchQueue.main.sync {
                uiImage = fetchBlock()
            }
        }

        guard let image = uiImage, let matrix = convertToASCIIMatrix(image: image, columns: cols, rows: rows) else {
            return nil
        }

        let dominant = dominantColor(from: image)
        let accent = dominant?.color ?? Color(red: 0.0, green: 1.0, blue: 0.4)
        let hex = dominant?.hex ?? "#00FF66"
        return TrackArtwork(matrix: matrix, accent: accent, accentHex: hex)
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
        let r = (totalR / count) / 255.0
        let g = (totalG / count) / 255.0
        let b = (totalB / count) / 255.0
        let hex = String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        return (Color(red: r, green: g, blue: b), hex)
    }
}
