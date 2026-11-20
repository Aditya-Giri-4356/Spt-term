import Foundation

/// Everything the tuning panel persists between launches.
struct PersistedAudioSettings: Codable {
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
    var profileID: String
}

protocol AudioPresetStoring: AnyObject {
    func load() -> PersistedAudioSettings?
    func save(_ settings: PersistedAudioSettings)
}

/// Codable JSON file in Application Support/SptTerm/audio-effects.json.
final class JSONAudioPresetStore: AudioPresetStoring {
    private let fileURL: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(filename: String = "audio-effects.json") {
        let manager = FileManager.default
        guard let base = try? manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            fileURL = nil
            return
        }
        let folder = base.appendingPathComponent("SptTerm", isDirectory: true)
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent(filename)
    }

    func load() -> PersistedAudioSettings? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(PersistedAudioSettings.self, from: data)
    }

    func save(_ settings: PersistedAudioSettings) {
        guard let fileURL, let data = try? encoder.encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Preview / test double that never touches disk.
final class InMemoryAudioPresetStore: AudioPresetStoring {
    private var settings: PersistedAudioSettings?

    init(settings: PersistedAudioSettings? = nil) {
        self.settings = settings
    }

    func load() -> PersistedAudioSettings? { settings }

    func save(_ settings: PersistedAudioSettings) {
        self.settings = settings
    }
}
