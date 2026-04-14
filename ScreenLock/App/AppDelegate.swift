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

        // Enable prevent sleep
        if settings.preventSleepEnabled {
            PowerManager.shared.enablePreventSleep()
            NSLog("Prevent sleep enabled")
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
}
