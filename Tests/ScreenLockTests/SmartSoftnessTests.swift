import XCTest
@testable import ScreenLock

final class SmartSoftnessTests: XCTestCase {
    func testSmartSoftnessProfileIsDaytimeGentlerThanLateNight() {
        let calendar = Calendar(identifier: .gregorian)
        let daytime = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 12, minute: 0))!
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 1, minute: 0))!

        let dayProfile = ScreenManager.shared.debugResolvedSoftnessProfile(for: .smart, now: daytime)
        let nightProfile = ScreenManager.shared.debugResolvedSoftnessProfile(for: .smart, now: lateNight)

        XCTAssertLessThan(dayProfile.brightnessReduction, nightProfile.brightnessReduction)
        XCTAssertLessThan(dayProfile.warmthStrength, nightProfile.warmthStrength)
        XCTAssertLessThan(dayProfile.manualStrengthProgress, nightProfile.manualStrengthProgress)
    }

    func testSmartSoftnessProfileTransitionsSmoothlyThroughEvening() {
        let calendar = Calendar(identifier: .gregorian)
        let evening = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 18, minute: 0))!
        let lateEvening = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 21, minute: 30))!

        let eveningProfile = ScreenManager.shared.debugResolvedSoftnessProfile(for: .smart, now: evening)
        let lateEveningProfile = ScreenManager.shared.debugResolvedSoftnessProfile(for: .smart, now: lateEvening)

        XCTAssertLessThan(eveningProfile.brightnessReduction, lateEveningProfile.brightnessReduction)
        XCTAssertLessThan(eveningProfile.warmthStrength, lateEveningProfile.warmthStrength)
        XCTAssertLessThan(eveningProfile.manualStrengthProgress, lateEveningProfile.manualStrengthProgress)
    }

    func testManualProfilesStayWithinSafeRange() {
        for level in WarningSoftnessLevel.allCases where level != .off {
            let profile = ScreenManager.shared.debugResolvedSoftnessProfile(for: level)

            XCTAssertGreaterThanOrEqual(profile.brightnessReduction, 0.0)
            XCTAssertLessThanOrEqual(profile.brightnessReduction, 0.20)
            XCTAssertGreaterThanOrEqual(profile.warmthStrength, 0.0)
            XCTAssertLessThanOrEqual(profile.warmthStrength, 0.16)
            XCTAssertGreaterThanOrEqual(profile.manualStrengthProgress, 0.0)
            XCTAssertLessThanOrEqual(profile.manualStrengthProgress, 0.75)
        }
    }

    func testSolarSmartProfileIsLighterAtNoonThanAfterSunset() {
        let calendar = Calendar(identifier: .gregorian)
        let noon = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 12, minute: 0))!
        let afterSunset = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 20, minute: 0))!
        let sunrise = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 6, minute: 0))!
        let sunset = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 18, minute: 30))!

        let noonProfile = ScreenManager.shared.debugResolvedSolarSoftnessProfile(
            now: noon,
            sunrise: sunrise,
            sunset: sunset,
            bias: 0.5
        )
        let eveningProfile = ScreenManager.shared.debugResolvedSolarSoftnessProfile(
            now: afterSunset,
            sunrise: sunrise,
            sunset: sunset,
            bias: 0.5
        )

        XCTAssertLessThan(noonProfile.brightnessReduction, eveningProfile.brightnessReduction)
        XCTAssertLessThan(noonProfile.warmthStrength, eveningProfile.warmthStrength)
    }

    func testWarmerPreferenceIncreasesSmartProfileStrength() {
        let calendar = Calendar(identifier: .gregorian)
        let sampleTime = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 21, minute: 0))!
        let sunrise = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 6, minute: 0))!
        let sunset = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 18, minute: 30))!

        let conservative = ScreenManager.shared.debugResolvedSolarSoftnessProfile(
            now: sampleTime,
            sunrise: sunrise,
            sunset: sunset,
            bias: 0.2
        )
        let warmer = ScreenManager.shared.debugResolvedSolarSoftnessProfile(
            now: sampleTime,
            sunrise: sunrise,
            sunset: sunset,
            bias: 0.8
        )

        XCTAssertLessThan(conservative.brightnessReduction, warmer.brightnessReduction)
        XCTAssertLessThan(conservative.warmthStrength, warmer.warmthStrength)
        XCTAssertLessThan(conservative.manualStrengthProgress, warmer.manualStrengthProgress)
    }

    func testMaximumWarmPreferenceStaysReadableButWarmer() {
        let calendar = Calendar(identifier: .gregorian)
        let sampleTime = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 23, minute: 0))!
        let sunrise = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 6, minute: 0))!
        let sunset = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 18, minute: 30))!

        let baseline = ScreenManager.shared.debugResolvedSolarSoftnessProfile(
            now: sampleTime,
            sunrise: sunrise,
            sunset: sunset,
            bias: 0.5
        )
        let maxWarm = ScreenManager.shared.debugResolvedSolarSoftnessProfile(
            now: sampleTime,
            sunrise: sunrise,
            sunset: sunset,
            bias: 1.0
        )

        XCTAssertGreaterThan(maxWarm.warmthStrength, baseline.warmthStrength)
        XCTAssertLessThanOrEqual(maxWarm.warmthStrength, 0.22)
        XCTAssertLessThanOrEqual(maxWarm.brightnessReduction, 0.22)
        XCTAssertLessThanOrEqual(maxWarm.manualStrengthProgress, 0.78)
    }
}
