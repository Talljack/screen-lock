import Foundation
import IOKit.pwr_mgt
import os.log

private let log = OSLog(subsystem: "com.yugangcao.screenlock", category: "Power")

class PowerManager {
    static let shared = PowerManager()

    private var preventSleepAssertionID: IOPMAssertionID = 0
    private var isPreventSleepActive = false
    private var lockScreenDisplayAssertionID: IOPMAssertionID = 0
    private var isLockScreenDisplayAssertionActive = false
    private var lockScreenSystemAssertionID: IOPMAssertionID = 0
    private var isLockScreenSystemAssertionActive = false

    private(set) var statusMessage: String?

    private init() {}

    func enablePreventSleep() {
        guard !isPreventSleepActive else { return }

        if createAssertion(
            type: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            name: "ScreenLock - Prevent Sleep When Enabled" as CFString,
            assertionID: &preventSleepAssertionID
        ) {
            isPreventSleepActive = true
            statusMessage = nil
            os_log("Sleep prevention enabled", log: log, type: .info)
        } else {
            statusMessage = L("status.sleep_unavailable")
            os_log("Failed to enable sleep prevention", log: log, type: .error)
        }
    }

    func disablePreventSleep() {
        guard isPreventSleepActive else { return }

        if releaseAssertion(&preventSleepAssertionID) {
            isPreventSleepActive = false
            statusMessage = nil
            os_log("Sleep prevention disabled", log: log, type: .info)
        }
    }

    func enableLockScreenWakefulness() {
        guard !isLockScreenWakefulnessActive else { return }

        let displayAssertionCreated = createAssertion(
            type: kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            name: "ScreenLock - Keep Display Awake During Lock Screen" as CFString,
            assertionID: &lockScreenDisplayAssertionID
        )
        let systemAssertionCreated = createAssertion(
            type: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            name: "ScreenLock - Keep System Awake During Lock Screen" as CFString,
            assertionID: &lockScreenSystemAssertionID
        )

        isLockScreenDisplayAssertionActive = displayAssertionCreated
        isLockScreenSystemAssertionActive = systemAssertionCreated

        if isLockScreenWakefulnessActive {
            os_log(
                "Lock screen wakefulness enabled (display=%{public}@, system=%{public}@)",
                log: log,
                type: .info,
                displayAssertionCreated ? "true" : "false",
                systemAssertionCreated ? "true" : "false"
            )
        } else {
            os_log("Failed to enable lock screen wakefulness", log: log, type: .error)
        }
    }

    func disableLockScreenWakefulness() {
        guard isLockScreenWakefulnessActive else { return }

        if isLockScreenDisplayAssertionActive {
            _ = releaseAssertion(&lockScreenDisplayAssertionID)
            isLockScreenDisplayAssertionActive = false
        }

        if isLockScreenSystemAssertionActive {
            _ = releaseAssertion(&lockScreenSystemAssertionID)
            isLockScreenSystemAssertionActive = false
        }

        os_log("Lock screen wakefulness disabled", log: log, type: .info)
    }

    private var isLockScreenWakefulnessActive: Bool {
        isLockScreenDisplayAssertionActive || isLockScreenSystemAssertionActive
    }

    @discardableResult
    private func createAssertion(
        type: CFString,
        name: CFString,
        assertionID: inout IOPMAssertionID
    ) -> Bool {
        let result = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name,
            &assertionID
        )

        if result != kIOReturnSuccess {
            os_log(
                "Failed to create power assertion %{public}@, error: %d",
                log: log,
                type: .error,
                String(name),
                result
            )
            assertionID = 0
            return false
        }

        return true
    }

    @discardableResult
    private func releaseAssertion(_ assertionID: inout IOPMAssertionID) -> Bool {
        guard assertionID != 0 else { return true }

        let result = IOPMAssertionRelease(assertionID)
        if result != kIOReturnSuccess {
            os_log("Failed to release power assertion, error: %d", log: log, type: .error, result)
            return false
        }

        assertionID = 0
        return true
    }

#if DEBUG
    func debugIsLockScreenWakefulnessActive() -> Bool {
        isLockScreenWakefulnessActive
    }
#endif
}
