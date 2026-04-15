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
        return settings
    }

    func save() {
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
}
