import UIKit
import SwiftUI
import MediaPlayer

final class STInProcessArtworkService: ArtworkProviding {
    private let fallback = MockArtworkService()

    func artwork(for track: Track, columns: Int = 16) -> TrackArtwork {
        if let rows = track.artworkMatrixRows, !rows.isEmpty {
            let accent = track.artworkAccentHex.map { Color(termHex: $0) } ?? Color(red: 0.0, green: 1.0, blue: 0.4)
            return TrackArtwork(matrix: ASCIIGlyphMatrix(rows: rows), accent: accent)
        }
        return artwork(seed: "\(track.id)|\(track.albumTitle)|\(track.title)", columns: columns)
    }

    func artwork(seed: String, columns: Int) -> TrackArtwork {
        let cols = max(columns, 8)
        let rows = max(Int((Double(cols) * 0.72).rounded()), 6)

        var uiImage: UIImage?
        if Thread.isMainThread {
            uiImage = fetchArtworkImage(columns: cols, rows: rows)
        } else {
            DispatchQueue.main.sync { [self] in
                uiImage = fetchArtworkImage(columns: cols, rows: rows)
            }
        }

        guard let image = uiImage, let matrix = convertToASCIIMatrix(image: image, columns: cols, rows: rows) else {
            return fallback.artwork(seed: seed, columns: columns)
        }

        let accent = dominantColor(from: image) ?? Color(red: 0.0, green: 1.0, blue: 0.4)
        return TrackArtwork(matrix: matrix, accent: accent)
    }

    private func fetchArtworkImage(columns: Int, rows: Int) -> UIImage? {
        guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo,
              let artwork = info[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork else {
            return nil
        }
        return artwork.image(at: CGSize(width: columns * 6, height: rows * 6))
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

    private func dominantColor(from image: UIImage) -> Color? {
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
        return Color(red: r, green: g, blue: b)
    }
}
