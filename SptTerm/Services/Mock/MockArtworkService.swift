import SwiftUI

/// Deterministic glyph-grid artwork. Same seed always yields the same art.
final class MockArtworkService: ArtworkProviding {
    func artwork(seed: String, columns: Int) -> TrackArtwork {
        let cols = max(columns, 4)
        let rows = max(Int((Double(cols) * 0.72).rounded()), 4)

        var generator = SeededGenerator(seed: Self.hash(seed))
        let hue = Double((Self.hash(seed) >> 8) % 360) / 360

        let blobCount = 3 + generator.nextInt(2)
        var blobs: [(x: Double, y: Double, radius: Double, weight: Double)] = []
        for _ in 0..<blobCount {
            blobs.append((
                x: generator.nextDouble(),
                y: generator.nextDouble(),
                radius: 0.22 + generator.nextDouble() * 0.32,
                weight: 0.6 + generator.nextDouble() * 0.4
            ))
        }
        let phase = generator.nextDouble() * 2

        let ramp = Array(" .:-=+*#%@")
        var lines: [String] = []
        for row in 0..<rows {
            let ny = Double(row) / Double(max(rows - 1, 1))
            var line = ""
            for column in 0..<cols {
                let nx = Double(column) / Double(max(cols - 1, 1))
                let mirrored = min(nx, 1 - nx) * 2

                var intensity = 0.0
                for blob in blobs {
                    let blobX = min(blob.x, 1 - blob.x) * 2
                    let dx = mirrored - blobX
                    let dy = ny - blob.y
                    let distance = (dx * dx + dy * dy).squareRoot()
                    if distance < blob.radius {
                        intensity += (1 - distance / blob.radius) * blob.weight
                    }
                }
                intensity += 0.12 * sin((nx * 6 + phase) * .pi) * cos((ny * 5) * .pi)

                let normalized = min(max(intensity, 0), 1)
                let index = Int(normalized * Double(ramp.count - 1))
                line.append(ramp[index])
            }
            lines.append(line)
        }

        let accent = Color(hue: hue, saturation: 0.62, brightness: 0.95)
        return TrackArtwork(matrix: ASCIIGlyphMatrix(rows: lines), accent: accent)
    }

    private static func hash(_ seed: String) -> UInt64 {
        var value: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            value ^= UInt64(byte)
            value &*= 0x100000001b3
        }
        return value
    }
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextDouble() -> Double {
        Double(next() % 100_000) / 100_000
    }

    mutating func nextInt(_ upperBound: Int) -> Int {
        Int(next() % UInt64(max(upperBound, 1)))
    }
}
