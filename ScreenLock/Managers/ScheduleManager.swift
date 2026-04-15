import Cocoa

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

    func checkSchedule() {
        let settings = SettingsManager.shared.settings

        if !settings.lockEnabled {
            if state != .normal {
                transitionToNormal()
            }
            return
        }

        let now = Date()

        guard let lockTime = nextOccurrence(of: settings.lockTime, after: now) else {
            print("ScheduleManager: Invalid lock time format")
            return
        }

        let warningTime = lockTime.addingTimeInterval(-Double(settings.warningMinutes) * 60)

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

    /// Returns the next occurrence of `timeString` (HH:mm) that is still in the
    /// future relative to `referenceDate`. When the time has already passed today
    /// the result rolls to tomorrow, keeping warningTime (derived by subtracting
    /// minutes from this result) on the correct calendar day.
    private func nextOccurrence(of timeString: String, after referenceDate: Date) -> Date? {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }

        let cal = Calendar.current
        var dc = cal.dateComponents([.year, .month, .day], from: referenceDate)
        dc.hour = parts[0]
        dc.minute = parts[1]
        dc.second = 0

        guard var target = cal.date(from: dc) else { return nil }

        if target <= referenceDate {
            target = cal.date(byAdding: .day, value: 1, to: target)!
        }

        return target
    }

    private func transitionToNormal() {
        state = .normal
        print("ScheduleManager: State -> Normal")
        onStateChange?(.normal)
    }

    private func transitionToWarning(durationMinutes: Int) {
        state = .warning
        print("ScheduleManager: State -> Warning")
        NSSound(named: "Tink")?.play()
        ScreenManager.shared.startGradualDimming(durationMinutes: durationMinutes)
        onStateChange?(.warning)
    }

    private func transitionToLocked() {
        state = .locked
        print("ScheduleManager: State -> Locked")
        ScreenManager.shared.lockScreenAndTurnOffDisplay { [weak self] in
            DispatchQueue.main.async {
                self?.transitionToNormal()
            }
        }
        onStateChange?(.locked)
    }

    func getTimeUntilLock() -> String {
        let settings = SettingsManager.shared.settings

        if !settings.lockEnabled {
            return "定时锁屏已禁用"
        }

        let now = Date()
        guard let lockTime = nextOccurrence(of: settings.lockTime, after: now) else {
            return "时间格式错误"
        }

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

    func lockNow() {
        transitionToLocked()
    }
}
