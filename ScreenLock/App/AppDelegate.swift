import Cocoa
import Sparkle
import UserNotifications
import os.log

private let log = OSLog(subsystem: "com.yugangcao.screenlock", category: "App")

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    let updaterController: SPUStandardUpdaterController

    override init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {}

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let settings = SettingsManager.shared.settings
        os_log("ScreenLock started — lock: %{public}@, warning: %d min",
               log: log, type: .info, settings.lockTime, settings.warningMinutes)

        updatePreventSleep(settings.preventSleepEnabled)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            os_log("Notification permission: %{public}@", log: log, type: .info, granted ? "granted" : "denied")
        }

        SettingsManager.shared.onSettingsChanged = { [weak self] in
            self?.handleSettingsChanged()
        }

        SettingsManager.shared.applyStoredLanguage()

        ScheduleManager.shared.start()
        menuBarController = MenuBarController(updater: updaterController.updater)

        StatsManager.shared.onNewAchievement = { achievement in
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = L("achievement.unlocked", achievement.emoji)
                alert.informativeText = "\(achievement.title) — \(achievement.description)"
                alert.addButton(withTitle: L("achievement.awesome"))
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }

        showPermissionGuideIfNeeded()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        ScheduleManager.shared.stop()
        PowerManager.shared.disablePreventSleep()
        ScreenManager.shared.restoreOriginalGamma()
        os_log("ScreenLock terminated", log: log, type: .info)
    }

    private func handleSettingsChanged() {
        let settings = SettingsManager.shared.settings
        updatePreventSleep(settings.preventSleepEnabled)
        ScheduleManager.shared.checkSchedule()
    }

    private func updatePreventSleep(_ enabled: Bool) {
        if enabled {
            PowerManager.shared.enablePreventSleep()
        } else {
            PowerManager.shared.disablePreventSleep()
        }
    }

    private func showPermissionGuideIfNeeded() {
        let settings = SettingsManager.shared.settings
        guard !settings.hasShownPermissionGuide else { return }

        let trusted = AXIsProcessTrusted()
        if !trusted {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = L("permission.title")
                alert.informativeText = L("permission.message")
                alert.addButton(withTitle: L("permission.open_settings"))
                alert.addButton(withTitle: L("permission.later"))

                NSApp.activate(ignoringOtherApps: true)
                let response = alert.runModal()

                if response == .alertFirstButtonReturn {
                    let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                    )!
                    NSWorkspace.shared.open(url)
                }
            }
        }

        SettingsManager.shared.markPermissionGuideShown()
    }
}
