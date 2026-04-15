import XCTest
@testable import ScreenLock

final class ScheduleLogicTests: XCTestCase {

    // MARK: - Copy system

    func testEachThemeHasMultipleCopySets() {
        for theme in LockScreenTheme.allCases {
            XCTAssertGreaterThanOrEqual(theme.copySets.count, 3,
                "\(theme.displayName) should have at least 3 copy sets")
        }
    }

    func testDefaultCopyMatchesFirstSet() {
        for theme in LockScreenTheme.allCases {
            let dc = theme.defaultCopy
            let first = theme.copySets[0]
            XCTAssertEqual(dc.title, first.title)
            XCTAssertEqual(dc.subtitle, first.subtitle)
            XCTAssertEqual(dc.footer, first.footer)
        }
    }

    func testRandomCopyNeverReturnsNil() {
        for theme in LockScreenTheme.allCases {
            for _ in 0..<20 {
                let copy = theme.randomCopy()
                XCTAssertFalse(copy.title.isEmpty)
                XCTAssertFalse(copy.subtitle.isEmpty)
                XCTAssertFalse(copy.footer.isEmpty)
            }
        }
    }

    // MARK: - Custom copy flag

    func testWithRandomCopyRespectsCustomFlag() {
        var appearance = LockScreenAppearance.default
        appearance.isCustomCopy = true
        appearance.titleText = "自定义标题"

        let result = appearance.withRandomCopyIfNeeded()
        XCTAssertEqual(result.titleText, "自定义标题",
            "Custom copy should not be overridden by random selection")
    }

    func testWithRandomCopyChangesWhenNotCustom() {
        var appearance = LockScreenAppearance.default
        appearance.isCustomCopy = false

        var gotDifferent = false
        for _ in 0..<50 {
            let result = appearance.withRandomCopyIfNeeded()
            if result.titleText != appearance.titleText {
                gotDifferent = true
                break
            }
        }
        // With 4 options and 50 tries, the chance of never getting different is negligible
        XCTAssertTrue(gotDifferent || LockScreenTheme.peachBunny.copySets.count == 1)
    }

    // MARK: - Settings backward compatibility

    func testDecodesSettingsWithoutNewFields() throws {
        let json = """
        {
          "lockTime": "23:00",
          "warningMinutes": 15,
          "preventSleepEnabled": false,
          "lockEnabled": true,
          "forcedBreakMinutes": 5
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(Settings.self, from: json)

        XCTAssertEqual(settings.autoStartEnabled, false)
        XCTAssertEqual(settings.hasShownPermissionGuide, false)
        XCTAssertEqual(settings.appearance.isCustomCopy, false)
    }

    // MARK: - Appearance validation

    func testValidatedAppearanceFallsBackToThemeDefault() {
        var appearance = LockScreenAppearance(
            theme: .starlightCat,
            titleText: "",
            subtitleText: "  ",
            footerText: "",
            backgroundImagePath: "",
            isCustomCopy: false
        )

        let validated = appearance.validated()
        let expected = LockScreenTheme.starlightCat.defaultCopy

        XCTAssertEqual(validated.titleText, expected.title)
        XCTAssertEqual(validated.subtitleText, expected.subtitle)
        XCTAssertEqual(validated.footerText, expected.footer)
        XCTAssertNil(validated.backgroundImagePath)
    }
}
