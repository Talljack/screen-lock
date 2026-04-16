import Foundation
import os.log

private let log = OSLog(subsystem: "com.yugangcao.screenlock", category: "Stats")

class StatsManager {
    static let shared = StatsManager()

    private let fileURL: URL
    private(set) var events: [LockEvent] = []

    var onNewAchievement: ((Achievement) -> Void)?

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("ScreenLock")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.fileURL = appSupport.appendingPathComponent("stats.json")
        self.events = Self.load(from: fileURL)
        os_log("Loaded %d lock events", log: log, type: .info, events.count)
    }

    private static func load(from url: URL) -> [LockEvent] {
        guard let data = try? Data(contentsOf: url),
              let events = try? JSONDecoder().decode([LockEvent].self, from: data) else {
            return []
        }
        return events
    }

    func record(event: LockEvent) {
        let previousStreak = currentStreak
        let previousTotal = events.count
        let previousAchievements = unlockedAchievements

        events.append(event)
        save()

        let newStreak = currentStreak
        let newTotal = events.count
        let newAchievements = unlockedAchievements

        let fresh = newAchievements.filter { new in
            !previousAchievements.contains(where: { $0.id == new.id })
        }
        for a in fresh {
            os_log("Achievement unlocked: %{public}@", log: log, type: .info, a.title)
            onNewAchievement?(a)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: fileURL)
    }

    // MARK: - Stats

    var totalCount: Int { events.count }

    var currentStreak: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let eventDays = Set(events.map { cal.startOfDay(for: $0.date) })

        var streak = 0
        var checkDay = today

        // If no event today yet, start from yesterday
        if !eventDays.contains(today) {
            checkDay = cal.date(byAdding: .day, value: -1, to: today)!
        }

        while eventDays.contains(checkDay) {
            streak += 1
            checkDay = cal.date(byAdding: .day, value: -1, to: checkDay)!
        }

        return streak
    }

    var longestStreak: Int {
        let cal = Calendar.current
        let sortedDays = Set(events.map { cal.startOfDay(for: $0.date) }).sorted()

        guard !sortedDays.isEmpty else { return 0 }

        var longest = 1
        var current = 1

        for i in 1..<sortedDays.count {
            let diff = cal.dateComponents([.day], from: sortedDays[i - 1], to: sortedDays[i]).day ?? 0
            if diff == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }

        return longest
    }

    func averageLockHour(days: Int) -> Double? {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -days, to: Date())!
        let recent = events.filter { $0.date >= cutoff }
        guard !recent.isEmpty else { return nil }

        let totalHours = recent.reduce(0.0) { sum, event in
            let comps = cal.dateComponents([.hour, .minute], from: event.date)
            var hour = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
            if hour < 6 { hour += 24 } // treat 0:00-5:59 as 24:00-29:59 for averaging
            return sum + hour
        }

        var avg = totalHours / Double(recent.count)
        if avg >= 24 { avg -= 24 }
        return avg
    }

    /// Returns (day, count) pairs for the last N days.
    func dailyCounts(days: Int) -> [(date: Date, count: Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        var result: [(date: Date, count: Int)] = []

        for i in (0..<days).reversed() {
            let day = cal.date(byAdding: .day, value: -i, to: today)!
            let dayEnd = cal.date(byAdding: .day, value: 1, to: day)!
            let count = events.filter { $0.date >= day && $0.date < dayEnd }.count
            result.append((date: day, count: count))
        }

        return result
    }

    // MARK: - Weekly Comparison

    /// Returns (thisWeekCount, lastWeekCount)
    var weeklyComparison: (thisWeek: Int, lastWeek: Int) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        let thisMonday = cal.date(byAdding: .day, value: -daysSinceMonday, to: today)!
        let lastMonday = cal.date(byAdding: .day, value: -7, to: thisMonday)!

        let thisWeek = events.filter { $0.date >= thisMonday }.count
        let lastWeek = events.filter { $0.date >= lastMonday && $0.date < thisMonday }.count
        return (thisWeek, lastWeek)
    }

    // MARK: - Trigger Distribution

    var scheduledCount: Int {
        events.filter { $0.trigger == .scheduled }.count
    }

    var manualCount: Int {
        events.filter { $0.trigger == .manual }.count
    }

    var completionRate: Double {
        guard !events.isEmpty else { return 0 }
        let completed = events.filter(\.completed).count
        return Double(completed) / Double(events.count)
    }

    // MARK: - Clear Data

    func clearAllData() {
        events.removeAll()
        save()
        os_log("All stats cleared", log: log, type: .info)
    }

    // MARK: - Achievements

    var unlockedAchievements: [Achievement] {
        let streak = currentStreak
        let total = totalCount

        return Achievement.all.filter { a in
            if a.id.hasPrefix("streak") {
                return streak >= a.requirement
            } else if a.id.hasPrefix("total") {
                return total >= a.requirement
            }
            return false
        }
    }

    // MARK: - Export

    func exportCSV() -> String {
        let formatter = ISO8601DateFormatter()
        var csv = "date,lockTime,trigger,breakDurationSeconds,completed\n"
        for e in events {
            csv += "\(formatter.string(from: e.date)),\(e.lockTime),\(e.trigger.rawValue),\(e.breakDurationSeconds),\(e.completed)\n"
        }
        return csv
    }
}
