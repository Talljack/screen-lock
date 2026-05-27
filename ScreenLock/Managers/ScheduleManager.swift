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
    private let graceWindowSeconds: TimeInterval = 5 * 60

    private var timer: Timer?
    private var handledScheduledOccurrence: Date?
    private(set) var state: ScheduleState = .normal
    var isInWarningState: Bool { state == .warning }

    var onStateChange: ((ScheduleState) -> Void)?

#if DEBUG
    var debugSettingsProvider: (() -> Settings)?
    var debugNowProvider: (() -> Date)?
#endif

    private init() {}

    func start() {
        stop()
        checkSchedule()
        os_log("Started", log: log, type: .info)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        os_log("Stopped", log: log, type: .info)
    }

    func checkSchedule() {
#if DEBUG
        let settings = debugSettingsProvider?() ?? SettingsManager.shared.settings
#else
        let settings = SettingsManager.shared.settings
#endif
        defer { scheduleNextCheck(using: settings) }

        if !settings.lockEnabled {
            handledScheduledOccurrence = nil
            if state != .normal {
                transitionToNormal()
            }
            ScreenManager.shared.applyCurrentSoftnessSetting()
            return
        }

#if DEBUG
        let now = debugNowProvider?() ?? Date()
#else
        let now = Date()
#endif
        let evaluation = evaluateSchedule(
            for: settings,
            relativeTo: now,
            handledScheduledLock: handledScheduledOccurrence
        )

        switch evaluation {
        case .lock(let occurrence):
            if ScreenManager.shared.didSleepThrough(occurrence.lockTime, now: now) {
                os_log("Skipping scheduled lock because the system slept through the lock time", log: log, type: .info)
                handledScheduledOccurrence = occurrence.lockTime
                if state != .normal {
                    transitionToNormal()
                }
                ScreenManager.shared.applyCurrentSoftnessSetting()
                return
            }

            if state != .locked {
                transitionToLocked(
                    trigger: .scheduled,
                    lockTime: occurrence.sourceTime,
                    scheduledOccurrence: occurrence.lockTime
                )
            }
        case .warning(let occurrence):
            let totalWarningInterval = max(Double(settings.warningMinutes) * 60, 1)
            let warningProgress = Float(now.timeIntervalSince(occurrence.warningStart) / totalWarningInterval)

            if state != .warning {
                transitionToWarning(durationMinutes: settings.warningMinutes)
            }
            ScreenManager.shared.refreshWarningDimming(
                progress: warningProgress,
                durationMinutes: settings.warningMinutes,
                softnessLevel: settings.warningSoftnessLevel
            )
        case .inactive:
            if state != .normal {
                ScreenManager.shared.cancelDimming()
                transitionToNormal()
            }
            ScreenManager.shared.applyCurrentSoftnessSetting()
        }
    }

    struct ScheduledOccurrence: Equatable {
        let lockTime: Date
        let sourceTime: String
        let warningStart: Date
        let graceEnd: Date
    }

    enum ScheduleEvaluation: Equatable {
        case inactive
        case warning(ScheduledOccurrence)
        case lock(ScheduledOccurrence)
    }

    func evaluateSchedule(
        for settings: Settings,
        relativeTo now: Date,
        handledScheduledLock: Date? = nil
    ) -> ScheduleEvaluation {
        if let occurrence = activeLockOccurrence(for: settings, relativeTo: now) {
            if handledScheduledLock == occurrence.lockTime {
                return .inactive
            }
            return .lock(occurrence)
        }

        if let occurrence = activeWarningOccurrence(for: settings, relativeTo: now) {
            return .warning(occurrence)
        }

        return .inactive
    }

    /// Used for countdown display and next-check scheduling. Returns the next
    /// future occurrence rather than the currently active lock window.
    func nextOccurrence(for settings: Settings, relativeTo now: Date) -> ScheduledOccurrence? {
        nearbyOccurrences(for: settings, now: now)
            .filter { $0.lockTime >= now }
            .min(by: { $0.lockTime < $1.lockTime })
    }

    private func activeLockOccurrence(for settings: Settings, relativeTo now: Date) -> ScheduledOccurrence? {
        nearbyOccurrences(for: settings, now: now)
            .filter { now >= $0.lockTime && now < $0.graceEnd }
            .max(by: { $0.lockTime < $1.lockTime })
    }

    private func activeWarningOccurrence(for settings: Settings, relativeTo now: Date) -> ScheduledOccurrence? {
        nearbyOccurrences(for: settings, now: now)
            .filter { now >= $0.warningStart && now < $0.lockTime }
            .min(by: { $0.lockTime < $1.lockTime })
    }

    private func nearbyOccurrences(for settings: Settings, now: Date) -> [ScheduledOccurrence] {
        settings.normalizedLockTimes.flatMap { time in
            candidateDates(for: time, relativeTo: now).map { lockTime in
                ScheduledOccurrence(
                    lockTime: lockTime,
                    sourceTime: time,
                    warningStart: lockTime.addingTimeInterval(-Double(settings.warningMinutes) * 60),
                    graceEnd: lockTime.addingTimeInterval(graceWindowSeconds)
                )
            }
        }
    }

    private func candidateDates(for timeString: String, relativeTo now: Date) -> [Date] {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2,
              (0...23).contains(parts[0]),
              (0...59).contains(parts[1]) else { return [] }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = parts[0]
        components.minute = parts[1]
        components.second = 0

        guard let today = calendar.date(from: components) else { return [] }

        return [-1, 0, 1].compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
        }
    }

    private func markScheduledOccurrenceHandled(_ occurrence: Date?) {
        handledScheduledOccurrence = occurrence
    }

    private func clearHandledScheduledOccurrenceIfNeeded(relativeTo now: Date) {
        guard let handledScheduledOccurrence else { return }

        let hasFutureMatch = nearbyOccurrences(for: SettingsManager.shared.settings, now: now)
            .contains { $0.lockTime == handledScheduledOccurrence && now < $0.graceEnd }

        if !hasFutureMatch {
            self.handledScheduledOccurrence = nil
        }
    }

    private func transitionToNormal() {
        clearHandledScheduledOccurrenceIfNeeded(relativeTo: Date())
        state = .normal
        os_log("State -> Normal", log: log, type: .info)
        onStateChange?(.normal)
    }

    private func transitionToWarning(durationMinutes: Int) {
        state = .warning
        os_log("State -> Warning", log: log, type: .info)
        NSSound(named: "Tink")?.play()
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

    private func transitionToLocked(
        trigger: LockEvent.Trigger,
        lockTime: String? = nil,
        scheduledOccurrence: Date? = nil
    ) {
        // Skip lock if displays are already asleep
        if ScreenManager.shared.areDisplaysAsleep() {
            os_log("Displays already asleep, skipping lock", log: log, type: .info)
            if trigger == .scheduled {
                markScheduledOccurrenceHandled(scheduledOccurrence)
            }
            transitionToNormal()
            return
        }

        state = .locked
        os_log("State -> Locked", log: log, type: .info)
        ScreenManager.shared.lockScreenAndTurnOffDisplay(trigger: trigger, lockTime: lockTime) { [weak self] in
            DispatchQueue.main.async {
                if trigger == .scheduled {
                    self?.markScheduledOccurrenceHandled(scheduledOccurrence)
                }
                self?.resumePostLockState()
            }
        }
        onStateChange?(.locked)
    }

    private func resumePostLockState() {
        transitionToNormal()
        checkSchedule()
    }

    func getTimeUntilLock() -> String {
        let settings = SettingsManager.shared.settings

        if !settings.lockEnabled {
            return L("schedule.disabled")
        }

        let now = Date()
        guard let lockTime = nextOccurrence(for: settings, relativeTo: now) else {
            os_log("Invalid lock time format", log: log, type: .error)
            return L("schedule.format_error")
        }

        let interval = lockTime.lockTime.timeIntervalSince(now)
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
        transitionToLocked(trigger: .manual)
    }

    func nextCheckDelay(for settings: Settings, now: Date) -> TimeInterval {
        guard settings.lockEnabled else { return 60.0 }

        if case .inactive = evaluateSchedule(for: settings, relativeTo: now, handledScheduledLock: handledScheduledOccurrence) {
            guard let next = nextOccurrence(for: settings, relativeTo: now) else {
                return 60.0
            }

            let nextWarningStart = next.warningStart
            if now < nextWarningStart {
                return max(1.0, min(60.0, nextWarningStart.timeIntervalSince(now)))
            }

            let nextBoundary = min(nextWarningStart, next.lockTime)
            return max(1.0, min(60.0, nextBoundary.timeIntervalSince(now)))
        } else {
            return 1.0
        }
    }

    private func scheduleNextCheck(using settings: Settings) {
        timer?.invalidate()

        let interval = nextCheckDelay(for: settings, now: Date())
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.checkSchedule()
        }

        if let timer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }
}
