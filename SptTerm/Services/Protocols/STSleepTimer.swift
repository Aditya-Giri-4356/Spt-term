import Foundation

/// Manages a persistent sleep timer for playback in suite `com.aditya.sptterm.tweak`.
final class STSleepTimer {
    static let shared = STSleepTimer()
    private let suiteName = "com.aditya.sptterm.tweak"
    private let endTimeKey = "sptterm.sleep_timer.end_time"
    private var timerTask: Task<Void, Never>?

    private var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private init() {}

    func setup(player: PlayerServiceProtocol) {
        checkAndSchedule(player: player)
    }

    func setTimer(minutes: Double, player: PlayerServiceProtocol) -> String {
        guard minutes > 0 else { return "invalid sleep duration: \(minutes)m" }
        timerTask?.cancel()
        let endDate = Date().addingTimeInterval(minutes * 60)
        defaults.set(endDate.timeIntervalSince1970, forKey: endTimeKey)

        scheduleTask(for: endDate, player: player)

        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return "> sleep: set for \(minutes)m (pauses at \(formatter.string(from: endDate)))"
    }

    func cancel() -> String {
        timerTask?.cancel()
        timerTask = nil
        defaults.removeObject(forKey: endTimeKey)
        return "> sleep: timer cancelled"
    }

    func status() -> String {
        let stored = defaults.double(forKey: endTimeKey)
        guard stored > 0 else {
            return "> sleep: no active timer (use sleep <minutes>)"
        }
        let remaining = stored - Date().timeIntervalSince1970
        guard remaining > 0 else {
            defaults.removeObject(forKey: endTimeKey)
            return "> sleep: no active timer"
        }
        return "> sleep: \(TermFormat.duration(remaining)) remaining"
    }

    private func checkAndSchedule(player: PlayerServiceProtocol) {
        let stored = defaults.double(forKey: endTimeKey)
        guard stored > 0 else { return }
        let remaining = stored - Date().timeIntervalSince1970
        if remaining <= 0 {
            defaults.removeObject(forKey: endTimeKey)
            DispatchQueue.main.async {
                player.pause()
                STLog.log("SptTerm: sleep timer expired on launch, paused playback")
            }
        } else {
            let endDate = Date(timeIntervalSince1970: stored)
            scheduleTask(for: endDate, player: player)
        }
    }

    private func scheduleTask(for endDate: Date, player: PlayerServiceProtocol) {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            let remaining = endDate.timeIntervalSince(Date())
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                player.pause()
                STLog.log("SptTerm: sleep timer fired, paused playback")
                self.defaults.removeObject(forKey: self.endTimeKey)
            }
        }
    }
}
