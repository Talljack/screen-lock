import XCTest
@testable import ScreenLock

final class SettingsDecodingTests: XCTestCase {
    func testDecodesLegacySettingsUsingAppearanceDefaults() throws {
        let legacyJSON = """
        {
          "lockTime": "00:00",
          "warningMinutes": 30,
          "preventSleepEnabled": true,
          "lockEnabled": true,
          "forcedBreakMinutes": 15
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(Settings.self, from: legacyJSON)

        XCTAssertEqual(settings.forcedBreakMinutes, 15)
        XCTAssertEqual(settings.appearance.theme, .peachBunny)
        XCTAssertEqual(settings.appearance.titleText, LockScreenAppearance.default.titleText)
    }

    func testValidatedSettingsClampBreakDurationToAtLeastOneMinute() {
        var settings = Settings.default
        settings.forcedBreakMinutes = 0

        XCTAssertEqual(settings.validated().forcedBreakMinutes, 1)
    }

    func testThemePresetsExposeStableDisplayNames() {
        XCTAssertEqual(LockScreenTheme.allCases.map(\.displayName), [
            "蜜桃兔兔",
            "云朵布丁",
            "星星晚安"
        ])
    }
}
