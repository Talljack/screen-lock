import XCTest
@testable import ScreenLock

final class PowerManagerTests: XCTestCase {
    override func tearDown() {
        PowerManager.shared.disableLockScreenWakefulness()
        super.tearDown()
    }

    func testLockScreenWakefulnessAssertionLifecycle() {
        let powerManager = PowerManager.shared

        powerManager.disableLockScreenWakefulness()
        XCTAssertFalse(powerManager.debugIsLockScreenWakefulnessActive())

        powerManager.enableLockScreenWakefulness()
        XCTAssertTrue(powerManager.debugIsLockScreenWakefulnessActive())

        powerManager.disableLockScreenWakefulness()
        XCTAssertFalse(powerManager.debugIsLockScreenWakefulnessActive())
    }
}
