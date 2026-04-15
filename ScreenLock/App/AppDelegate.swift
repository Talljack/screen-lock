import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSLog("applicationWillFinishLaunching called")
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSLog("applicationDidFinishLaunching called")
        let settings = SettingsManager.shared.settings
        NSLog("ScreenLock started")
        NSLog("Lock time: \(settings.lockTime)")
        NSLog("Warning: \(settings.warningMinutes) minutes")

        // Enable prevent sleep if needed
        updatePreventSleep(settings.preventSleepEnabled)

        // Listen for settings changes
        SettingsManager.shared.onSettingsChanged = { [weak self] in
            self?.handleSettingsChanged()
        }

        // Start schedule manager
        ScheduleManager.shared.start()
        NSLog("Schedule manager started")

        // Setup menu bar
        menuBarController = MenuBarController()
        NSLog("Menu bar controller created")
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        ScheduleManager.shared.stop()
        PowerManager.shared.disablePreventSleep()
        ScreenManager.shared.restoreOriginalGamma()
        print("ScreenLock terminated")
    }

    private func handleSettingsChanged() {
        let settings = SettingsManager.shared.settings
        updatePreventSleep(settings.preventSleepEnabled)
        ScheduleManager.shared.checkSchedule()
    }

    private func updatePreventSleep(_ enabled: Bool) {
        if enabled {
            PowerManager.shared.enablePreventSleep()
            NSLog("Prevent sleep enabled")
        } else {
            PowerManager.shared.disablePreventSleep()
            NSLog("Prevent sleep disabled")
        }
    }
}
