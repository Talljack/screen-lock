import XCTest
@testable import ScreenLock

final class StatsManagerTests: XCTestCase {
    func testAverageLockHourUsesConfiguredLockTime() throws {
        let calendar = Calendar(identifier: .gregorian)
        let events = [
            LockEvent(
                date: Date(timeIntervalSince1970: 1_746_043_500),
                lockTime: "23:45",
                trigger: .scheduled,
                breakDurationSeconds: 900,
                completed: true
            )
        ]

        let average = try XCTUnwrap(
            StatsManager.averageLockHour(for: events, calendar: calendar)
        )

        XCTAssertEqual(average, 23.75, accuracy: 0.0001)
    }

    func testPreferredTrendPeriodFallsBackToThirtyDaysWhenSevenDaysIsEmpty() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = Date(timeIntervalSince1970: 1_746_662_400) // 2025-05-08 00:00:00 UTC
        let events = [
            LockEvent(
                date: Date(timeIntervalSince1970: 1_746_014_400), // 2025-04-30 12:00:00 UTC
                lockTime: "23:45",
                trigger: .scheduled,
                breakDurationSeconds: 900,
                completed: true
            )
        ]

        XCTAssertEqual(
            StatsManager.preferredTrendPeriod(for: events, now: now, calendar: calendar),
            30
        )
    }

    func testDailyCountsIncludesCalendarDayBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = Date(timeIntervalSince1970: 1_746_662_400) // 2025-05-08 00:00:00 UTC
        let events = [
            LockEvent(
                date: Date(timeIntervalSince1970: 1_746_000_300), // 2025-04-30 08:05:00 UTC
                lockTime: "23:45",
                trigger: .manual,
                breakDurationSeconds: 900,
                completed: true
            )
        ]

        let counts = StatsManager.dailyCounts(for: events, days: 9, now: now, calendar: calendar)

        XCTAssertEqual(counts.map(\.count).reduce(0, +), 1)
        XCTAssertEqual(counts.first?.count, 1)
    }
}
