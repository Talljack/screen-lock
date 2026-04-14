import Foundation
import IOKit.pwr_mgt

class PowerManager {
    static let shared = PowerManager()

    private var assertionID: IOPMAssertionID = 0
    private var isActive = false

    private init() {}

    func enablePreventSleep() {
        guard !isActive else { return }

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "ScreenLock - Prevent Sleep When Lid Closed" as CFString,
            &assertionID
        )

        if result == kIOReturnSuccess {
            isActive = true
            print("PowerManager: Sleep prevention enabled")
        } else {
            print("PowerManager: Failed to enable sleep prevention, error: \(result)")
        }
    }

    func disablePreventSleep() {
        guard isActive else { return }

        let result = IOPMAssertionRelease(assertionID)

        if result == kIOReturnSuccess {
            isActive = false
            assertionID = 0
            print("PowerManager: Sleep prevention disabled")
        } else {
            print("PowerManager: Failed to disable sleep prevention, error: \(result)")
        }
    }
}
