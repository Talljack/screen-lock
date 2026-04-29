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
        XCTAssertEqual(settings.warningSoftnessLevel, .smart)
        XCTAssertEqual(settings.smartSoftnessBias, 0.5, accuracy: 0.0001)
        XCTAssertEqual(settings.appearance.theme, .peachBunny)
        XCTAssertEqual(settings.appearance.titleText, LockScreenAppearance.default.titleText)
    }

    func testValidatedSettingsClampBreakDurationToAtLeastOneMinute() {
        var settings = Settings.default
        settings.forcedBreakMinutes = 0

        XCTAssertEqual(settings.validated().forcedBreakMinutes, 1)
    }

    func testThemePresetsExposeNonEmptyDisplayNames() {
        let names = LockScreenTheme.allCases.map(\.displayName)
        XCTAssertEqual(names.count, 3)
        for name in names {
            XCTAssertFalse(name.isEmpty)
        }
    }

    func testWarningSoftnessLevelsExposeDisplayNames() {
        let levels = WarningSoftnessLevel.allCases
        XCTAssertEqual(levels.count, 7)
        for level in levels {
            XCTAssertFalse(level.displayName.isEmpty)
        }
    }

    func testLegacySmartPreferenceMigratesToBias() throws {
        let legacyJSON = """
        {
          "warningSoftnessLevel": "smart",
          "smartSoftnessPreference": "warm"
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(Settings.self, from: legacyJSON)

        XCTAssertEqual(settings.smartSoftnessBias, 0.8, accuracy: 0.0001)
    }

    func testValidatedSettingsClampSmartBiasIntoSafeRange() {
        var settings = Settings.default
        settings.smartSoftnessBias = 1.8

        XCTAssertEqual(settings.validated().smartSoftnessBias, 1.0, accuracy: 0.0001)
    }
}
