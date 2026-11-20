import Foundation

struct AudioPreset: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var isBuiltIn: Bool
    var bandGains: [Int: Double]
    var bassBoost: Double
    var treble: Double
    var stereoWidth: Double
    var compressorAmount: Double
    var limiterThreshold: Double

    var detail: String {
        isBuiltIn ? "FACTORY PRESET" : "CUSTOM PRESET"
    }

    static let builtIns: [AudioPreset] = [
        AudioPreset(
            id: "neutral",
            name: "Neutral",
            isBuiltIn: true,
            bandGains: [:],
            bassBoost: 0,
            treble: 0,
            stereoWidth: 0.5,
            compressorAmount: 0.2,
            limiterThreshold: -1
        ),
        AudioPreset(
            id: "warm",
            name: "Warm",
            isBuiltIn: true,
            bandGains: [32: 3.5, 64: 3.0, 125: 2.0, 250: 1.0, 500: 0, 1000: -0.5, 2000: -1.0, 4000: -1.5, 8000: -2.0, 16000: -2.5],
            bassBoost: 2.5,
            treble: -1.5,
            stereoWidth: 0.45,
            compressorAmount: 0.35,
            limiterThreshold: -1.5
        ),
        AudioPreset(
            id: "clarity",
            name: "Clarity",
            isBuiltIn: true,
            bandGains: [32: -1.5, 64: -1.0, 125: 0, 250: 1.0, 500: 1.5, 1000: 2.0, 2000: 2.5, 4000: 3.0, 8000: 2.0, 16000: 1.0],
            bassBoost: -1.0,
            treble: 3.0,
            stereoWidth: 0.6,
            compressorAmount: 0.15,
            limiterThreshold: -1
        ),
        AudioPreset(
            id: "punch",
            name: "Punch",
            isBuiltIn: true,
            bandGains: [32: 4.5, 64: 4.0, 125: 2.5, 250: 0.5, 500: -1.0, 1000: -1.5, 2000: 0, 4000: 1.0, 8000: 1.5, 16000: 1.0],
            bassBoost: 4.0,
            treble: 1.0,
            stereoWidth: 0.55,
            compressorAmount: 0.65,
            limiterThreshold: -0.5
        ),
        AudioPreset(
            id: "wide",
            name: "Wide",
            isBuiltIn: true,
            bandGains: [32: 1.0, 64: 0.5, 125: 0, 250: -0.5, 500: -0.5, 1000: 0, 2000: 0.5, 4000: 1.0, 8000: 1.5, 16000: 2.0],
            bassBoost: 1.5,
            treble: 2.0,
            stereoWidth: 0.95,
            compressorAmount: 0.25,
            limiterThreshold: -1
        )
    ]
}

struct AudioEffectsState: Equatable {
    var bandGains: [Int: Double]
    var bassBoost: Double
    var treble: Double
    var stereoWidth: Double
    var compressorEnabled: Bool
    var compressorAmount: Double
    var limiterEnabled: Bool
    var limiterThreshold: Double
    var activePresetID: String?
    var customPresets: [AudioPreset]
    var currentProfile: AudioProfile
    var profiles: [AudioProfile]

    var allPresets: [AudioPreset] {
        AudioPreset.builtIns + customPresets
    }

    var activePresetName: String {
        allPresets.first { $0.id == activePresetID }?.name ?? "CUSTOM"
    }

    func gain(for band: EQBand) -> Double {
        bandGains[band.id] ?? 0
    }

    static let `default` = AudioEffectsState(
        bandGains: [:],
        bassBoost: 0,
        treble: 0,
        stereoWidth: 0.5,
        compressorEnabled: false,
        compressorAmount: 0.2,
        limiterEnabled: true,
        limiterThreshold: -1,
        activePresetID: "neutral",
        customPresets: [],
        currentProfile: AudioProfile.defaults[2],
        profiles: AudioProfile.defaults
    )
}
