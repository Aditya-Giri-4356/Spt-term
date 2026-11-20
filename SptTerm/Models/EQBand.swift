import Foundation

/// One band of the 10-band graphic EQ (32Hz – 16kHz).
struct EQBand: Identifiable, Codable, Hashable {
    let id: Int
    let hz: Double
    let label: String

    static let standard: [EQBand] = [
        EQBand(id: 32, hz: 32, label: "32"),
        EQBand(id: 64, hz: 64, label: "64"),
        EQBand(id: 125, hz: 125, label: "125"),
        EQBand(id: 250, hz: 250, label: "250"),
        EQBand(id: 500, hz: 500, label: "500"),
        EQBand(id: 1000, hz: 1_000, label: "1k"),
        EQBand(id: 2000, hz: 2_000, label: "2k"),
        EQBand(id: 4000, hz: 4_000, label: "4k"),
        EQBand(id: 8000, hz: 8_000, label: "8k"),
        EQBand(id: 16000, hz: 16_000, label: "16k")
    ]
}

struct AudioProfile: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case headphones
        case speaker
        case bluetooth
        case car
        case studio
    }

    let id: String
    let name: String
    let detail: String
    let kind: Kind

    var glyph: String {
        switch kind {
        case .headphones: return "♫"
        case .speaker: return "◉"
        case .bluetooth: return "⌁"
        case .car: return "▣"
        case .studio: return "▤"
        }
    }

    static let defaults: [AudioProfile] = [
        AudioProfile(id: "headphones", name: "Wired Headphones", detail: "3.5mm / 24-bit DAC", kind: .headphones),
        AudioProfile(id: "speaker", name: "iPhone Speaker", detail: "Built-in stereo", kind: .speaker),
        AudioProfile(id: "bluetooth", name: "AirPods Pro 2", detail: "AAC-ELD / 48kHz", kind: .bluetooth),
        AudioProfile(id: "car", name: "Car Audio", detail: "Bluetooth / SBC", kind: .car),
        AudioProfile(id: "studio", name: "Studio Monitors", detail: "USB-C interface", kind: .studio)
    ]
}
