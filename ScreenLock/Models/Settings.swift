import Foundation

enum SmartSoftnessPreference: String, Codable, CaseIterable {
    case conservative
    case balanced
    case warm

    var defaultBias: Double {
        switch self {
        case .conservative: return 0.2
        case .balanced: return 0.5
        case .warm: return 0.8
        }
    }
}

enum WarningSoftnessLevel: String, Codable, CaseIterable {
    case off
    case smart
    case subtle
    case gentle
    case balanced
    case warm
    case extraWarm

    var displayName: String {
        switch self {
        case .off: return L("softness.off")
        case .smart: return L("softness.smart")
        case .subtle: return L("softness.subtle")
        case .gentle: return L("softness.gentle")
        case .balanced: return L("softness.balanced")
        case .warm: return L("softness.warm")
        case .extraWarm: return L("softness.extra_warm")
        }
    }

    var brightnessReduction: Double {
        switch self {
        case .off: return 0.0
        case .smart: return WarningSoftnessLevel.balanced.brightnessReduction
        case .subtle: return 0.05
        case .gentle: return 0.08
        case .balanced: return 0.12
        case .warm: return 0.16
        case .extraWarm: return 0.20
        }
    }

    var warmthStrength: Double {
        switch self {
        case .off: return 0.0
        case .smart: return WarningSoftnessLevel.balanced.warmthStrength
        case .subtle: return 0.04
        case .gentle: return 0.07
        case .balanced: return 0.10
        case .warm: return 0.13
        case .extraWarm: return 0.16
        }
    }

    var manualStrengthProgress: Float {
        switch self {
        case .off: return 0.0
        case .smart: return WarningSoftnessLevel.balanced.manualStrengthProgress
        case .subtle: return 0.35
        case .gentle: return 0.45
        case .balanced: return 0.55
        case .warm: return 0.65
        case .extraWarm: return 0.75
        }
    }
}

enum LockScreenTheme: String, Codable, CaseIterable {
    case peachBunny
    case cloudPudding
    case starlightCat

    var displayName: String {
        switch self {
        case .peachBunny:  return L("theme.peachBunny")
        case .cloudPudding: return L("theme.cloudPudding")
        case .starlightCat: return L("theme.starlightCat")
        }
    }

    struct CopySet: Equatable {
        let title: String
        let subtitle: String
        let footer: String
    }

    var defaultCopy: CopySet {
        return copySets[0]
    }

    var copySets: [CopySet] {
        switch self {
        case .peachBunny:
            return [
                CopySet(title: L("copy.peach.1.title"),
                        subtitle: L("copy.peach.1.subtitle"),
                        footer: L("copy.peach.1.footer")),
                CopySet(title: L("copy.peach.2.title"),
                        subtitle: L("copy.peach.2.subtitle"),
                        footer: L("copy.peach.2.footer")),
                CopySet(title: L("copy.peach.3.title"),
                        subtitle: L("copy.peach.3.subtitle"),
                        footer: L("copy.peach.3.footer")),
                CopySet(title: L("copy.peach.4.title"),
                        subtitle: L("copy.peach.4.subtitle"),
                        footer: L("copy.peach.4.footer")),
            ]
        case .cloudPudding:
            return [
                CopySet(title: L("copy.cloud.1.title"),
                        subtitle: L("copy.cloud.1.subtitle"),
                        footer: L("copy.cloud.1.footer")),
                CopySet(title: L("copy.cloud.2.title"),
                        subtitle: L("copy.cloud.2.subtitle"),
                        footer: L("copy.cloud.2.footer")),
                CopySet(title: L("copy.cloud.3.title"),
                        subtitle: L("copy.cloud.3.subtitle"),
                        footer: L("copy.cloud.3.footer")),
                CopySet(title: L("copy.cloud.4.title"),
                        subtitle: L("copy.cloud.4.subtitle"),
                        footer: L("copy.cloud.4.footer")),
            ]
        case .starlightCat:
            return [
                CopySet(title: L("copy.star.1.title"),
                        subtitle: L("copy.star.1.subtitle"),
                        footer: L("copy.star.1.footer")),
                CopySet(title: L("copy.star.2.title"),
                        subtitle: L("copy.star.2.subtitle"),
                        footer: L("copy.star.2.footer")),
                CopySet(title: L("copy.star.3.title"),
                        subtitle: L("copy.star.3.subtitle"),
                        footer: L("copy.star.3.footer")),
                CopySet(title: L("copy.star.4.title"),
                        subtitle: L("copy.star.4.subtitle"),
                        footer: L("copy.star.4.footer")),
            ]
        }
    }

    func randomCopy() -> CopySet {
        return copySets.randomElement() ?? defaultCopy
    }
}

struct LockScreenAppearance: Codable, Equatable {
    var theme: LockScreenTheme
    var titleText: String
    var subtitleText: String
    var footerText: String
    var backgroundImagePath: String?
    var isCustomCopy: Bool

    static let `default` = LockScreenAppearance(
        theme: .peachBunny,
        titleText: LockScreenTheme.peachBunny.defaultCopy.title,
        subtitleText: LockScreenTheme.peachBunny.defaultCopy.subtitle,
        footerText: LockScreenTheme.peachBunny.defaultCopy.footer,
        backgroundImagePath: nil,
        isCustomCopy: false
    )

    func validated() -> LockScreenAppearance {
        var a = self

        a.backgroundImagePath = a.backgroundImagePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.backgroundImagePath?.isEmpty == true { a.backgroundImagePath = nil }

        if !a.isCustomCopy {
            let copy = theme.defaultCopy
            a.titleText = copy.title
            a.subtitleText = copy.subtitle
            a.footerText = copy.footer
        } else {
            a.titleText = a.titleText.trimmingCharacters(in: .whitespacesAndNewlines)
            a.subtitleText = a.subtitleText.trimmingCharacters(in: .whitespacesAndNewlines)
            a.footerText = a.footerText.trimmingCharacters(in: .whitespacesAndNewlines)

            let fallback = theme.defaultCopy
            if a.titleText.isEmpty { a.titleText = fallback.title }
            if a.subtitleText.isEmpty { a.subtitleText = fallback.subtitle }
            if a.footerText.isEmpty { a.footerText = fallback.footer }
        }

        return a
    }

    /// Returns an appearance with random copy from the theme pool.
    /// Only randomizes if the user hasn't set custom copy.
    func withRandomCopyIfNeeded() -> LockScreenAppearance {
        guard !isCustomCopy else { return self }
        let copy = theme.randomCopy()
        var a = self
        a.titleText = copy.title
        a.subtitleText = copy.subtitle
        a.footerText = copy.footer
        return a
    }
}

struct Settings: Codable {
    var lockTime: String
    var warningMinutes: Int
    var warningSoftnessLevel: WarningSoftnessLevel
    var smartSoftnessBias: Double
    var preventSleepEnabled: Bool
    var lockEnabled: Bool
    var forcedBreakMinutes: Int
    var appearance: LockScreenAppearance
    var autoStartEnabled: Bool
    var hasShownPermissionGuide: Bool
    var language: AppLanguage

    static let `default` = Settings(
        lockTime: "00:00",
        warningMinutes: 30,
        warningSoftnessLevel: .smart,
        smartSoftnessBias: 0.5,
        preventSleepEnabled: true,
        lockEnabled: true,
        forcedBreakMinutes: 15,
        appearance: .default,
        autoStartEnabled: false,
        hasShownPermissionGuide: false,
        language: .auto
    )

    enum CodingKeys: String, CodingKey {
        case lockTime, warningMinutes, warningSoftnessLevel, smartSoftnessBias, smartSoftnessPreference, preventSleepEnabled, lockEnabled
        case forcedBreakMinutes, appearance, autoStartEnabled, hasShownPermissionGuide
        case language
    }

    init(
        lockTime: String,
        warningMinutes: Int,
        warningSoftnessLevel: WarningSoftnessLevel,
        smartSoftnessBias: Double,
        preventSleepEnabled: Bool,
        lockEnabled: Bool,
        forcedBreakMinutes: Int,
        appearance: LockScreenAppearance,
        autoStartEnabled: Bool = false,
        hasShownPermissionGuide: Bool = false,
        language: AppLanguage = .auto
    ) {
        self.lockTime = lockTime
        self.warningMinutes = warningMinutes
        self.warningSoftnessLevel = warningSoftnessLevel
        self.smartSoftnessBias = smartSoftnessBias
        self.preventSleepEnabled = preventSleepEnabled
        self.lockEnabled = lockEnabled
        self.forcedBreakMinutes = forcedBreakMinutes
        self.appearance = appearance
        self.autoStartEnabled = autoStartEnabled
        self.hasShownPermissionGuide = hasShownPermissionGuide
        self.language = language
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.lockTime = try container.decodeIfPresent(String.self, forKey: .lockTime) ?? Self.default.lockTime
        self.warningMinutes = try container.decodeIfPresent(Int.self, forKey: .warningMinutes)
            ?? Self.default.warningMinutes
        self.warningSoftnessLevel = try container.decodeIfPresent(WarningSoftnessLevel.self, forKey: .warningSoftnessLevel)
            ?? Self.default.warningSoftnessLevel
        self.smartSoftnessBias = try container.decodeIfPresent(Double.self, forKey: .smartSoftnessBias)
            ?? (try container.decodeIfPresent(SmartSoftnessPreference.self, forKey: .smartSoftnessPreference)?.defaultBias)
            ?? Self.default.smartSoftnessBias
        self.preventSleepEnabled = try container.decodeIfPresent(Bool.self, forKey: .preventSleepEnabled)
            ?? Self.default.preventSleepEnabled
        self.lockEnabled = try container.decodeIfPresent(Bool.self, forKey: .lockEnabled)
            ?? Self.default.lockEnabled
        self.forcedBreakMinutes = try container.decodeIfPresent(Int.self, forKey: .forcedBreakMinutes)
            ?? Self.default.forcedBreakMinutes
        self.appearance = try container.decodeIfPresent(LockScreenAppearance.self, forKey: .appearance)
            ?? Self.default.appearance
        self.autoStartEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoStartEnabled)
            ?? Self.default.autoStartEnabled
        self.hasShownPermissionGuide = try container.decodeIfPresent(Bool.self, forKey: .hasShownPermissionGuide)
            ?? Self.default.hasShownPermissionGuide
        self.language = try container.decodeIfPresent(AppLanguage.self, forKey: .language)
            ?? Self.default.language
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(lockTime, forKey: .lockTime)
        try container.encode(warningMinutes, forKey: .warningMinutes)
        try container.encode(warningSoftnessLevel, forKey: .warningSoftnessLevel)
        try container.encode(smartSoftnessBias, forKey: .smartSoftnessBias)
        try container.encode(preventSleepEnabled, forKey: .preventSleepEnabled)
        try container.encode(lockEnabled, forKey: .lockEnabled)
        try container.encode(forcedBreakMinutes, forKey: .forcedBreakMinutes)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(autoStartEnabled, forKey: .autoStartEnabled)
        try container.encode(hasShownPermissionGuide, forKey: .hasShownPermissionGuide)
        try container.encode(language, forKey: .language)
    }

    func validated() -> Settings {
        Settings(
            lockTime: lockTime,
            warningMinutes: max(1, warningMinutes),
            warningSoftnessLevel: warningSoftnessLevel,
            smartSoftnessBias: min(max(smartSoftnessBias, 0.0), 1.0),
            preventSleepEnabled: preventSleepEnabled,
            lockEnabled: lockEnabled,
            forcedBreakMinutes: max(1, forcedBreakMinutes),
            appearance: appearance.validated(),
            autoStartEnabled: autoStartEnabled,
            hasShownPermissionGuide: hasShownPermissionGuide,
            language: language
        )
    }
}
