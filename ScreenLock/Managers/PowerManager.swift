import Foundation
import IOKit.pwr_mgt
import os.log

private let log = OSLog(subsystem: "com.yugangcao.screenlock", category: "Power")

class PowerManager {
    static let shared = PowerManager()

    private var assertionID: IOPMAssertionID = 0
    private var isActive = false

    private(set) var statusMessage: String?

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
            statusMessage = nil
            os_log("Sleep prevention enabled", log: log, type: .info)
        } else {
            statusMessage = "合盖不休眠功能不可用"
            os_log("Failed to enable sleep prevention, error: %d", log: log, type: .error, result)
        }
    }

    func disablePreventSleep() {
        guard isActive else { return }

        let result = IOPMAssertionRelease(assertionID)

        if result == kIOReturnSuccess {
            isActive = false
            assertionID = 0
            statusMessage = nil
            os_log("Sleep prevention disabled", log: log, type: .info)
        } else {
            os_log("Failed to disable sleep prevention, error: %d", log: log, type: .error, result)
        }
    }
}
