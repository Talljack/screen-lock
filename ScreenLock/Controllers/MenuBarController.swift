import Cocoa

class MenuBarController {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    private var statusMenuItem: NSMenuItem?
    private var lockTimeMenuItem: NSMenuItem?
    private var warningMenuItem: NSMenuItem?

    init() {
        NSLog("MenuBarController init started")
        setupMenuBar()
        NSLog("Menu bar setup complete")
        setupStateObserver()
        updateUI()
    }

    private func setupMenuBar() {
        NSLog("Creating status item...")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.isVisible = true
        NSLog("Status item created: \(statusItem != nil)")

        if let button = statusItem?.button {
            button.title = "🔒"
            button.toolTip = "ScreenLock"
            NSLog("Button title set to lock icon")
        } else {
            NSLog("ERROR: Status item button is nil!")
        }

        menu = NSMenu()

        // Status item
        statusMenuItem = NSMenuItem(title: "加载中...", action: nil, keyEquivalent: "")
        statusMenuItem?.isEnabled = false
        menu?.addItem(statusMenuItem!)

        menu?.addItem(NSMenuItem.separator())

        // Lock time submenu
        lockTimeMenuItem = NSMenuItem(title: "设置锁屏时间", action: nil, keyEquivalent: "")
        let lockTimeMenu = NSMenu()

        let times = ["22:00", "23:00", "00:00", "01:00", "02:00"]
        for time in times {
            let item = NSMenuItem(
                title: time,
                action: #selector(lockTimeSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = time
            lockTimeMenu.addItem(item)
        }

        lockTimeMenuItem?.submenu = lockTimeMenu
        menu?.addItem(lockTimeMenuItem!)

        // Warning duration submenu
        warningMenuItem = NSMenuItem(title: "提前警告时间", action: nil, keyEquivalent: "")
        let warningMenu = NSMenu()

        let durations = [15, 30, 45, 60]
        for duration in durations {
            let item = NSMenuItem(
                title: "\(duration) 分钟",
                action: #selector(warningDurationSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = duration
            warningMenu.addItem(item)
        }

        warningMenuItem?.submenu = warningMenu
        menu?.addItem(warningMenuItem!)

        menu?.addItem(NSMenuItem.separator())

        // Prevent sleep toggle
        let preventSleepItem = NSMenuItem(
            title: "合盖不休眠",
            action: #selector(togglePreventSleep(_:)),
            keyEquivalent: ""
        )
        preventSleepItem.target = self
        preventSleepItem.state = .on // Always on
        preventSleepItem.isEnabled = false // Can't toggle (always on)
        menu?.addItem(preventSleepItem)

        menu?.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "退出 ScreenLock",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu?.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func setupStateObserver() {
        ScheduleManager.shared.onStateChange = { [weak self] state in
            self?.updateIconForState(state)
        }
    }

    private func updateUI() {
        let countdown = ScheduleManager.shared.getTimeUntilLock()
        statusMenuItem?.title = countdown

        let settings = SettingsManager.shared.settings
        lockTimeMenuItem?.title = "设置锁屏时间: \(settings.lockTime)"
        warningMenuItem?.title = "提前警告时间: \(settings.warningMinutes) 分钟"

        // Update every minute
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.updateUI()
        }
    }

    private func updateIconForState(_ state: ScheduleState) {
        guard let button = statusItem?.button else { return }

        if #available(macOS 11.0, *) {
            switch state {
            case .normal:
                if let image = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: nil) {
                    button.image = image
                    button.title = ""
                } else {
                    button.title = "🌙"
                }
            case .warning:
                if let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil) {
                    button.image = image
                    button.title = ""
                } else {
                    button.title = "🟠"
                }
            case .locked:
                if let image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) {
                    button.image = image
                    button.title = ""
                } else {
                    button.title = "🔴"
                }
            }
        } else {
            switch state {
            case .normal:
                button.title = "🌙"
            case .warning:
                button.title = "🟠"
            case .locked:
                button.title = "🔴"
            }
        }
    }

    @objc private func lockTimeSelected(_ sender: NSMenuItem) {
        guard let time = sender.representedObject as? String else { return }
        SettingsManager.shared.updateLockTime(time)
        updateUI()
        print("Lock time updated to: \(time)")
    }

    @objc private func warningDurationSelected(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? Int else { return }
        SettingsManager.shared.updateWarningMinutes(duration)
        updateUI()
        print("Warning duration updated to: \(duration) minutes")
    }

    @objc private func togglePreventSleep(_ sender: NSMenuItem) {
        // Not used - always on
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
}
