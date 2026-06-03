import XCTest
@testable import ScreenLock

final class LockLifecycleTests: XCTestCase {
    func testLockScreenWindowTargetsActiveFullscreenSpace() {
        XCTAssertTrue(
            LockScreenWindow.overlayCollectionBehavior.contains(.moveToActiveSpace)
        )
        XCTAssertTrue(
            LockScreenWindow.overlayCollectionBehavior.contains(.fullScreenAuxiliary)
        )
    }

    func testRequestLockActivationPreparesWindowsWhileWaitingForAppActivation() {
        let screenManager = ScreenManager.shared
        screenManager.debugIsAppActiveProvider = { false }
        screenManager.debugConfigureLockState(
            remainingSeconds: 60,
            endsAt: Date().addingTimeInterval(60),
            isLockModeActive: true,
            trigger: .scheduled
        )

        screenManager.debugRequestLockActivationAndPresent()

        XCTAssertTrue(screenManager.debugIsAwaitingLockActivation())
        XCTAssertGreaterThan(screenManager.debugLockWindowCount(), 0)
    }

    override func tearDown() {
        ScreenManager.shared.debugResetLockState()
        super.tearDown()
    }

    func testWakeFinishesExpiredLockSequenceInsteadOfLeavingLockScreenStuck() {
        let screenManager = ScreenManager.shared
        let start = Date()
        let wakeTime = start.addingTimeInterval((15 * 60) + 5)
        var completionCount = 0

        screenManager.debugShouldRecordStatsForCompletedLocks = false
        screenManager.debugConfigureLockState(
            remainingSeconds: 15 * 60,
            endsAt: start.addingTimeInterval(15 * 60),
            isLockModeActive: true,
            trigger: .scheduled,
            scheduledLockTime: "23:50",
            completion: {
                completionCount += 1
            }
        )

        screenManager.debugHandleSystemWake(reason: "test wake after expiry", now: wakeTime)

        XCTAssertEqual(completionCount, 1)
        XCTAssertFalse(screenManager.debugIsLockModeActive())
        XCTAssertEqual(screenManager.debugRemainingLockSeconds(), 0)
    }

    func testWakeBeforeCountdownEndsKeepsLockActiveWithRemainingTime() {
        let screenManager = ScreenManager.shared
        let start = Date()
        let wakeTime = start.addingTimeInterval(60)
        var completionCount = 0

        screenManager.debugShouldRecordStatsForCompletedLocks = false
        screenManager.debugConfigureLockState(
            remainingSeconds: 15 * 60,
            endsAt: start.addingTimeInterval(15 * 60),
            isLockModeActive: true,
            trigger: .manual,
            completion: {
                completionCount += 1
            }
        )

        screenManager.debugHandleSystemWake(reason: "test wake before expiry", now: wakeTime)

        XCTAssertEqual(completionCount, 0)
        XCTAssertTrue(screenManager.debugIsLockModeActive())
        XCTAssertEqual(screenManager.debugRemainingLockSeconds(), 14 * 60)
    }

    func testDisplaySleepThenWakeBeforeCountdownEndsKeepsLockActive() {
        let screenManager = ScreenManager.shared
        let start = Date()
        let sleepTime = start.addingTimeInterval(10)
        let wakeTime = start.addingTimeInterval(60)
        var completionCount = 0

        screenManager.debugShouldRecordStatsForCompletedLocks = false
        screenManager.debugConfigureLockState(
            remainingSeconds: 15 * 60,
            endsAt: start.addingTimeInterval(15 * 60),
            isLockModeActive: true,
            trigger: .manual,
            completion: {
                completionCount += 1
            }
        )

        screenManager.debugHandleSystemInactivityStarted(reason: "test screens slept", now: sleepTime)

        XCTAssertEqual(completionCount, 0)
        XCTAssertTrue(screenManager.debugIsLockModeActive())
        XCTAssertEqual(screenManager.debugRemainingLockSeconds(), 14 * 60 + 50)

        screenManager.debugHandleSystemWake(reason: "test screens woke", now: wakeTime)

        XCTAssertEqual(completionCount, 0)
        XCTAssertTrue(screenManager.debugIsLockModeActive())
        XCTAssertEqual(screenManager.debugRemainingLockSeconds(), 14 * 60)
    }
}
