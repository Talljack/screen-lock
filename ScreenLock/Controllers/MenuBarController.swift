import Cocoa

class MenuBarController {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    private var countdownMenuItem: NSMenuItem?
    private var statusIndicatorItem: NSMenuItem?
    private var lockTimeMenuItems: [NSMenuItem] = []
    private var warningMenuItems: [NSMenuItem] = []
    private var breakDurationMenuItems: [NSMenuItem] = []
    private var preventSleepItem: NSMenuItem?
    private var lockEnabledItem: NSMenuItem?

    private var currentState: ScheduleState = .normal

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

        // Set initial icon
        if let button = statusItem?.button {
            configureButtonForState(.normal)
            button.toolTip = "ScreenLock - 定时锁屏助手"
            NSLog("Button configured")
        }

        menu = NSMenu()
        menu?.minimumWidth = 280

        // Header with countdown (larger, prominent)
        countdownMenuItem = NSMenuItem()
        countdownMenuItem?.attributedTitle = createCountdownAttributedString("加载中...")
        countdownMenuItem?.isEnabled = false
        menu?.addItem(countdownMenuItem!)

        // Status indicator (subtle, secondary info)
        statusIndicatorItem = NSMenuItem()
        statusIndicatorItem?.attributedTitle = createStatusAttributedString("正常运行")
        statusIndicatorItem?.isEnabled = false
        menu?.addItem(statusIndicatorItem!)

        menu?.addItem(NSMenuItem.separator())

        // Section: 锁屏时间
        let lockTimeSectionItem = NSMenuItem()
        lockTimeSectionItem.attributedTitle = createSectionHeaderAttributedString("锁屏时间")
        lockTimeSectionItem.isEnabled = false
        menu?.addItem(lockTimeSectionItem)

        let times = ["22:00", "23:00", "00:00", "01:00", "02:00"]
        for time in times {
            let item = NSMenuItem(
                title: "  \(time)",
                action: #selector(lockTimeSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = time
            lockTimeMenuItems.append(item)
            menu?.addItem(item)
        }

        // Lock now option
        let lockNowItem = NSMenuItem(
            title: "  立即锁屏",
            action: #selector(lockNow(_:)),
            keyEquivalent: ""
        )
        lockNowItem.target = self
        if #available(macOS 11.0, *) {
            lockNowItem.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        }
        menu?.addItem(lockNowItem)

        menu?.addItem(NSMenuItem.separator())

        // Section: 提前警告
        let warningSectionItem = NSMenuItem()
        warningSectionItem.attributedTitle = createSectionHeaderAttributedString("提前警告")
        warningSectionItem.isEnabled = false
        menu?.addItem(warningSectionItem)

        let durations = [15, 30, 45, 60]
        for duration in durations {
            let item = NSMenuItem(
                title: "  \(duration) 分钟",
                action: #selector(warningDurationSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = duration
            warningMenuItems.append(item)
            menu?.addItem(item)
        }

        menu?.addItem(NSMenuItem.separator())

        // Section: 强制休息时长
        let breakDurationSectionItem = NSMenuItem()
        breakDurationSectionItem.attributedTitle = createSectionHeaderAttributedString("强制休息时长")
        breakDurationSectionItem.isEnabled = false
        menu?.addItem(breakDurationSectionItem)

        let breakDurations = [5, 10, 15, 20, 30]
        for duration in breakDurations {
            let item = NSMenuItem(
                title: "  \(duration) 分钟",
                action: #selector(breakDurationSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = duration
            breakDurationMenuItems.append(item)
            menu?.addItem(item)
        }

        menu?.addItem(NSMenuItem.separator())

        // Prevent sleep toggle
        preventSleepItem = NSMenuItem(
            title: "  合盖不休眠",
            action: #selector(togglePreventSleep(_:)),
            keyEquivalent: ""
        )
        preventSleepItem?.target = self
        menu?.addItem(preventSleepItem!)

        // Lock enabled toggle
        lockEnabledItem = NSMenuItem(
            title: "  启用定时锁屏",
            action: #selector(toggleLockEnabled(_:)),
            keyEquivalent: ""
        )
        lockEnabledItem?.target = self
        menu?.addItem(lockEnabledItem!)

        menu?.addItem(NSMenuItem.separator())

        // Quit with icon
        let quitItem = NSMenuItem(
            title: "  退出",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        if #available(macOS 11.0, *) {
            quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        }
        menu?.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func setupStateObserver() {
        ScheduleManager.shared.onStateChange = { [weak self] state in
            self?.currentState = state
            self?.updateIconForState(state)
            self?.updateStatusIndicator(state)
        }
    }

    private func updateUI() {
        let countdown = ScheduleManager.shared.getTimeUntilLock()
        countdownMenuItem?.attributedTitle = createCountdownAttributedString(countdown)

        let settings = SettingsManager.shared.settings

        // Update checkmarks for lock time
        for item in lockTimeMenuItems {
            if let time = item.representedObject as? String {
                item.state = (time == settings.lockTime) ? .on : .off
            }
        }

        // Update checkmarks for warning duration
        for item in warningMenuItems {
            if let duration = item.representedObject as? Int {
                item.state = (duration == settings.warningMinutes) ? .on : .off
            }
        }

        // Update checkmarks for break duration
        for item in breakDurationMenuItems {
            if let duration = item.representedObject as? Int {
                item.state = (duration == settings.forcedBreakMinutes) ? .on : .off
            }
        }

        // Update prevent sleep toggle
        preventSleepItem?.state = settings.preventSleepEnabled ? .on : .off

        // Update lock enabled toggle
        lockEnabledItem?.state = settings.lockEnabled ? .on : .off

        // Update every minute
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.updateUI()
        }
    }

    private func configureButtonForState(_ state: ScheduleState) {
        guard let button = statusItem?.button else { return }

        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            var symbolName: String

            switch state {
            case .normal:
                symbolName = "moon.stars.fill"
            case .warning:
                symbolName = "exclamationmark.triangle.fill"
            case .locked:
                symbolName = "lock.fill"
            }

            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let configuredImage = image.withSymbolConfiguration(config)
                button.image = configuredImage
                button.title = ""

                // Set tint color based on state
                button.contentTintColor = colorForState(state)
            }
        } else {
            // Fallback for older macOS
            switch state {
            case .normal:
                button.title = "🌙"
            case .warning:
                button.title = "⚠️"
            case .locked:
                button.title = "🔒"
            }
        }
    }

    private func updateIconForState(_ state: ScheduleState) {
        configureButtonForState(state)
    }

    private func updateStatusIndicator(_ state: ScheduleState) {
        let statusText: String
        switch state {
        case .normal:
            statusText = "正常运行"
        case .warning:
            statusText = "即将锁屏"
        case .locked:
            statusText = "已锁定"
        }
        statusIndicatorItem?.attributedTitle = createStatusAttributedString(statusText)
    }

    private func colorForState(_ state: ScheduleState) -> NSColor {
        switch state {
        case .normal:
            return NSColor.systemTeal
        case .warning:
            return NSColor.systemOrange
        case .locked:
            return NSColor.systemRed
        }
    }

    // MARK: - Attributed String Helpers

    private func createCountdownAttributedString(_ text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 2

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]

        return NSAttributedString(string: text, attributes: attributes)
    }

    private func createStatusAttributedString(_ text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]

        return NSAttributedString(string: text, attributes: attributes)
    }

    private func createSectionHeaderAttributedString(_ text: String) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        return NSAttributedString(string: "  \(text)", attributes: attributes)
    }

    // MARK: - Actions

    @objc private func lockTimeSelected(_ sender: NSMenuItem) {
        guard let time = sender.representedObject as? String else { return }
        SettingsManager.shared.updateLockTime(time)
        updateUI()

        // Provide haptic feedback (if available)
        if #available(macOS 10.14, *) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }

        print("Lock time updated to: \(time)")
    }

    @objc private func warningDurationSelected(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? Int else { return }
        SettingsManager.shared.updateWarningMinutes(duration)
        updateUI()

        // Provide haptic feedback (if available)
        if #available(macOS 10.14, *) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }

        print("Warning duration updated to: \(duration) minutes")
    }

    @objc private func breakDurationSelected(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? Int else { return }
        SettingsManager.shared.updateForcedBreakMinutes(duration)
        updateUI()

        if #available(macOS 10.14, *) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }

        print("Break duration updated to: \(duration) minutes")
    }

    @objc private func togglePreventSleep(_ sender: NSMenuItem) {
        SettingsManager.shared.togglePreventSleep()
        updateUI()

        if #available(macOS 10.14, *) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }

        let enabled = SettingsManager.shared.settings.preventSleepEnabled
        print("Prevent sleep: \(enabled ? "enabled" : "disabled")")
    }

    @objc private func toggleLockEnabled(_ sender: NSMenuItem) {
        SettingsManager.shared.toggleLockEnabled()
        updateUI()

        if #available(macOS 10.14, *) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }

        let enabled = SettingsManager.shared.settings.lockEnabled
        print("Lock enabled: \(enabled ? "enabled" : "disabled")")
    }

    @objc private func lockNow(_ sender: NSMenuItem) {
        ScheduleManager.shared.lockNow()

        if #available(macOS 10.14, *) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }

        print("Locking screen now")
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
}
