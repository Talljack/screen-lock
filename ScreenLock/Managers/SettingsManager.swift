import Foundation

class SettingsManager {
    static let shared = SettingsManager()

    private let fileURL: URL
    private(set) var settings: Settings

    var onSettingsChanged: (() -> Void)?

    private init() {
        // Get Application Support directory
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let appDirectory = appSupport.appendingPathComponent("ScreenLock")

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: appDirectory,
            withIntermediateDirectories: true
        )

        self.fileURL = appDirectory.appendingPathComponent("settings.json")
        self.settings = Self.loadSettings(from: fileURL)
    }

    private static func loadSettings(from url: URL) -> Settings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings.default
        }
        return settings.validated()
    }

    func save() {
        settings = settings.validated()
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: fileURL)
        onSettingsChanged?()
    }

    func updateLockTime(_ time: String) {
        settings.lockTime = time
        save()
    }

    func updateWarningMinutes(_ minutes: Int) {
        settings.warningMinutes = minutes
        save()
    }

    func togglePreventSleep() {
        settings.preventSleepEnabled.toggle()
        save()
    }

    func toggleLockEnabled() {
        settings.lockEnabled.toggle()
        save()
    }

    func updateForcedBreakMinutes(_ minutes: Int) {
        settings.forcedBreakMinutes = minutes
        save()
    }

    func updateLockScreenTheme(_ theme: LockScreenTheme) {
        settings.appearance.theme = theme
        save()
    }

    func updateBackgroundImagePath(_ path: String?) {
        settings.appearance.backgroundImagePath = path
        save()
    }

    func updateLockScreenCopy(title: String, subtitle: String, footer: String) {
        settings.appearance.titleText = title
        settings.appearance.subtitleText = subtitle
        settings.appearance.footerText = footer
        save()
    }

    func resetLockScreenAppearance() {
        settings.appearance = .default
        save()
    }

    func updateAutoStart(_ enabled: Bool) {
        settings.autoStartEnabled = enabled
        save()
    }

    func markPermissionGuideShown() {
        settings.hasShownPermissionGuide = true
        save()
    }

    func updateLockScreenThemeAndResetCopy(_ theme: LockScreenTheme) {
        settings.appearance.theme = theme
        if !settings.appearance.isCustomCopy {
            let copy = theme.defaultCopy
            settings.appearance.titleText = copy.title
            settings.appearance.subtitleText = copy.subtitle
            settings.appearance.footerText = copy.footer
        }
        save()
    }

    func markCopyAsCustom() {
        settings.appearance.isCustomCopy = true
        save()
    }

    func resetCopyToThemeDefault() {
        let copy = settings.appearance.theme.defaultCopy
        settings.appearance.titleText = copy.title
        settings.appearance.subtitleText = copy.subtitle
        settings.appearance.footerText = copy.footer
        settings.appearance.isCustomCopy = false
        save()
    }

    func updateLanguage(_ language: AppLanguage) {
        settings.language = language
        LanguageManager.shared.applyLanguage(language)
        save()
    }

    func applyStoredLanguage() {
        LanguageManager.shared.applyLanguage(settings.language)
    }
}
