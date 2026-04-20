import Cocoa
import UserNotifications
import os.log

private let log = OSLog(subsystem: "com.yugangcao.screenlock", category: "Schedule")

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
        stop()

        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.checkSchedule()
        }
        RunLoop.current.add(timer!, forMode: .common)

        checkSchedule()
        os_log("Started", log: log, type: .info)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        os_log("Stopped", log: log, type: .info)
    }

    func checkSchedule() {
        let settings = SettingsManager.shared.settings

        if !settings.lockEnabled {
            if state != .normal {
                ScreenManager.shared.cancelDimming()
                transitionToNormal()
            }
            return
        }

        let now = Date()

        guard let todayLock = todayOccurrence(of: settings.lockTime, relativeTo: now) else {
            os_log("Invalid lock time format", log: log, type: .error)
            return
        }

        let warningStart = todayLock.addingTimeInterval(-Double(settings.warningMinutes) * 60)

        // Grace window: within 2 minutes after lock time, still trigger lock.
        let graceEnd = todayLock.addingTimeInterval(120)

        if now >= todayLock && now < graceEnd {
            if state != .locked {
                transitionToLocked()
            }
        } else if now >= warningStart && now < todayLock {
            if state != .warning {
                transitionToWarning(durationMinutes: settings.warningMinutes)
            }
        } else {
            if state != .normal {
                ScreenManager.shared.cancelDimming()
                transitionToNormal()
            }
        }
    }

    /// Returns today's occurrence of `timeString` (HH:mm) regardless of whether
    /// it has passed. Used for range-based schedule comparison.
    private func todayOccurrence(of timeString: String, relativeTo now: Date) -> Date? {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2,
              (0...23).contains(parts[0]),
              (0...59).contains(parts[1]) else { return nil }

        let cal = Calendar.current
        var dc = cal.dateComponents([.year, .month, .day], from: now)
        dc.hour = parts[0]
        dc.minute = parts[1]
        dc.second = 0

        guard let target = cal.date(from: dc) else { return nil }

        // For times in the small hours (0:00–5:59), if current time is in the
        // evening (18:00+), this means the lock is "tonight" = tomorrow calendar day.
        if parts[0] < 6 && cal.component(.hour, from: now) >= 18 {
            return cal.date(byAdding: .day, value: 1, to: target)
        }

        // For evening times, if we're past the grace window, roll to tomorrow
        // so getTimeUntilLock shows the next occurrence.
        let graceEnd = target.addingTimeInterval(120)
        if now >= graceEnd && parts[0] >= 18 {
            return cal.date(byAdding: .day, value: 1, to: target)
        }

        return target
    }

    /// Used for countdown display — always returns a future lock time.
    private func nextLockTime(for settings: Settings, now: Date) -> Date? {
        guard let today = todayOccurrence(of: settings.lockTime, relativeTo: now) else { return nil }
        let graceEnd = today.addingTimeInterval(120)
        if now >= graceEnd {
            return Calendar.current.date(byAdding: .day, value: 1, to: today)
        }
        return today
    }

    private func transitionToNormal() {
        state = .normal
        os_log("State -> Normal", log: log, type: .info)
        onStateChange?(.normal)
    }

    private func transitionToWarning(durationMinutes: Int) {
        state = .warning
        os_log("State -> Warning", log: log, type: .info)
        NSSound(named: "Tink")?.play()
        ScreenManager.shared.startGradualDimming(durationMinutes: durationMinutes)
        sendWarningNotification(minutesLeft: durationMinutes)
        onStateChange?(.warning)
    }

    private func sendWarningNotification(minutesLeft: Int) {
        let content = UNMutableNotificationContent()
        content.title = L("warning.notification.title")
        content.body = L("warning.notification.body", minutesLeft)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "screenlock-warning",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                os_log("Failed to send notification: %{public}@", log: log, type: .error, error.localizedDescription)
            }
        }
    }

    private func transitionToLocked() {
        // Skip lock if displays are already asleep
        if ScreenManager.shared.areDisplaysAsleep() {
            os_log("Displays already asleep, skipping lock", log: log, type: .info)
            transitionToNormal()
            return
        }

        state = .locked
        os_log("State -> Locked", log: log, type: .info)
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
            return L("schedule.disabled")
        }

        let now = Date()
        guard let lockTime = nextLockTime(for: settings, now: now) else {
            return L("schedule.format_error")
        }

        let interval = lockTime.timeIntervalSince(now)
        if interval < 0 {
            return L("schedule.past_time")
        }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 0 {
            return L("schedule.countdown.hours", hours, minutes)
        } else {
            return L("schedule.countdown.minutes", minutes)
        }
    }

    func lockNow() {
        transitionToLocked()
    }
}
