import XCTest
@testable import ScreenLock

final class AppDelegateTests: XCTestCase {
    func testHandleSettingsChangedReappliesCurrentSoftnessSetting() {
        let appDelegate = AppDelegate()
        let screenManager = ScreenManager.shared
        let originalHandler = screenManager.debugApplyCurrentSoftnessSettingHandler
        var applyCount = 0

        screenManager.debugApplyCurrentSoftnessSettingHandler = {
            applyCount += 1
        }

        defer {
            screenManager.debugApplyCurrentSoftnessSettingHandler = originalHandler
        }

        appDelegate.debugHandleSettingsChanged()

        XCTAssertGreaterThanOrEqual(applyCount, 1)
    }
}
