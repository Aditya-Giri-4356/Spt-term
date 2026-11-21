import SpotifyiOS
import SwiftUI
import UIKit

private final class STImageItem: NSObject, SPTAppRemoteImageRepresentable {
    let imageIdentifier: String
    init(imageIdentifier: String) {
        self.imageIdentifier = imageIdentifier
    }
}

/// Raster covers converted to the glyph grid the design uses. The provider is
/// synchronous, so this returns cached or generated art immediately and fills
/// the real image in behind it.
final class STRemoteArtworkService: ArtworkProviding {
    private let fallback = MockArtworkService()
    private let remote: () -> SPTAppRemote?

    private var cache: [String: TrackArtwork] = [:]
    private var inFlight = Set<String>()
    private let lock = NSLock()

    private static let ramp = Array(" .:-=+*#%@")

    init(remote: @escaping () -> SPTAppRemote?) {
        self.remote = remote
    }

    func artwork(seed: String, columns: Int) -> TrackArtwork {
        if let cached = cachedArt(seed: seed) { return cached }

        let generated = fallback.artwork(seed: seed, columns: columns)
        startFetch(seed: seed, columns: columns)
        return generated
    }

    private func startFetch(seed: String, columns: Int) {
        guard let uri = imageURI(from: seed) else { return }

        lock.lock()
        let alreadyRunning = !inFlight.insert(uri).inserted
        lock.unlock()
        guard !alreadyRunning else { return }

        let item = STImageItem(imageIdentifier: uri)
        remote()?.imageAPI?.fetchImage(forItem: item, with: .zero) { [weak self] result, error in
            guard let self else { return }

            self.lock.lock()
            self.inFlight.remove(uri)
            self.lock.unlock()

            guard error == nil, let image = result as? UIImage else { return }

            let matrix = Self.matrix(from: image, columns: columns)
            let accent = Self.accent(from: image)

            self.lock.lock()
            self.cache[seed] = TrackArtwork(matrix: matrix, accent: accent)
            self.lock.unlock()
        }
    }

    private func cachedArt(seed: String) -> TrackArtwork? {
        lock.lock()
        defer { lock.unlock() }
        return cache[seed]
    }

    private func imageURI(from seed: String) -> String? {
        guard let id = seed.split(separator: "|").first, !id.isEmpty else { return nil }
        return "spotify:image:\(id)"
    }

    private static func matrix(from image: UIImage, columns: Int) -> ASCIIGlyphMatrix {
        let cols = max(columns, 4)
        let rows = max(Int((Double(cols) * 0.72).rounded()), 4)

        var pixels = [UInt8](repeating: 0, count: cols * rows)
        let space = CGColorSpaceCreateDeviceGray()

        guard let context = CGContext(
            data: &pixels,
            width: cols,
            height: rows,
            bitsPerComponent: 8,
            bytesPerRow: cols,
            space: space,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let cgImage = image.cgImage else {
            return .placeholder
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cols, height: rows))

        var lines: [String] = []
        for row in 0..<rows {
            var line = ""
            for column in 0..<cols {
                let luminance = Double(pixels[row * cols + column]) / 255
                let index = min(Int(luminance * Double(ramp.count)), ramp.count - 1)
                line.append(ramp[index])
            }
            lines.append(line)
        }
        return ASCIIGlyphMatrix(rows: lines)
    }

    private static func accent(from image: UIImage) -> Color {
        guard let average = image.averageColor() else { return .accentColor }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        average.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return Color(red: Double(red), green: Double(green), blue: Double(blue))
    }
}

extension UIImage {
    /// 1×1 redraw used only for the accent tint.
    func averageColor() -> UIColor? {
        let space = CGColorSpaceCreateDeviceRGB()
        var pixel = [UInt8](repeating: 0, count: 4)

        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }
}
