import Foundation
import Combine

final class STAudioTweaksService: AudioEffectsServiceProtocol {
    private let subject: CurrentValueSubject<AudioEffectsState, Never>
    private let defaults: UserDefaults

    var state: AudioEffectsState { subject.value }
    var statePublisher: AnyPublisher<AudioEffectsState, Never> {
        subject.eraseToAnyPublisher()
    }

    init(defaults: UserDefaults = UserDefaults(suiteName: "com.aditya.sptterm.tweak") ?? .standard) {
        self.defaults = defaults
        var loaded = AudioEffectsState.default
        if let data = defaults.data(forKey: "sptterm.tweak.effects"),
           let decoded = try? JSONDecoder().decode(AudioEffectsState.self, from: data) {
            loaded = decoded
        }
        subject = CurrentValueSubject(loaded)
    }

    func setEQBand(_ band: EQBand, gain: Double) {
        update { $0.bandGains[band.id] = min(max(gain, -12), 12) }
    }

    func setBassBoost(_ value: Double) {
        update { $0.bassBoost = min(max(value, -12), 12) }
    }

    func setTreble(_ value: Double) {
        update { $0.treble = min(max(value, -12), 12) }
    }

    func setStereoWidth(_ value: Double) {
        update { $0.stereoWidth = min(max(value, 0), 1) }
    }

    func setCompressor(enabled: Bool, amount: Double) {
        update {
            $0.compressorEnabled = enabled
            $0.compressorAmount = min(max(amount, 0), 1)
        }
    }

    func setLimiter(enabled: Bool, threshold: Double) {
        update {
            $0.limiterEnabled = enabled
            $0.limiterThreshold = min(max(threshold, -6), 0)
        }
    }

    func applyPreset(_ preset: AudioPreset) {
        update {
            $0.bandGains = preset.bandGains
            $0.bassBoost = preset.bassBoost
            $0.treble = preset.treble
            $0.stereoWidth = preset.stereoWidth
            $0.compressorAmount = preset.compressorAmount
            $0.limiterThreshold = preset.limiterThreshold
            $0.activePresetID = preset.id
        }
    }

    func saveCustomPreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let current = state
        let preset = AudioPreset(
            id: "custom-\(UUID().uuidString.prefix(8))",
            name: trimmed,
            isBuiltIn: false,
            bandGains: current.bandGains,
            bassBoost: current.bassBoost,
            treble: current.treble,
            stereoWidth: current.stereoWidth,
            compressorAmount: current.compressorAmount,
            limiterThreshold: current.limiterThreshold
        )
        update {
            $0.customPresets.append(preset)
            $0.activePresetID = preset.id
        }
    }

    func deleteCustomPreset(id: String) {
        update {
            $0.customPresets.removeAll { $0.id == id }
            if $0.activePresetID == id { $0.activePresetID = nil }
        }
    }

    func selectProfile(_ profile: AudioProfile) {
        update { $0.currentProfile = profile }
    }

    func resetBands() {
        update {
            $0.bandGains = [:]
            $0.bassBoost = 0
            $0.treble = 0
            $0.activePresetID = nil
        }
    }

    private func update(_ mutate: (inout AudioEffectsState) -> Void) {
        var next = subject.value
        mutate(&next)
        subject.send(next)
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: "sptterm.tweak.effects")
        }
    }
}
