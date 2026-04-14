import Foundation

enum ScheduleState {
    case normal
    case warning
    case locked
}

class ScheduleManager {
    static let shared = ScheduleManager()

    private var timer: Timer?
    private(set) var state: ScheduleState = .normal

    var onStateChange: ((ScheduleState) -> Void)?

    private init() {}

    func start() {
        stop() // Clear any existing timer

        // Check every minute
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.checkSchedule()
        }

        // Also check immediately
        checkSchedule()

        print("ScheduleManager: Started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        print("ScheduleManager: Stopped")
    }

    private func checkSchedule() {
        let settings = SettingsManager.shared.settings
        let now = Date()

        guard let lockTime = parseTime(settings.lockTime) else {
            print("ScheduleManager: Invalid lock time format")
            return
        }

        let warningTime = Calendar.current.date(
            byAdding: .minute,
            value: -settings.warningMinutes,
            to: lockTime
        )!

        // Determine state
        if now >= lockTime {
            if state != .locked {
                transitionToLocked()
            }
        } else if now >= warningTime {
            if state != .warning {
                transitionToWarning(durationMinutes: settings.warningMinutes)
            }
        } else {
            if state != .normal {
                transitionToNormal()
            }
        }
    }

    private func parseTime(_ timeString: String) -> Date? {
        let components = timeString.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { return nil }

        let hour = components[0]
        let minute = components[1]

        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        dateComponents.hour = hour
        dateComponents.minute = minute
        dateComponents.second = 0

        guard var targetDate = Calendar.current.date(from: dateComponents) else { return nil }

        // If target time has passed today, schedule for tomorrow
        if targetDate < Date() {
            targetDate = Calendar.current.date(byAdding: .day, value: 1, to: targetDate)!
        }

        return targetDate
    }

    private func transitionToNormal() {
        state = .normal
        print("ScheduleManager: State -> Normal")
        onStateChange?(.normal)
    }

    private func transitionToWarning(durationMinutes: Int) {
        state = .warning
        print("ScheduleManager: State -> Warning")
        ScreenManager.shared.startGradualDimming(durationMinutes: durationMinutes)
        onStateChange?(.warning)
    }

    private func transitionToLocked() {
        state = .locked
        print("ScheduleManager: State -> Locked")
        ScreenManager.shared.lockScreenAndTurnOffDisplay()
        onStateChange?(.locked)

        // Reset to normal after lock (for next day)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.transitionToNormal()
        }
    }

    func getTimeUntilLock() -> String {
        let settings = SettingsManager.shared.settings
        guard let lockTime = parseTime(settings.lockTime) else {
            return "Invalid time"
        }

        let now = Date()
        let interval = lockTime.timeIntervalSince(now)

        if interval < 0 {
            return "已过锁屏时间"
        }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 0 {
            return "距离锁屏还有 \(hours)小时\(minutes)分钟"
        } else {
            return "距离锁屏还有 \(minutes)分钟"
        }
    }
}
