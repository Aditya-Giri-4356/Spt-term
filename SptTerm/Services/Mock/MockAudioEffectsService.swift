import Combine
import Foundation

/// Stores EQ / effects values and persists them. No DSP is performed.
final class MockAudioEffectsService: AudioEffectsServiceProtocol {
    private let subject: CurrentValueSubject<AudioEffectsState, Never>
    private let store: AudioPresetStoring

    init(store: AudioPresetStoring = JSONAudioPresetStore()) {
        self.store = store
        var state = AudioEffectsState.default
        if let persisted = store.load() {
            state.bandGains = persisted.bandGains
            state.bassBoost = persisted.bassBoost
            state.treble = persisted.treble
            state.stereoWidth = persisted.stereoWidth
            state.compressorEnabled = persisted.compressorEnabled
            state.compressorAmount = persisted.compressorAmount
            state.limiterEnabled = persisted.limiterEnabled
            state.limiterThreshold = persisted.limiterThreshold
            state.activePresetID = persisted.activePresetID
            state.customPresets = persisted.customPresets
            if let profile = state.profiles.first(where: { $0.id == persisted.profileID }) {
                state.currentProfile = profile
            }
        }
        subject = CurrentValueSubject(state)
    }

    static func ephemeral() -> MockAudioEffectsService {
        MockAudioEffectsService(store: InMemoryAudioPresetStore())
    }

    var state: AudioEffectsState { subject.value }

    var statePublisher: AnyPublisher<AudioEffectsState, Never> {
        subject.eraseToAnyPublisher()
    }

    // MARK: EQ

    func setEQBand(_ band: EQBand, gain: Double) {
        update { state in
            state.bandGains[band.id] = min(max(gain, -12), 12)
            state.activePresetID = nil
        }
    }

    func setBassBoost(_ value: Double) {
        update { state in
            state.bassBoost = min(max(value, -12), 12)
            state.activePresetID = nil
        }
    }

    func setTreble(_ value: Double) {
        update { state in
            state.treble = min(max(value, -12), 12)
            state.activePresetID = nil
        }
    }

    func setStereoWidth(_ value: Double) {
        update { state in
            state.stereoWidth = value.clampedUnit
            state.activePresetID = nil
        }
    }

    func setCompressor(enabled: Bool, amount: Double) {
        update { state in
            state.compressorEnabled = enabled
            state.compressorAmount = min(max(amount, 0), 1)
        }
    }

    func setLimiter(enabled: Bool, threshold: Double) {
        update { state in
            state.limiterEnabled = enabled
            state.limiterThreshold = min(max(threshold, -12), 0)
        }
    }

    // MARK: Presets

    func applyPreset(_ preset: AudioPreset) {
        update { state in
            state.bandGains = preset.bandGains
            state.bassBoost = preset.bassBoost
            state.treble = preset.treble
            state.stereoWidth = preset.stereoWidth
            state.compressorAmount = preset.compressorAmount
            state.limiterThreshold = preset.limiterThreshold
            state.activePresetID = preset.id
        }
    }

    func saveCustomPreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        update { state in
            let resolved = trimmed.isEmpty ? "Custom \(state.customPresets.count + 1)" : trimmed
            let preset = AudioPreset(
                id: "custom-\(UUID().uuidString.prefix(8))",
                name: resolved,
                isBuiltIn: false,
                bandGains: state.bandGains,
                bassBoost: state.bassBoost,
                treble: state.treble,
                stereoWidth: state.stereoWidth,
                compressorAmount: state.compressorAmount,
                limiterThreshold: state.limiterThreshold
            )
            state.customPresets.append(preset)
            state.activePresetID = preset.id
        }
    }

    func deleteCustomPreset(id: String) {
        update { state in
            state.customPresets.removeAll { $0.id == id }
            if state.activePresetID == id {
                state.activePresetID = nil
            }
        }
    }

    // MARK: Profiles

    func selectProfile(_ profile: AudioProfile) {
        update { state in
            state.currentProfile = profile
        }
    }

    func resetBands() {
        update { state in
            state.bandGains = [:]
            state.bassBoost = 0
            state.treble = 0
            state.stereoWidth = 0.5
            state.activePresetID = nil
        }
    }

    // MARK: Persistence

    private func update(_ mutate: (inout AudioEffectsState) -> Void) {
        var next = state
        mutate(&next)
        subject.send(next)
        write(next)
    }

    private func write(_ state: AudioEffectsState) {
        store.save(
            PersistedAudioSettings(
                bandGains: state.bandGains,
                bassBoost: state.bassBoost,
                treble: state.treble,
                stereoWidth: state.stereoWidth,
                compressorEnabled: state.compressorEnabled,
                compressorAmount: state.compressorAmount,
                limiterEnabled: state.limiterEnabled,
                limiterThreshold: state.limiterThreshold,
                activePresetID: state.activePresetID,
                customPresets: state.customPresets,
                profileID: state.currentProfile.id
            )
        )
    }
}
