import Combine
import Foundation

/// DSP surface for the tuning panel. Phase 1 only stores values.
protocol AudioEffectsServiceProtocol: AnyObject {
    var state: AudioEffectsState { get }
    var statePublisher: AnyPublisher<AudioEffectsState, Never> { get }

    func setEQBand(_ band: EQBand, gain: Double)
    func setBassBoost(_ value: Double)
    func setTreble(_ value: Double)
    func setStereoWidth(_ value: Double)
    func setCompressor(enabled: Bool, amount: Double)
    func setLimiter(enabled: Bool, threshold: Double)

    func applyPreset(_ preset: AudioPreset)
    func saveCustomPreset(named name: String)
    func deleteCustomPreset(id: String)
    func selectProfile(_ profile: AudioProfile)
    func resetBands()
}
