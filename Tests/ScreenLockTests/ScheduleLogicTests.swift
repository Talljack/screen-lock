import XCTest
@testable import ScreenLock

final class ScheduleLogicTests: XCTestCase {
    func testNextCheckDelayAlignsToWarningBoundaryBeforeWarningStarts() {
        let manager = ScheduleManager.shared
        var settings = Settings.default
        settings.lockEnabled = true
        settings.lockTime = "10:28"
        settings.warningMinutes = 1

        let now = Calendar.current.date(from: DateComponents(
            year: 2026, month: 5, day: 9, hour: 10, minute: 26, second: 5
        ))!

        XCTAssertEqual(manager.nextCheckDelay(for: settings, now: now), 55, accuracy: 0.1)
    }

    func testNextCheckDelayPollsEverySecondDuringWarningWindow() {
        let manager = ScheduleManager.shared
        var settings = Settings.default
        settings.lockEnabled = true
        settings.lockTime = "10:28"
        settings.warningMinutes = 1

        let now = Calendar.current.date(from: DateComponents(
            year: 2026, month: 5, day: 9, hour: 10, minute: 27, second: 30
        ))!

        XCTAssertEqual(manager.nextCheckDelay(for: settings, now: now), 1, accuracy: 0.1)
    }

    func testSleepTransitionStateDetectsLockWasMissedDuringSleep() {
        let lockMoment = Date(timeIntervalSince1970: 1_000)
        let state = ScreenManager.SleepTransitionState(
            inactiveSince: Date(timeIntervalSince1970: 900),
            lastWakeAt: Date(timeIntervalSince1970: 1_100)
        )

        XCTAssertTrue(state.crossed(lockMoment, now: Date(timeIntervalSince1970: 1_100)))
    }

    func testSleepTransitionStateIgnoresSleepThatStartedAfterLockTime() {
        let lockMoment = Date(timeIntervalSince1970: 1_000)
        let state = ScreenManager.SleepTransitionState(
            inactiveSince: Date(timeIntervalSince1970: 1_050),
            lastWakeAt: Date(timeIntervalSince1970: 1_100)
        )

        XCTAssertFalse(state.crossed(lockMoment, now: Date(timeIntervalSince1970: 1_100)))
    }

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
        XCTAssertEqual(settings.warningSoftnessLevel, .smart)
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

    func testResolvedBackgroundImageReturnsNilForMissingFile() {
        let appearance = LockScreenAppearance(
            theme: .peachBunny,
            titleText: "t",
            subtitleText: "s",
            footerText: "f",
            backgroundImagePath: "/tmp/does-not-exist-screen-lock-test.png",
            isCustomCopy: true
        )

        XCTAssertNil(appearance.resolvedBackgroundImage())
    }

    func testValidatedSettingsPreserveWarningSoftnessLevel() {
        var settings = Settings.default
        settings.warningSoftnessLevel = .warm

        XCTAssertEqual(settings.validated().warningSoftnessLevel, .warm)
    }
}
