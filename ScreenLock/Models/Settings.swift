import Foundation

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
        preventSleepEnabled: true,
        lockEnabled: true,
        forcedBreakMinutes: 15,
        appearance: .default,
        autoStartEnabled: false,
        hasShownPermissionGuide: false,
        language: .auto
    )

    enum CodingKeys: String, CodingKey {
        case lockTime, warningMinutes, preventSleepEnabled, lockEnabled
        case forcedBreakMinutes, appearance, autoStartEnabled, hasShownPermissionGuide
        case language
    }

    init(
        lockTime: String,
        warningMinutes: Int,
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

    func validated() -> Settings {
        Settings(
            lockTime: lockTime,
            warningMinutes: max(1, warningMinutes),
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
