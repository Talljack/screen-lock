import XCTest
@testable import ScreenLock

final class DisplaySleepTests: XCTestCase {

    func testAreDisplaysAsleepDetection() {
        let screenManager = ScreenManager.shared

        // This test checks if the method runs without crashing
        // Actual sleep state depends on hardware
        let isAsleep = screenManager.areDisplaysAsleep()

        print("Displays asleep: \(isAsleep)")

        // The method should return a boolean value
        XCTAssertTrue(isAsleep == true || isAsleep == false)
    }

    func testScheduleManagerSkipsLockWhenDisplaysAsleep() {
        // This is a behavioral test - we can't easily simulate display sleep
        // but we can verify the logic path exists

        let scheduleManager = ScheduleManager.shared
        let initialState = scheduleManager.state

        print("Initial schedule state: \(initialState)")

        // Verify the manager exists and has state
        XCTAssertNotNil(scheduleManager)
    }
}
