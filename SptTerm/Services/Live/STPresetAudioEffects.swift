import Combine
import Foundation

/// Preset store only. Spotify's audio renders in a separate process, so these
/// values persist and surface but cannot reach the samples. `apply(to:)` is the
/// hook a future in-process DSP pass would fill.
final class STPresetAudioEffects: AudioEffectsServiceProtocol {
    private enum Key {
        static let state = "sptterm.effects"
    }

    private let subject: CurrentValueSubject<AudioEffectsState, Never>
    private let defaults: UserDefaults

    var state: AudioEffectsState { subject.value }

    var statePublisher: AnyPublisher<AudioEffectsState, Never> {
        subject.eraseToAnyPublisher()
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        subject = CurrentValueSubject(Self.load(from: defaults))
    }

    func setEQBand(_ band: EQBand, gain: Double) {
        update { $0.bandGains[band.id] = gain.stClampedGain }
    }

    func setBassBoost(_ value: Double) {
        update { $0.bassBoost = value.stClampedGain }
    }

    func setTreble(_ value: Double) {
        update { $0.treble = value.stClampedGain }
    }

    func setStereoWidth(_ value: Double) {
        update { $0.stereoWidth = value.stClampedUnit }
    }

    func setCompressor(enabled: Bool, amount: Double) {
        update {
            $0.compressorEnabled = enabled
            $0.compressorAmount = amount.stClampedUnit
        }
    }

    func setLimiter(enabled: Bool, threshold: Double) {
        update {
            $0.limiterEnabled = enabled
            $0.limiterThreshold = threshold.stClampedThreshold
        }
    }

    func resetBands() {
        update {
            $0.bandGains = [:]
            $0.bassBoost = 0
            $0.treble = 0
            $0.activePresetID = nil
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

    /// No-op pending in-process DSP. Logged so the gap stays visible.
    func apply(to track: Track?) {
        NSLog(
            "[SptTerm] effects stored, not applied (%@) — cross-process audio",
            track?.title ?? "nil"
        )
    }

    private func update(_ mutate: (inout AudioEffectsState) -> Void) {
        var next = subject.value
        mutate(&next)
        subject.send(next)
        Self.save(next, to: defaults)
    }

    private static func load(from defaults: UserDefaults) -> AudioEffectsState {
        guard let data = defaults.data(forKey: Key.state),
              let decoded = try? JSONDecoder().decode(AudioEffectsState.self, from: data)
        else { return .default }
        return decoded
    }

    private static func save(_ state: AudioEffectsState, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Key.state)
    }
}
