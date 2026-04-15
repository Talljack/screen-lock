import Cocoa
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers
import os.log

private let log = OSLog(subsystem: "com.yugangcao.screenlock", category: "MenuBar")

class MenuBarController {
    private let presetBreakDurations = [1, 5, 10, 15, 20, 30]

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var refreshTimer: Timer?

    private var countdownMenuItem: NSMenuItem?
    private var statusIndicatorItem: NSMenuItem?
    private var apiStatusItem: NSMenuItem?
    private var lockTimeMenuItems: [NSMenuItem] = []
    private var customLockTimeItem: NSMenuItem?
    private var warningMenuItems: [NSMenuItem] = []
    private var breakDurationMenuItems: [NSMenuItem] = []
    private var customBreakDurationItem: NSMenuItem?
    private var themeMenuItems: [NSMenuItem] = []
    private var backgroundStatusItem: NSMenuItem?
    private var clearBackgroundItem: NSMenuItem?
    private var preventSleepItem: NSMenuItem?
    private var lockEnabledItem: NSMenuItem?
    private var autoStartItem: NSMenuItem?
    private var globalHotkeyRef: EventHotKeyRef?

    private var currentState: ScheduleState = .normal

    init() {
        setupMenuBar()
        setupStateObserver()
        startRefreshTimer()
        registerGlobalHotkey()
        syncAutoStartState()
        updateUI()
        os_log("MenuBarController initialized", log: log, type: .info)
    }

    deinit {
        refreshTimer?.invalidate()
        unregisterGlobalHotkey()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.isVisible = true

        if let button = statusItem?.button {
            configureButtonForState(.normal)
            button.toolTip = "ScreenLock - 定时锁屏助手"
        }

        menu = NSMenu()
        menu?.minimumWidth = 320

        countdownMenuItem = NSMenuItem()
        countdownMenuItem?.attributedTitle = createCountdownAttributedString("加载中...")
        countdownMenuItem?.isEnabled = false
        menu?.addItem(countdownMenuItem!)

        statusIndicatorItem = NSMenuItem()
        statusIndicatorItem?.attributedTitle = createStatusAttributedString("正常运行")
        statusIndicatorItem?.isEnabled = false
        menu?.addItem(statusIndicatorItem!)

        menu?.addItem(.separator())

        addLockTimeSection()
        menu?.addItem(.separator())

        addWarningSection()
        menu?.addItem(.separator())

        addBreakDurationSection()
        menu?.addItem(.separator())

        addThemeSection()
        menu?.addItem(.separator())

        addBackgroundSection()
        menu?.addItem(.separator())

        addCopySection()
        menu?.addItem(.separator())

        preventSleepItem = NSMenuItem(
            title: "  合盖不休眠",
            action: #selector(togglePreventSleep(_:)),
            keyEquivalent: ""
        )
        preventSleepItem?.target = self
        menu?.addItem(preventSleepItem!)

        lockEnabledItem = NSMenuItem(
            title: "  启用定时锁屏",
            action: #selector(toggleLockEnabled(_:)),
            keyEquivalent: ""
        )
        lockEnabledItem?.target = self
        menu?.addItem(lockEnabledItem!)

        if #available(macOS 13.0, *) {
            autoStartItem = NSMenuItem(
                title: "  开机自启动",
                action: #selector(toggleAutoStart(_:)),
                keyEquivalent: ""
            )
            autoStartItem?.target = self
            menu?.addItem(autoStartItem!)
        }

        menu?.addItem(.separator())

        apiStatusItem = NSMenuItem()
        apiStatusItem?.isEnabled = false
        apiStatusItem?.isHidden = true
        menu?.addItem(apiStatusItem!)

        let aboutItem = NSMenuItem(
            title: "  关于 ScreenLock",
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu?.addItem(aboutItem)

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

    private func addLockTimeSection() {
        menu?.addItem(makeSectionHeader("锁屏时间"))

        for time in ["22:00", "23:00", "00:00", "01:00", "02:00"] {
            let item = NSMenuItem(title: "  \(time)", action: #selector(lockTimeSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = time
            lockTimeMenuItems.append(item)
            menu?.addItem(item)
        }

        customLockTimeItem = NSMenuItem(
            title: "  自定义时间...",
            action: #selector(customLockTimeSelected(_:)),
            keyEquivalent: ""
        )
        customLockTimeItem?.target = self
        menu?.addItem(customLockTimeItem!)

        let lockNowItem = NSMenuItem(title: "  立即锁屏", action: #selector(lockNow(_:)), keyEquivalent: "")
        lockNowItem.target = self
        if #available(macOS 11.0, *) {
            lockNowItem.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        }
        menu?.addItem(lockNowItem)
    }

    private func addWarningSection() {
        menu?.addItem(makeSectionHeader("提前警告"))

        for duration in [15, 30, 45, 60] {
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
    }

    private func addBreakDurationSection() {
        menu?.addItem(makeSectionHeader("强制休息时长"))

        for duration in presetBreakDurations {
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

        customBreakDurationItem = NSMenuItem(
            title: "  自定义...",
            action: #selector(customBreakDurationSelected(_:)),
            keyEquivalent: ""
        )
        customBreakDurationItem?.target = self
        menu?.addItem(customBreakDurationItem!)
    }

    private func addThemeSection() {
        menu?.addItem(makeSectionHeader("可爱风格"))

        for theme in LockScreenTheme.allCases {
            let item = NSMenuItem(
                title: "  \(theme.displayName)",
                action: #selector(themeSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = theme.rawValue
            themeMenuItems.append(item)
            menu?.addItem(item)
        }
    }

    private func addBackgroundSection() {
        menu?.addItem(makeSectionHeader("背景图"))

        backgroundStatusItem = NSMenuItem()
        backgroundStatusItem?.isEnabled = false
        menu?.addItem(backgroundStatusItem!)

        let chooseItem = NSMenuItem(
            title: "  选择背景图...",
            action: #selector(chooseBackgroundImage(_:)),
            keyEquivalent: ""
        )
        chooseItem.target = self
        menu?.addItem(chooseItem)

        clearBackgroundItem = NSMenuItem(
            title: "  使用主题渐变背景",
            action: #selector(clearBackgroundImage(_:)),
            keyEquivalent: ""
        )
        clearBackgroundItem?.target = self
        menu?.addItem(clearBackgroundItem!)
    }

    private func addCopySection() {
        menu?.addItem(makeSectionHeader("提示文案"))

        let editItem = NSMenuItem(
            title: "  编辑锁屏文案...",
            action: #selector(editLockScreenCopy(_:)),
            keyEquivalent: ""
        )
        editItem.target = self
        menu?.addItem(editItem)

        let resetItem = NSMenuItem(
            title: "  恢复默认风格与文案",
            action: #selector(resetLockScreenAppearance(_:)),
            keyEquivalent: ""
        )
        resetItem.target = self
        menu?.addItem(resetItem)
    }

    private func setupStateObserver() {
        ScheduleManager.shared.onStateChange = { [weak self] state in
            self?.currentState = state
            self?.updateIconForState(state)
            self?.updateStatusIndicator(state)
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        // Refresh every 30 seconds for a more responsive countdown display
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.updateUI()
        }
        RunLoop.current.add(refreshTimer!, forMode: .common)
    }

    private func updateUI() {
        countdownMenuItem?.attributedTitle = createCountdownAttributedString(
            ScheduleManager.shared.getTimeUntilLock()
        )

        let settings = SettingsManager.shared.settings.validated()

        let presetTimes = ["22:00", "23:00", "00:00", "01:00", "02:00"]
        let isCustomTime = !presetTimes.contains(settings.lockTime)

        for item in lockTimeMenuItems {
            if let time = item.representedObject as? String {
                item.state = (time == settings.lockTime) ? .on : .off
            }
        }

        customLockTimeItem?.state = isCustomTime ? .on : .off
        customLockTimeItem?.title = isCustomTime
            ? "  自定义时间 (\(settings.lockTime))"
            : "  自定义时间..."

        for item in warningMenuItems {
            if let duration = item.representedObject as? Int {
                item.state = (duration == settings.warningMinutes) ? .on : .off
            }
        }

        for item in breakDurationMenuItems {
            if let duration = item.representedObject as? Int {
                item.state = (duration == settings.forcedBreakMinutes) ? .on : .off
            }
        }

        let isCustomBreak = !presetBreakDurations.contains(settings.forcedBreakMinutes)
        customBreakDurationItem?.state = isCustomBreak ? .on : .off
        customBreakDurationItem?.title = isCustomBreak
            ? "  自定义 (\(settings.forcedBreakMinutes) 分钟)"
            : "  自定义..."

        for item in themeMenuItems {
            if let rawValue = item.representedObject as? String {
                item.state = (rawValue == settings.appearance.theme.rawValue) ? .on : .off
            }
        }

        if let path = settings.appearance.backgroundImagePath, !path.isEmpty {
            backgroundStatusItem?.attributedTitle = createStatusAttributedString(
                "当前背景：\(URL(fileURLWithPath: path).lastPathComponent)"
            )
            clearBackgroundItem?.isEnabled = true
            clearBackgroundItem?.title = "  使用主题动态背景"
        } else {
            backgroundStatusItem?.attributedTitle = createStatusAttributedString("当前背景：主题动态背景")
            clearBackgroundItem?.isEnabled = false
            clearBackgroundItem?.title = "  使用主题动态背景"
        }

        preventSleepItem?.state = settings.preventSleepEnabled ? .on : .off
        lockEnabledItem?.state = settings.lockEnabled ? .on : .off
        autoStartItem?.state = settings.autoStartEnabled ? .on : .off

        // Show API degradation status
        let warnings = [
            ScreenManager.shared.statusMessage,
            PowerManager.shared.statusMessage,
        ].compactMap { $0 }
        if warnings.isEmpty {
            apiStatusItem?.isHidden = true
        } else {
            apiStatusItem?.isHidden = false
            apiStatusItem?.attributedTitle = createStatusAttributedString(
                "⚠️ " + warnings.joined(separator: " / ")
            )
        }
    }

    private func configureButtonForState(_ state: ScheduleState) {
        guard let button = statusItem?.button else { return }

        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let symbolName: String

            switch state {
            case .normal:
                symbolName = "moon.stars.fill"
            case .warning:
                symbolName = "sparkles"
            case .locked:
                symbolName = "lock.fill"
            }

            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                button.image = image.withSymbolConfiguration(config)
                button.title = ""
                button.contentTintColor = colorForState(state)
            }
        } else {
            switch state {
            case .normal:
                button.title = "🌙"
            case .warning:
                button.title = "✨"
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
            statusText = "可爱提醒已开始"
        case .locked:
            statusText = "强制休息中"
        }
        statusIndicatorItem?.attributedTitle = createStatusAttributedString(statusText)
    }

    private func colorForState(_ state: ScheduleState) -> NSColor {
        switch state {
        case .normal:
            return NSColor.systemTeal
        case .warning:
            return NSColor.systemPink
        case .locked:
            return NSColor.systemOrange
        }
    }

    private func makeSectionHeader(_ text: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = createSectionHeaderAttributedString(text)
        item.isEnabled = false
        return item
    }

    private func createCountdownAttributedString(_ text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 2

        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    private func createStatusAttributedString(_ text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    private func createSectionHeaderAttributedString(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: "  \(text)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
    }

    private func performFeedback() {
        if #available(macOS 10.14, *) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }

    private func promptForPositiveInteger(
        title: String,
        message: String,
        initialValue: Int
    ) -> Int? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(string: "\(initialValue)")
        field.placeholderString = "请输入分钟数"
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        let value = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return value > 0 ? value : nil
    }

    @objc private func lockTimeSelected(_ sender: NSMenuItem) {
        guard let time = sender.representedObject as? String else { return }
        SettingsManager.shared.updateLockTime(time)
        updateUI()
        performFeedback()
    }

    @objc private func warningDurationSelected(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? Int else { return }
        SettingsManager.shared.updateWarningMinutes(duration)
        updateUI()
        performFeedback()
    }

    @objc private func breakDurationSelected(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? Int else { return }
        SettingsManager.shared.updateForcedBreakMinutes(duration)
        updateUI()
        performFeedback()
    }

    @objc private func customBreakDurationSelected(_ sender: NSMenuItem) {
        guard let minutes = promptForPositiveInteger(
            title: "自定义强制休息时长",
            message: "输入你想要的分钟数，测试时可以设为 1 分钟。",
            initialValue: SettingsManager.shared.settings.forcedBreakMinutes
        ) else { return }

        SettingsManager.shared.updateForcedBreakMinutes(minutes)
        updateUI()
        performFeedback()
    }

    @objc private func themeSelected(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let theme = LockScreenTheme(rawValue: rawValue) else {
            return
        }

        SettingsManager.shared.updateLockScreenThemeAndResetCopy(theme)
        updateUI()
        performFeedback()
    }

    @objc private func chooseBackgroundImage(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.png, .jpeg, .heic, .webP]
        } else {
            panel.allowedFileTypes = ["png", "jpg", "jpeg", "heic", "webp"]
        }
        panel.prompt = "选择背景图"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        SettingsManager.shared.updateBackgroundImagePath(url.path)
        updateUI()
        performFeedback()
    }

    @objc private func clearBackgroundImage(_ sender: NSMenuItem) {
        SettingsManager.shared.updateBackgroundImagePath(nil)
        updateUI()
        performFeedback()
    }

    @objc private func editLockScreenCopy(_ sender: NSMenuItem) {
        let appearance = SettingsManager.shared.settings.appearance

        let titleField = NSTextField(string: appearance.titleText)
        titleField.placeholderString = "标题"

        let subtitleField = NSTextField(string: appearance.subtitleText)
        subtitleField.placeholderString = "副标题"

        let footerField = NSTextField(string: appearance.footerText)
        footerField.placeholderString = "底部提示"

        let stack = NSStackView(views: [
            labeledField(title: "标题", field: titleField),
            labeledField(title: "副标题", field: subtitleField),
            labeledField(title: "底部提示", field: footerField)
        ])
        stack.orientation = .vertical
        stack.spacing = 10

        let alert = NSAlert()
        alert.messageText = "编辑锁屏文案"
        alert.informativeText = "可以自由改成更可爱的提醒语。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.accessoryView = stack

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        SettingsManager.shared.updateLockScreenCopy(
            title: titleField.stringValue,
            subtitle: subtitleField.stringValue,
            footer: footerField.stringValue
        )
        SettingsManager.shared.markCopyAsCustom()
        updateUI()
        performFeedback()
    }

    private func labeledField(title: String, field: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        let container = NSStackView(views: [label, field])
        container.orientation = .vertical
        container.spacing = 4
        return container
    }

    @objc private func resetLockScreenAppearance(_ sender: NSMenuItem) {
        SettingsManager.shared.resetCopyToThemeDefault()
        updateUI()
        performFeedback()
    }

    @objc private func togglePreventSleep(_ sender: NSMenuItem) {
        SettingsManager.shared.togglePreventSleep()
        updateUI()
        performFeedback()
    }

    @objc private func toggleLockEnabled(_ sender: NSMenuItem) {
        SettingsManager.shared.toggleLockEnabled()
        updateUI()
        performFeedback()
    }

    @objc private func customLockTimeSelected(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "自定义锁屏时间"
        alert.informativeText = "输入 24 小时制时间，格式：HH:mm（例如 23:30）"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(string: SettingsManager.shared.settings.lockTime)
        field.placeholderString = "HH:mm"
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let input = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = input.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else {
            let err = NSAlert()
            err.messageText = "时间格式错误"
            err.informativeText = "请输入有效的 HH:mm 格式，例如 23:30"
            err.runModal()
            return
        }

        let formatted = String(format: "%02d:%02d", parts[0], parts[1])
        SettingsManager.shared.updateLockTime(formatted)
        updateUI()
        performFeedback()
    }

    @objc private func lockNow(_ sender: NSMenuItem) {
        ScheduleManager.shared.lockNow()
        performFeedback()
    }

    @available(macOS 13.0, *)
    @objc private func toggleAutoStart(_ sender: NSMenuItem) {
        let settings = SettingsManager.shared.settings
        let newValue = !settings.autoStartEnabled

        do {
            if newValue {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            SettingsManager.shared.updateAutoStart(newValue)
        } catch {
            let alert = NSAlert()
            alert.messageText = "设置开机自启动失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }

        updateUI()
        performFeedback()
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        let alert = NSAlert()
        alert.messageText = "ScreenLock"
        alert.informativeText = """
            版本 \(version) (\(build))

            可爱的定时锁屏助手，帮你养成健康的睡眠习惯。

            全局快捷键：⌃⌥⌘L 立即锁屏
            """
        alert.addButton(withTitle: "好的")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Global Hotkey (Ctrl+Option+Cmd+L)

    private func registerGlobalHotkey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x534C4B21) // "SLK!"
        hotKeyID.id = 1

        // kVK_ANSI_L = 0x25
        let modifiers: UInt32 = UInt32(cmdKey | optionKey | controlKey)
        var ref: EventHotKeyRef?

        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_L), modifiers,
            hotKeyID, GetApplicationEventTarget(), 0, &ref
        )

        if status == noErr {
            globalHotkeyRef = ref
            os_log("Global hotkey registered: Ctrl+Opt+Cmd+L", log: log, type: .info)

            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
                ScheduleManager.shared.lockNow()
                return noErr
            }, 1, &eventType, nil, nil)
        } else {
            os_log("Failed to register global hotkey: %d", log: log, type: .error, status)
        }
    }

    private func unregisterGlobalHotkey() {
        if let ref = globalHotkeyRef {
            UnregisterEventHotKey(ref)
            globalHotkeyRef = nil
        }
    }

    // MARK: - Auto-Start Sync

    private func syncAutoStartState() {
        if #available(macOS 13.0, *) {
            let systemStatus = SMAppService.mainApp.status
            let settingsEnabled = SettingsManager.shared.settings.autoStartEnabled
            let actuallyEnabled = (systemStatus == .enabled)

            if settingsEnabled != actuallyEnabled {
                SettingsManager.shared.updateAutoStart(actuallyEnabled)
                os_log("Synced auto-start state: %{public}@", log: log, type: .info,
                       actuallyEnabled ? "enabled" : "disabled")
            }
        }
    }
}
