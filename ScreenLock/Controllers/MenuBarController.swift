import Cocoa
import Carbon.HIToolbox
import ServiceManagement
import Sparkle
import UniformTypeIdentifiers
import os.log

private let log = OSLog(subsystem: "com.yugangcao.screenlock", category: "MenuBar")

class MenuBarController {
    private let presetBreakDurations = [1, 5, 10, 15, 20, 30]
    private let updater: SPUUpdater

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var refreshTimer: Timer?

    private var countdownMenuItem: NSMenuItem?
    private var statusIndicatorItem: NSMenuItem?
    private var apiStatusItem: NSMenuItem?
    private var lockEnabledItem: NSMenuItem?
    private var lockTimeParentItem: NSMenuItem?
    private var lockTimeMenuItems: [NSMenuItem] = []
    private var customLockTimeItem: NSMenuItem?
    private var warningParentItem: NSMenuItem?
    private var warningMenuItems: [NSMenuItem] = []
    private var breakParentItem: NSMenuItem?
    private var breakDurationMenuItems: [NSMenuItem] = []
    private var customBreakDurationItem: NSMenuItem?
    private var appearanceParentItem: NSMenuItem?
    private var themeMenuItems: [NSMenuItem] = []
    private var backgroundStatusItem: NSMenuItem?
    private var clearBackgroundItem: NSMenuItem?
    private var copyPreviewTitleItem: NSMenuItem?
    private var copyPreviewSubtitleItem: NSMenuItem?
    private var copyPreviewFooterItem: NSMenuItem?
    private var preventSleepItem: NSMenuItem?
    private var autoStartItem: NSMenuItem?
    private var languageParentItem: NSMenuItem?
    private var globalHotkeyRef: EventHotKeyRef?

    private var currentState: ScheduleState = .normal

    init(updater: SPUUpdater) {
        self.updater = updater
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
            button.toolTip = L("menu.title")
        }

        menu = NSMenu()
        menu?.minimumWidth = 280
        setupMenuItems()

        statusItem?.menu = menu
    }

    private func setupMenuItems() {
        // -- Info section --
        countdownMenuItem = NSMenuItem()
        countdownMenuItem?.attributedTitle = createCountdownAttributedString(L("menu.loading"))
        countdownMenuItem?.isEnabled = false
        menu?.addItem(countdownMenuItem!)

        statusIndicatorItem = NSMenuItem()
        statusIndicatorItem?.attributedTitle = createStatusAttributedString(L("menu.status.normal"))
        statusIndicatorItem?.isEnabled = false
        menu?.addItem(statusIndicatorItem!)

        menu?.addItem(.separator())

        // -- Main toggle + lock now --
        lockEnabledItem = NSMenuItem(
            title: L("menu.lock_toggle"),
            action: #selector(toggleLockEnabled(_:)),
            keyEquivalent: ""
        )
        lockEnabledItem?.target = self
        menu?.addItem(lockEnabledItem!)

        let lockNowItem = NSMenuItem(title: L("menu.lock_now"), action: #selector(lockNow(_:)), keyEquivalent: "")
        lockNowItem.target = self
        if #available(macOS 11.0, *) {
            lockNowItem.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        }
        menu?.addItem(lockNowItem)

        menu?.addItem(.separator())

        // -- Schedule submenus --
        lockTimeParentItem = NSMenuItem(title: L("menu.lock_time"), action: nil, keyEquivalent: "")
        lockTimeParentItem?.submenu = buildLockTimeSubmenu()
        menu?.addItem(lockTimeParentItem!)

        warningParentItem = NSMenuItem(title: L("menu.warning"), action: nil, keyEquivalent: "")
        warningParentItem?.submenu = buildWarningSubmenu()
        menu?.addItem(warningParentItem!)

        breakParentItem = NSMenuItem(title: L("menu.break_duration"), action: nil, keyEquivalent: "")
        breakParentItem?.submenu = buildBreakDurationSubmenu()
        menu?.addItem(breakParentItem!)

        menu?.addItem(.separator())

        // -- Appearance submenu --
        appearanceParentItem = NSMenuItem(title: L("menu.appearance"), action: nil, keyEquivalent: "")
        appearanceParentItem?.submenu = buildAppearanceSubmenu()
        menu?.addItem(appearanceParentItem!)

        // -- Toggle items --
        preventSleepItem = NSMenuItem(
            title: L("menu.prevent_sleep"),
            action: #selector(togglePreventSleep(_:)),
            keyEquivalent: ""
        )
        preventSleepItem?.target = self
        menu?.addItem(preventSleepItem!)

        if #available(macOS 13.0, *) {
            autoStartItem = NSMenuItem(
                title: L("menu.auto_start"),
                action: #selector(toggleAutoStart(_:)),
                keyEquivalent: ""
            )
            autoStartItem?.target = self
            menu?.addItem(autoStartItem!)
        }

        languageParentItem = NSMenuItem(title: L("menu.language"), action: nil, keyEquivalent: "")
        languageParentItem?.submenu = buildLanguageSubmenu()
        menu?.addItem(languageParentItem!)

        menu?.addItem(.separator())

        // -- API status (hidden by default) --
        apiStatusItem = NSMenuItem()
        apiStatusItem?.isEnabled = false
        apiStatusItem?.isHidden = true
        menu?.addItem(apiStatusItem!)

        // -- Bottom section --
        let statsItem = NSMenuItem(title: L("menu.stats"), action: #selector(showStats(_:)), keyEquivalent: "")
        statsItem.target = self
        if #available(macOS 11.0, *) {
            statsItem.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil)
        }
        menu?.addItem(statsItem)

        let exportItem = NSMenuItem(title: L("menu.export_csv"), action: #selector(exportCSV(_:)), keyEquivalent: "")
        exportItem.target = self
        menu?.addItem(exportItem)

        let clearStatsItem = NSMenuItem(title: L("menu.clear_stats"), action: #selector(clearStats(_:)), keyEquivalent: "")
        clearStatsItem.target = self
        menu?.addItem(clearStatsItem)

        let checkUpdateItem = NSMenuItem(title: L("menu.check_update"), action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        checkUpdateItem.target = self
        menu?.addItem(checkUpdateItem)

        let aboutItem = NSMenuItem(title: L("menu.about"), action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu?.addItem(aboutItem)

        let quitItem = NSMenuItem(title: L("menu.quit"), action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu?.addItem(quitItem)
    }

    // MARK: - Submenu Builders

    private func buildLockTimeSubmenu() -> NSMenu {
        let sub = NSMenu()
        for time in ["22:00", "23:00", "00:00", "01:00", "02:00"] {
            let item = NSMenuItem(title: time, action: #selector(lockTimeSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = time
            lockTimeMenuItems.append(item)
            sub.addItem(item)
        }
        sub.addItem(.separator())
        customLockTimeItem = NSMenuItem(title: L("menu.custom_time"), action: #selector(customLockTimeSelected(_:)), keyEquivalent: "")
        customLockTimeItem?.target = self
        sub.addItem(customLockTimeItem!)
        return sub
    }

    private func buildWarningSubmenu() -> NSMenu {
        let sub = NSMenu()
        for duration in [5, 10, 15, 30, 45, 60] {
            let item = NSMenuItem(title: L("unit.minutes", duration), action: #selector(warningDurationSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = duration
            warningMenuItems.append(item)
            sub.addItem(item)
        }
        sub.addItem(.separator())
        let customItem = NSMenuItem(title: L("menu.custom"), action: #selector(customWarningDuration(_:)), keyEquivalent: "")
        customItem.target = self
        sub.addItem(customItem)
        return sub
    }

    private func buildBreakDurationSubmenu() -> NSMenu {
        let sub = NSMenu()
        for duration in presetBreakDurations {
            let item = NSMenuItem(title: L("unit.minutes", duration), action: #selector(breakDurationSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = duration
            breakDurationMenuItems.append(item)
            sub.addItem(item)
        }
        sub.addItem(.separator())
        customBreakDurationItem = NSMenuItem(title: L("menu.custom"), action: #selector(customBreakDurationSelected(_:)), keyEquivalent: "")
        customBreakDurationItem?.target = self
        sub.addItem(customBreakDurationItem!)
        return sub
    }

    private func buildLanguageSubmenu() -> NSMenu {
        let sub = NSMenu()
        let currentLang = SettingsManager.shared.settings.language

        for lang in AppLanguage.allCases {
            let item = NSMenuItem(title: lang.displayName, action: #selector(switchLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.tag = AppLanguage.allCases.firstIndex(of: lang) ?? 0
            item.state = (lang == currentLang) ? .on : .off
            sub.addItem(item)
        }

        return sub
    }

    @objc private func switchLanguage(_ sender: NSMenuItem) {
        let allLangs = AppLanguage.allCases
        guard sender.tag >= 0, sender.tag < allLangs.count else { return }
        let selected = allLangs[sender.tag]
        SettingsManager.shared.updateLanguage(selected)

        rebuildMenu()
    }

    private func rebuildMenu() {
        menu?.removeAllItems()
        setupMenuItems()
        updateUI()
    }

    private func buildAppearanceSubmenu() -> NSMenu {
        let sub = NSMenu()

        sub.addItem(makeSectionHeader(L("appearance.theme_section")))
        for theme in LockScreenTheme.allCases {
            let item = NSMenuItem(title: theme.displayName, action: #selector(themeSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = theme.rawValue
            themeMenuItems.append(item)
            sub.addItem(item)
        }

        sub.addItem(.separator())
        sub.addItem(makeSectionHeader(L("appearance.background_section")))

        backgroundStatusItem = NSMenuItem()
        backgroundStatusItem?.isEnabled = false
        sub.addItem(backgroundStatusItem!)

        let chooseItem = NSMenuItem(title: L("appearance.choose_bg"), action: #selector(chooseBackgroundImage(_:)), keyEquivalent: "")
        chooseItem.target = self
        sub.addItem(chooseItem)

        clearBackgroundItem = NSMenuItem(title: L("appearance.use_theme_bg"), action: #selector(clearBackgroundImage(_:)), keyEquivalent: "")
        clearBackgroundItem?.target = self
        sub.addItem(clearBackgroundItem!)

        sub.addItem(.separator())
        sub.addItem(makeSectionHeader(L("appearance.copy_preview")))

        copyPreviewTitleItem = NSMenuItem()
        copyPreviewTitleItem?.isEnabled = false
        sub.addItem(copyPreviewTitleItem!)

        copyPreviewSubtitleItem = NSMenuItem()
        copyPreviewSubtitleItem?.isEnabled = false
        sub.addItem(copyPreviewSubtitleItem!)

        copyPreviewFooterItem = NSMenuItem()
        copyPreviewFooterItem?.isEnabled = false
        sub.addItem(copyPreviewFooterItem!)

        sub.addItem(.separator())

        let editItem = NSMenuItem(title: L("appearance.edit_copy"), action: #selector(editLockScreenCopy(_:)), keyEquivalent: "")
        editItem.target = self
        sub.addItem(editItem)

        let resetItem = NSMenuItem(title: L("appearance.reset_copy"), action: #selector(resetLockScreenAppearance(_:)), keyEquivalent: "")
        resetItem.target = self
        sub.addItem(resetItem)

        sub.addItem(.separator())

        let previewItem = NSMenuItem(title: L("appearance.preview"), action: #selector(showAppearancePreview(_:)), keyEquivalent: "")
        previewItem.target = self
        if #available(macOS 11.0, *) {
            previewItem.image = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: nil)
        }
        sub.addItem(previewItem)

        return sub
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
        let enabled = settings.lockEnabled

        // Main toggle
        lockEnabledItem?.state = enabled ? .on : .off

        // Grey out schedule items when disabled
        lockTimeParentItem?.isEnabled = enabled
        warningParentItem?.isEnabled = enabled
        breakParentItem?.isEnabled = enabled

        // Parent item titles show current values
        lockTimeParentItem?.title = L("menu.lock_time.value", settings.lockTime)
        warningParentItem?.title = L("menu.warning.value", settings.warningMinutes)
        breakParentItem?.title = L("menu.break.value", settings.forcedBreakMinutes)

        // Lock time submenu checks
        let presetTimes = ["22:00", "23:00", "00:00", "01:00", "02:00"]
        let isCustomTime = !presetTimes.contains(settings.lockTime)
        for item in lockTimeMenuItems {
            if let time = item.representedObject as? String {
                item.state = (time == settings.lockTime) ? .on : .off
            }
        }
        customLockTimeItem?.state = isCustomTime ? .on : .off
        customLockTimeItem?.title = isCustomTime ? L("menu.custom_time.value", settings.lockTime) : L("menu.custom_time")

        // Warning submenu checks
        for item in warningMenuItems {
            if let duration = item.representedObject as? Int {
                item.state = (duration == settings.warningMinutes) ? .on : .off
            }
        }

        // Break duration submenu checks
        for item in breakDurationMenuItems {
            if let duration = item.representedObject as? Int {
                item.state = (duration == settings.forcedBreakMinutes) ? .on : .off
            }
        }
        let isCustomBreak = !presetBreakDurations.contains(settings.forcedBreakMinutes)
        customBreakDurationItem?.state = isCustomBreak ? .on : .off
        customBreakDurationItem?.title = isCustomBreak ? L("menu.custom.value", settings.forcedBreakMinutes) : L("menu.custom")

        // Appearance submenu: theme
        let themeName = settings.appearance.theme.displayName
        appearanceParentItem?.title = L("menu.appearance.value", themeName)
        for item in themeMenuItems {
            if let rawValue = item.representedObject as? String {
                item.state = (rawValue == settings.appearance.theme.rawValue) ? .on : .off
            }
        }

        // Appearance submenu: copy preview
        let appearance = settings.appearance
        copyPreviewTitleItem?.attributedTitle = NSAttributedString(
            string: "  「\(appearance.titleText)」",
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]
        )
        copyPreviewSubtitleItem?.attributedTitle = NSAttributedString(
            string: "  \(appearance.subtitleText)",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        copyPreviewFooterItem?.attributedTitle = NSAttributedString(
            string: "  \(appearance.footerText)",
            attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.tertiaryLabelColor]
        )

        // Appearance submenu: background
        if let path = appearance.backgroundImagePath, !path.isEmpty {
            let fileExists = FileManager.default.fileExists(atPath: path)
            if fileExists {
                backgroundStatusItem?.attributedTitle = createStatusAttributedString(
                    L("appearance.current_bg", URL(fileURLWithPath: path).lastPathComponent)
                )
                clearBackgroundItem?.isEnabled = true
                clearBackgroundItem?.title = L("appearance.clear_bg")
            } else {
                SettingsManager.shared.updateBackgroundImagePath(nil)
                backgroundStatusItem?.attributedTitle = createStatusAttributedString(L("appearance.current_theme_bg"))
                clearBackgroundItem?.isEnabled = false
                clearBackgroundItem?.title = L("appearance.use_theme_bg")
            }
        } else {
            backgroundStatusItem?.attributedTitle = createStatusAttributedString(L("appearance.current_theme_bg"))
            clearBackgroundItem?.isEnabled = false
            clearBackgroundItem?.title = L("appearance.use_theme_bg")
        }

        // Toggle states
        preventSleepItem?.state = settings.preventSleepEnabled ? .on : .off
        autoStartItem?.state = settings.autoStartEnabled ? .on : .off
        languageParentItem?.title = L("menu.language.value", settings.language.displayName)

        // API status
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

        switch state {
        case .normal:
            if let img = NSImage(named: "MenuBarIcon") {
                img.isTemplate = false
                button.image = img
                button.title = ""
                button.contentTintColor = nil
            }
        case .warning, .locked:
            if #available(macOS 11.0, *) {
                let symbolName = (state == .warning) ? "sparkles" : "lock.fill"
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                    button.image = image.withSymbolConfiguration(config)
                    button.title = ""
                    button.contentTintColor = colorForState(state)
                }
            } else {
                button.image = nil
                button.title = (state == .warning) ? "✨" : "🔒"
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
            statusText = L("menu.status.normal")
        case .warning:
            statusText = L("menu.status.warning")
        case .locked:
            statusText = L("menu.status.locked")
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
        alert.addButton(withTitle: L("button.save"))
        alert.addButton(withTitle: L("button.cancel"))

        let field = NSTextField(string: "\(initialValue)")
        field.placeholderString = L("custom_time.placeholder")
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

    @objc private func customWarningDuration(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = L("custom_warning.title")
        alert.informativeText = L("custom_warning.message")
        alert.addButton(withTitle: L("button.confirm"))
        alert.addButton(withTitle: L("button.cancel"))

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        input.placeholderString = L("unit.minute_input")
        input.stringValue = "\(SettingsManager.shared.settings.warningMinutes)"
        alert.accessoryView = input

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if let value = Int(input.stringValue), value >= 1, value <= 120 {
            SettingsManager.shared.updateWarningMinutes(value)
            updateUI()
            performFeedback()
        }
    }

    @objc private func breakDurationSelected(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? Int else { return }
        SettingsManager.shared.updateForcedBreakMinutes(duration)
        updateUI()
        performFeedback()
    }

    @objc private func customBreakDurationSelected(_ sender: NSMenuItem) {
        guard let minutes = promptForPositiveInteger(
            title: L("custom_break.title"),
            message: L("custom_break.message"),
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
        panel.prompt = L("bg.choose_title")

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

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = L("copy_editor.title")
        panel.center()
        panel.isReleasedWhenClosed = false

        let content = NSView(frame: panel.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        panel.contentView = content

        let margin: CGFloat = 28
        var y = content.bounds.height

        // Header with icon
        y -= 56
        let headerView = NSView(frame: NSRect(x: 0, y: y, width: content.bounds.width, height: 56))
        headerView.autoresizingMask = [.width]

        let iconView = NSImageView(frame: NSRect(x: margin, y: 8, width: 40, height: 40))
        if let appIcon = NSApp.applicationIconImage {
            iconView.image = appIcon
        }
        headerView.addSubview(iconView)

        let headerTitle = NSTextField(labelWithString: L("copy_editor.title"))
        headerTitle.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        headerTitle.frame = NSRect(x: margin + 50, y: 24, width: 300, height: 22)
        headerView.addSubview(headerTitle)

        let headerSub = NSTextField(labelWithString: L("copy_editor.subtitle"))
        headerSub.font = NSFont.systemFont(ofSize: 12)
        headerSub.textColor = .secondaryLabelColor
        headerSub.frame = NSRect(x: margin + 50, y: 6, width: 300, height: 18)
        headerView.addSubview(headerSub)

        content.addSubview(headerView)

        // Separator
        y -= 1
        let sep = NSBox(frame: NSRect(x: margin, y: y, width: content.bounds.width - margin * 2, height: 1))
        sep.boxType = .separator
        content.addSubview(sep)

        // Field dimensions
        let fieldWidth = content.bounds.width - margin * 2
        let fieldHeight: CGFloat = 28

        // Title field
        y -= 48
        let titleLabel = NSTextField(labelWithString: L("copy_editor.field.title"))
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.frame = NSRect(x: margin, y: y + fieldHeight + 4, width: fieldWidth, height: 16)
        content.addSubview(titleLabel)

        let titleField = NSTextField(string: appearance.titleText)
        titleField.placeholderString = L("copy_editor.field.title_placeholder")
        titleField.font = NSFont.systemFont(ofSize: 14)
        titleField.frame = NSRect(x: margin, y: y, width: fieldWidth, height: fieldHeight)
        content.addSubview(titleField)

        // Subtitle field
        y -= 56
        let subLabel = NSTextField(labelWithString: L("copy_editor.field.subtitle"))
        subLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        subLabel.textColor = .secondaryLabelColor
        subLabel.frame = NSRect(x: margin, y: y + fieldHeight + 4, width: fieldWidth, height: 16)
        content.addSubview(subLabel)

        let subtitleField = NSTextField(string: appearance.subtitleText)
        subtitleField.placeholderString = L("copy_editor.field.subtitle_placeholder")
        subtitleField.font = NSFont.systemFont(ofSize: 14)
        subtitleField.frame = NSRect(x: margin, y: y, width: fieldWidth, height: fieldHeight)
        content.addSubview(subtitleField)

        // Footer field
        y -= 56
        let footerLabel = NSTextField(labelWithString: L("copy_editor.field.footer"))
        footerLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        footerLabel.textColor = .secondaryLabelColor
        footerLabel.frame = NSRect(x: margin, y: y + fieldHeight + 4, width: fieldWidth, height: 16)
        content.addSubview(footerLabel)

        let footerField = NSTextField(string: appearance.footerText)
        footerField.placeholderString = L("copy_editor.field.footer_placeholder")
        footerField.font = NSFont.systemFont(ofSize: 14)
        footerField.frame = NSRect(x: margin, y: y, width: fieldWidth, height: fieldHeight)
        content.addSubview(footerField)

        // Preview label
        y -= 36
        let previewLabel = NSTextField(labelWithString: L("copy_editor.preview"))
        previewLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.frame = NSRect(x: margin, y: y, width: fieldWidth, height: 16)
        content.addSubview(previewLabel)

        // Preview card
        y -= 52
        let previewCard = NSView(frame: NSRect(x: margin, y: y, width: fieldWidth, height: 48))
        previewCard.wantsLayer = true
        previewCard.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        previewCard.layer?.cornerRadius = 10
        previewCard.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        previewCard.layer?.borderWidth = 1
        content.addSubview(previewCard)

        let previewText = NSTextField(labelWithString: "「\(appearance.titleText)」\n\(appearance.subtitleText)")
        previewText.font = NSFont.systemFont(ofSize: 12)
        previewText.textColor = .labelColor
        previewText.maximumNumberOfLines = 2
        previewText.frame = NSRect(x: 12, y: 6, width: fieldWidth - 24, height: 36)
        previewCard.addSubview(previewText)

        // Buttons
        y -= 48
        let saveBtn = NSButton(title: L("button.save"), target: nil, action: nil)
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        saveBtn.frame = NSRect(x: content.bounds.width - margin - 80, y: y, width: 80, height: 32)

        let cancelBtn = NSButton(title: L("button.cancel"), target: nil, action: nil)
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}"
        cancelBtn.frame = NSRect(x: content.bounds.width - margin - 170, y: y, width: 80, height: 32)

        content.addSubview(saveBtn)
        content.addSubview(cancelBtn)

        NSApp.activate(ignoringOtherApps: true)

        saveBtn.target = self
        saveBtn.action = #selector(copyEditorSave(_:))
        cancelBtn.target = self
        cancelBtn.action = #selector(copyEditorCancel(_:))

        copyEditorPanel = panel
        copyEditorFields = (titleField, subtitleField, footerField)

        panel.makeKeyAndOrderFront(nil)
    }

    private var copyEditorPanel: NSPanel?
    private var copyEditorFields: (title: NSTextField, subtitle: NSTextField, footer: NSTextField)?

    @objc private func copyEditorSave(_ sender: NSButton) {
        guard let fields = copyEditorFields else { return }
        SettingsManager.shared.updateLockScreenCopy(
            title: fields.title.stringValue,
            subtitle: fields.subtitle.stringValue,
            footer: fields.footer.stringValue
        )
        SettingsManager.shared.markCopyAsCustom()
        updateUI()
        performFeedback()
        copyEditorPanel?.close()
        copyEditorPanel = nil
        copyEditorFields = nil
    }

    @objc private func copyEditorCancel(_ sender: NSButton) {
        copyEditorPanel?.close()
        copyEditorPanel = nil
        copyEditorFields = nil
    }

    // MARK: - Appearance Preview

    private var previewWindow: NSPanel?

    @objc private func showAppearancePreview(_ sender: NSMenuItem) {
        previewWindow?.close()

        let settings = SettingsManager.shared.settings.validated()
        let appearance = settings.appearance
        let palette = appearance.theme.palette

        let panelW: CGFloat = 480
        let panelH: CGFloat = 420

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelW, height: panelH),
            styleMask: [.titled, .closable, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = L("preview.title", appearance.theme.displayName)
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true

        let root = NSView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
        root.wantsLayer = true
        panel.contentView = root

        // Gradient background mimicking the lock screen
        let bgLayer = CAGradientLayer()
        bgLayer.frame = root.bounds
        bgLayer.colors = palette.gradientColors.map(\.cgColor)
        bgLayer.startPoint = CGPoint(x: 0, y: 1)
        bgLayer.endPoint = CGPoint(x: 1, y: 0)
        root.layer?.addSublayer(bgLayer)

        // Custom background image (if user selected one)
        if let bgPath = appearance.backgroundImagePath, !bgPath.isEmpty,
           let bgImage = NSImage(contentsOfFile: bgPath) {
            let imageView = NSImageView(frame: root.bounds)
            imageView.image = bgImage
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.autoresizingMask = [.width, .height]
            root.addSubview(imageView)
        }

        // Semi-transparent overlay
        let overlay = CALayer()
        overlay.frame = root.bounds
        overlay.backgroundColor = palette.overlayColor.cgColor
        root.layer?.addSublayer(overlay)

        // Card
        let cardW: CGFloat = panelW - 60
        let cardH: CGFloat = panelH - 80
        let cardX: CGFloat = 30
        let cardY: CGFloat = 20

        let card = NSView(frame: NSRect(x: cardX, y: cardY, width: cardW, height: cardH))
        card.wantsLayer = true
        card.layer?.backgroundColor = palette.cardColor.cgColor
        card.layer?.borderColor = palette.cardBorderColor.cgColor
        card.layer?.borderWidth = 1.0
        card.layer?.cornerRadius = 24
        root.addSubview(card)

        // Card content (top-down in flipped coordinates — use manual y positioning)
        var cy = cardH - 24

        // Badge
        let badge = NSTextField(labelWithString: "\(palette.symbol)  \(appearance.theme.displayName)")
        badge.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        badge.textColor = palette.secondaryTextColor
        badge.alignment = .center
        badge.sizeToFit()
        cy -= badge.bounds.height
        badge.frame = NSRect(x: 0, y: cy, width: cardW, height: badge.bounds.height)
        card.addSubview(badge)

        cy -= 12

        // Title
        let titleLabel = NSTextField(labelWithString: appearance.titleText)
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = palette.secondaryTextColor
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 2
        titleLabel.preferredMaxLayoutWidth = cardW - 48
        titleLabel.sizeToFit()
        cy -= titleLabel.bounds.height
        titleLabel.frame = NSRect(x: 24, y: cy, width: cardW - 48, height: titleLabel.bounds.height)
        card.addSubview(titleLabel)

        cy -= 10

        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: appearance.subtitleText)
        subtitleLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = palette.secondaryTextColor.withAlphaComponent(0.85)
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 3
        subtitleLabel.preferredMaxLayoutWidth = cardW - 48
        subtitleLabel.sizeToFit()
        cy -= subtitleLabel.bounds.height
        subtitleLabel.frame = NSRect(x: 24, y: cy, width: cardW - 48, height: subtitleLabel.bounds.height)
        card.addSubview(subtitleLabel)

        cy -= 16

        // Countdown box
        let countdownH: CGFloat = 72
        let countdownW: CGFloat = cardW - 48
        cy -= countdownH

        let countdownBox = NSView(frame: NSRect(x: 24, y: cy, width: countdownW, height: countdownH))
        countdownBox.wantsLayer = true
        countdownBox.layer?.backgroundColor = palette.accentColor.withAlphaComponent(0.12).cgColor
        countdownBox.layer?.cornerRadius = 16
        countdownBox.layer?.borderWidth = 1
        countdownBox.layer?.borderColor = palette.accentColor.withAlphaComponent(0.25).cgColor
        card.addSubview(countdownBox)

        let countdownLabel = NSTextField(labelWithString: "14:59")
        countdownLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 36, weight: .bold)
        countdownLabel.textColor = palette.accentColor
        countdownLabel.alignment = .center
        countdownLabel.sizeToFit()
        countdownLabel.frame = NSRect(
            x: 0,
            y: (countdownH - countdownLabel.bounds.height) / 2,
            width: countdownW,
            height: countdownLabel.bounds.height
        )
        countdownBox.addSubview(countdownLabel)

        cy -= 12

        // Footer
        let footerLabel = NSTextField(labelWithString: appearance.footerText)
        footerLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        footerLabel.textColor = palette.footerTextColor
        footerLabel.alignment = .center
        footerLabel.maximumNumberOfLines = 2
        footerLabel.preferredMaxLayoutWidth = cardW - 48
        footerLabel.sizeToFit()
        cy -= footerLabel.bounds.height
        footerLabel.frame = NSRect(x: 24, y: max(cy, 12), width: cardW - 48, height: footerLabel.bounds.height)
        card.addSubview(footerLabel)

        previewWindow = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
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
        alert.messageText = L("custom_time.title")
        alert.informativeText = L("custom_time.message")
        alert.addButton(withTitle: L("button.save"))
        alert.addButton(withTitle: L("button.cancel"))

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
            err.messageText = L("custom_time.error.title")
            err.informativeText = L("custom_time.error.message")
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
            alert.messageText = L("autostart.error")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }

        updateUI()
        performFeedback()
    }

    private var statsWindow: StatsWindow?

    @objc private func showStats(_ sender: NSMenuItem) {
        if statsWindow == nil {
            statsWindow = StatsWindow()
        }
        statsWindow?.refresh()
        statsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func exportCSV(_ sender: NSMenuItem) {
        let csv = StatsManager.shared.exportCSV()

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "screenlock-stats.csv"
        panel.allowedContentTypes = [.commaSeparatedText]

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = L("export.error")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func checkForUpdates(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        checkForUpdatesViaGitHub()
    }

    private func checkForUpdatesViaGitHub() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let repoURL = "https://api.github.com/repos/Talljack/screen-lock/releases/latest"

        guard let url = URL(string: repoURL) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                let appIcon = NSApp.applicationIconImage

                if let error = error {
                    self?.showUpdateAlert(
                        title: L("update.check_failed"),
                        message: L("update.check_failed.message", error.localizedDescription),
                        icon: appIcon,
                        primaryButton: L("button.ok")
                    )
                    return
                }

                let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0

                guard let data = data, httpStatus == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    self?.showUpdateAlert(
                        title: L("update.up_to_date"),
                        message: L("update.up_to_date.message", currentVersion),
                        icon: appIcon,
                        primaryButton: L("button.ok")
                    )
                    return
                }

                let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                let releaseNotes = json["body"] as? String ?? L("update.no_notes")
                let htmlURL = json["html_url"] as? String ?? ""

                if latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                    let alert = NSAlert()
                    alert.messageText = L("update.new_version", latestVersion)
                    let notes = String(releaseNotes.prefix(500))
                    alert.informativeText = """
                        \(L("update.current_version", currentVersion))
                        \(L("update.latest_version", latestVersion))

                        \(L("update.changelog"))
                        \(notes)
                        """
                    alert.icon = appIcon
                    alert.addButton(withTitle: L("update.install"))
                    alert.addButton(withTitle: L("update.later"))
                    NSApp.activate(ignoringOtherApps: true)
                    let resp = alert.runModal()

                    if resp == .alertFirstButtonReturn {
                        if let downloadURL = URL(string: htmlURL) {
                            NSWorkspace.shared.open(downloadURL)
                        }
                    }
                } else {
                    self?.showUpdateAlert(
                        title: L("update.up_to_date"),
                        message: L("update.up_to_date.message", currentVersion),
                        icon: appIcon,
                        primaryButton: L("button.ok")
                    )
                }
            }
        }.resume()
    }

    private func showUpdateAlert(title: String, message: String, icon: NSImage?, primaryButton: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.icon = icon
        alert.addButton(withTitle: primaryButton)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func clearStats(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = L("clear_stats.title")
        alert.informativeText = L("clear_stats.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("button.clear"))
        alert.addButton(withTitle: L("button.cancel"))

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        StatsManager.shared.clearAllData()
        statsWindow?.refresh()
        performFeedback()
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        let alert = NSAlert()
        alert.messageText = "ScreenLock"
        alert.informativeText = """
            \(L("about.version", version))

            \(L("about.description"))

            \(L("about.hotkey"))
            """
        if let appIcon = NSImage(named: "AppIcon") {
            alert.icon = appIcon
        } else if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }
        alert.addButton(withTitle: L("button.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Global Hotkey (Option+Cmd+L)

    private func registerGlobalHotkey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x534C4B21) // "SLK!"
        hotKeyID.id = 1

        let modifiers: UInt32 = UInt32(cmdKey | optionKey)
        var ref: EventHotKeyRef?

        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_L), modifiers,
            hotKeyID, GetApplicationEventTarget(), 0, &ref
        )

        if status == noErr {
            globalHotkeyRef = ref
            os_log("Global hotkey registered: Opt+Cmd+L", log: log, type: .info)

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
