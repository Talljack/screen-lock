import Cocoa

private enum ButtonTone {
    case primary
    case secondary
    case destructive
    case ghost
}

final class LockTimeEditorWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private var times: [String]
    private let onSave: ([String]) -> Void

    private let tableView = TimeListTableView()
    private let timeField = TimeSelectionField()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let selectedLabel = NSTextField(labelWithString: "")
    private let helperLabel = NSTextField(labelWithString: "")
    private let listCountLabel = NSTextField(labelWithString: "")
    private let emptyStateLabel = NSTextField(labelWithString: "")
    private let previewTimeLabel = NSTextField(labelWithString: "")
    private let previewCaptionLabel = NSTextField(labelWithString: "")
    private let emptyAddButton = PillActionControl(title: L("menu.add_lock_time"), symbol: "plus", tone: .secondary)
    private let addButton = PillActionControl(title: L("menu.add_lock_time"), symbol: "plus", tone: .secondary)
    private let updateButton = PillActionControl(title: L("menu.update_lock_time"), symbol: "arrow.clockwise", tone: .secondary)
    private let removeButton = PillActionControl(title: L("menu.remove_lock_time"), symbol: "trash", tone: .destructive)
    private let cancelButton = PillActionControl(title: L("button.cancel"), symbol: "xmark", tone: .ghost)
    private let saveButton = PillActionControl(title: L("button.save"), symbol: "checkmark", tone: .primary)
    private let pickerPopover = TimePickerPopoverController()
    private var pickerDate = Date()

    init(times: [String], onSave: @escaping ([String]) -> Void) {
        self.times = Settings.normalizeLockTimes(times)
        if self.times.isEmpty {
            self.times = Settings.default.lockTimes
        }
        self.onSave = onSave

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = L("lock_time_editor.title")
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.toolbarStyle = .unifiedCompact
        panel.center()

        super.init(window: panel)
        panel.delegate = self
        configureUI(in: panel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: window)
    }

    #if DEBUG
    func debugExportSnapshot(to url: URL) {
        guard let window else { return }
        window.layoutIfNeeded()
        window.displayIfNeeded()
        guard let image = window.contentView?.snapshotImage() else { return }
        guard let tiffData = image.tiffRepresentation else { return }
        guard let rep = NSBitmapImageRep(data: tiffData) else { return }
        guard let pngData = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { return }
        try? pngData.write(to: url)
    }

    func debugOpenTimePicker() {
        timeField.onOpen?()
    }

    func debugExportTimePickerSnapshot(to url: URL) {
        pickerPopover.debugExportSnapshot(to: url)
    }
    #endif

    func windowWillClose(_ notification: Notification) {
        if NSApp.modalWindow === window {
            NSApp.stopModal()
        }
    }

    private func configureUI(in window: NSWindow) {
        guard let root = window.contentView else { return }
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let shell = NSVisualEffectView()
        shell.translatesAutoresizingMaskIntoConstraints = false
        shell.material = .windowBackground
        shell.blendingMode = .behindWindow
        shell.state = .active
        shell.wantsLayer = true
        shell.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.addSubview(shell)

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 16
        shell.addSubview(stack)

        NSLayoutConstraint.activate([
            shell.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            shell.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            shell.topAnchor.constraint(equalTo: root.topAnchor),
            shell.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: shell.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: shell.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: shell.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: shell.bottomAnchor, constant: -20)
        ])

        stack.addArrangedSubview(buildHeader())
        stack.addArrangedSubview(buildBody())
        stack.addArrangedSubview(buildFooter())

        reloadTable(selectRow: 0)
        updateUIState()
    }

    private func buildHeader() -> NSView {
        let iconContainer = NSView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.wantsLayer = true
        iconContainer.layer?.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.92, alpha: 1).cgColor
        iconContainer.layer?.cornerRadius = 18
        iconContainer.layer?.cornerCurve = .continuous
        iconContainer.layer?.borderWidth = 1
        iconContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor

        let icon = NSImageView(image: NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: nil) ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        icon.contentTintColor = NSColor(calibratedRed: 0.93, green: 0.60, blue: 0.24, alpha: 1)
        iconContainer.addSubview(icon)

        let eyebrow = NSTextField(labelWithString: L("lock_time_editor.header.eyebrow"))
        eyebrow.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        eyebrow.textColor = NSColor.secondaryLabelColor

        let title = NSTextField(labelWithString: L("lock_time_editor.title"))
        title.font = NSFont.systemFont(ofSize: 32, weight: .bold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: L("lock_time_editor.message"))
        subtitle.font = NSFont.systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2

        let titleStack = NSStackView(views: [eyebrow, title, subtitle])
        titleStack.orientation = .vertical
        titleStack.spacing = 6
        titleStack.alignment = .leading

        let leading = NSStackView(views: [iconContainer, titleStack])
        leading.orientation = .horizontal
        leading.spacing = 16
        leading.alignment = .top

        summaryLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        summaryLabel.textColor = NSColor(calibratedRed: 0.35, green: 0.42, blue: 0.58, alpha: 1)
        summaryLabel.alignment = .center

        let summaryPill = NSView()
        summaryPill.translatesAutoresizingMaskIntoConstraints = false
        summaryPill.wantsLayer = true
        summaryPill.layer?.backgroundColor = NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.99, alpha: 1).cgColor
        summaryPill.layer?.cornerRadius = 999
        summaryPill.layer?.cornerCurve = .continuous
        summaryPill.layer?.borderWidth = 1
        summaryPill.layer?.borderColor = NSColor(calibratedRed: 0.84, green: 0.88, blue: 0.95, alpha: 1).cgColor
        summaryPill.addSubview(summaryLabel)

        let header = NSStackView(views: [leading, NSView(), summaryPill])
        header.orientation = .horizontal
        header.spacing = 16
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        wrapper.layer?.cornerRadius = 24
        wrapper.layer?.cornerCurve = .continuous
        wrapper.layer?.borderWidth = 1
        wrapper.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        wrapper.addSubview(header)

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 56),
            iconContainer.heightAnchor.constraint(equalToConstant: 56),
            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            header.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),
            header.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 20),
            header.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -20),
            summaryLabel.leadingAnchor.constraint(equalTo: summaryPill.leadingAnchor, constant: 12),
            summaryLabel.trailingAnchor.constraint(equalTo: summaryPill.trailingAnchor, constant: -12),
            summaryLabel.topAnchor.constraint(equalTo: summaryPill.topAnchor, constant: 7),
            summaryLabel.bottomAnchor.constraint(equalTo: summaryPill.bottomAnchor, constant: -7)
        ])

        return wrapper
    }

    private func buildBody() -> NSView {
        let splitView = NSSplitView()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let listPane = buildListPane()
        let editorPane = buildEditorPane()
        splitView.addArrangedSubview(listPane)
        splitView.addArrangedSubview(editorPane)

        NSLayoutConstraint.activate([
            listPane.widthAnchor.constraint(equalToConstant: 264),
            editorPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),
            splitView.heightAnchor.constraint(equalToConstant: 360)
        ])

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: wrapper.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])

        return wrapper
    }

    private func buildListPane() -> NSView {
        let container = paneContainer(background: NSColor.controlBackgroundColor)

        let icon = NSImageView(image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        icon.contentTintColor = NSColor.secondaryLabelColor

        let title = sectionTitle(L("lock_time_editor.list_title"))

        listCountLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        listCountLabel.textColor = .secondaryLabelColor

        let header = NSStackView(views: [icon, title, NSView(), listCountLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10

        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("time"))
        tableColumn.title = L("lock_time_editor.column")
        tableColumn.width = 220
        tableView.addTableColumn(tableColumn)
        tableView.headerView = nil
        tableView.rowHeight = 46
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = false
        tableView.focusRingType = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(applySelectedTimeUpdate)
        tableView.onDeleteKey = { [weak self] in self?.removeSelectedTimes() }
        tableView.onReturnKey = { [weak self] in self?.applySelectedTimeUpdate() }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView

        emptyStateLabel.font = NSFont.systemFont(ofSize: 12)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.alignment = .center
        emptyStateLabel.maximumNumberOfLines = 2
        emptyStateLabel.stringValue = L("lock_time_editor.empty")

        let hintLabel = NSTextField(labelWithString: L("lock_time_editor.list_hint"))
        hintLabel.font = NSFont.systemFont(ofSize: 12)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.maximumNumberOfLines = 3

        let emptyAction = NSStackView(views: [NSView(), emptyAddButton, NSView()])
        emptyAction.orientation = .horizontal
        emptyAction.alignment = .centerY

        let body = NSStackView(views: [header, scrollView, emptyStateLabel, emptyAction, hintLabel])
        body.orientation = .vertical
        body.spacing = 12
        body.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(body)

        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            body.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            body.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            body.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
            scrollView.heightAnchor.constraint(equalToConstant: 224)
        ])

        return container
    }

    private func buildEditorPane() -> NSView {
        let container = paneContainer(background: NSColor.controlBackgroundColor)

        let meta = NSTextField(labelWithString: L("lock_time_editor.editor_meta"))
        meta.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        meta.textColor = .secondaryLabelColor

        let title = sectionTitle(L("lock_time_editor.editor_title"))

        helperLabel.font = NSFont.systemFont(ofSize: 13)
        helperLabel.textColor = .secondaryLabelColor
        helperLabel.maximumNumberOfLines = 2

        configureTimeField()

        let pickerTitle = NSTextField(labelWithString: L("lock_time_editor.picker"))
        pickerTitle.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        pickerTitle.textColor = .secondaryLabelColor

        let pickerRow = NSStackView(views: [NSView(), timeField, NSView()])
        pickerRow.orientation = .horizontal
        pickerRow.alignment = .centerY

        let pickerStack = NSStackView(views: [pickerTitle, pickerRow])
        pickerStack.orientation = .vertical
        pickerStack.spacing = 8

        let previewCard = buildPreviewCard()

        selectedLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        selectedLabel.textColor = .secondaryLabelColor

        let content = NSStackView(views: [meta, title, helperLabel, pickerStack, previewCard, selectedLabel])
        content.orientation = .vertical
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            content.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -18),
            timeField.widthAnchor.constraint(equalToConstant: 286),
            timeField.heightAnchor.constraint(equalToConstant: 58),
            previewCard.heightAnchor.constraint(equalToConstant: 176)
        ])

        return container
    }

    private func buildPreviewCard() -> NSView {
        let card = PreviewCardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let chip = makePreviewChip()

        let badge = NSTextField(labelWithString: L("lock_time_editor.preview.badge"))
        badge.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        badge.textColor = NSColor(calibratedRed: 0.48, green: 0.31, blue: 0.20, alpha: 1)

        previewTimeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 36, weight: .bold)
        previewTimeLabel.textColor = NSColor(calibratedRed: 0.45, green: 0.28, blue: 0.18, alpha: 1)

        previewCaptionLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        previewCaptionLabel.textColor = NSColor(calibratedRed: 0.54, green: 0.34, blue: 0.22, alpha: 0.95)
        previewCaptionLabel.maximumNumberOfLines = 2

        let noteTitle = NSTextField(labelWithString: L("lock_time_editor.preview.card_title"))
        noteTitle.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        noteTitle.textColor = NSColor(calibratedRed: 0.58, green: 0.39, blue: 0.28, alpha: 0.9)
        noteTitle.alignment = .right

        let noteValue = NSTextField(labelWithString: L("lock_time_editor.preview.card_value"))
        noteValue.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        noteValue.textColor = NSColor(calibratedRed: 0.47, green: 0.30, blue: 0.21, alpha: 1)
        noteValue.maximumNumberOfLines = 3
        noteValue.alignment = .right

        let leftStack = NSStackView(views: [chip, badge, previewTimeLabel, previewCaptionLabel])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 8
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(leftStack)

        let rightStack = NSStackView(views: [NSView(), noteTitle, noteValue])
        rightStack.orientation = .vertical
        rightStack.alignment = .trailing
        rightStack.spacing = 4
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(rightStack)

        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            leftStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
            leftStack.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -20),
            rightStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            rightStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            rightStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
            rightStack.widthAnchor.constraint(equalToConstant: 180)
        ])

        return card
    }

    private func buildFooter() -> NSView {
        emptyAddButton.target = self
        emptyAddButton.action = #selector(addTime)
        addButton.target = self
        addButton.action = #selector(addTime)
        updateButton.target = self
        updateButton.action = #selector(applySelectedTimeUpdate)
        removeButton.target = self
        removeButton.action = #selector(removeSelectedTimes)
        cancelButton.target = self
        cancelButton.action = #selector(cancelAndClose)
        saveButton.target = self
        saveButton.action = #selector(saveAndClose)

        let leftCluster = NSStackView(views: [addButton, updateButton, removeButton])
        leftCluster.orientation = .horizontal
        leftCluster.spacing = 10

        let rightCluster = NSStackView(views: [cancelButton, saveButton])
        rightCluster.orientation = .horizontal
        rightCluster.spacing = 12

        let leftGroup = toolbarGroup(for: leftCluster)
        let rightGroup = toolbarGroup(for: rightCluster)

        let toolbar = NSStackView(views: [leftGroup, NSView(), rightGroup])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 16
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        wrapper.layer?.cornerRadius = 24
        wrapper.layer?.cornerCurve = .continuous
        wrapper.layer?.borderWidth = 1
        wrapper.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        wrapper.addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
            toolbar.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            toolbar.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 14),
            toolbar.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -14),
            cancelButton.widthAnchor.constraint(equalTo: saveButton.widthAnchor)
        ])

        return wrapper
    }

    private func toolbarGroup(for content: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.72).cgColor
        container.layer?.cornerRadius = 18
        container.layer?.cornerCurve = .continuous
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.20).cgColor

        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        return container
    }

    private func paneContainer(background: NSColor) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = background.cgColor
        view.layer?.cornerRadius = 22
        view.layer?.cornerCurve = .continuous
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.42).cgColor
        return view
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private func makePreviewChip() -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        icon.contentTintColor = NSColor(calibratedRed: 0.54, green: 0.35, blue: 0.22, alpha: 1)

        let label = NSTextField(labelWithString: L("lock_time_editor.preview.chip"))
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor(calibratedRed: 0.54, green: 0.35, blue: 0.22, alpha: 1)

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let chip = NSView()
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.wantsLayer = true
        chip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.46).cgColor
        chip.layer?.cornerRadius = 999
        chip.layer?.cornerCurve = .continuous
        chip.layer?.borderWidth = 1
        chip.layer?.borderColor = NSColor.white.withAlphaComponent(0.38).cgColor
        chip.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: chip.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -5)
        ])

        return chip
    }

    private func configureTimeField() {
        let now = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        pickerDate = now
        timeField.configure(title: timeText(for: now), caption: L("lock_time_editor.picker"))
        timeField.onOpen = { [weak self] in
            guard let self else { return }
            let currentDate = self.pickerDate
            self.pickerPopover.show(
                relativeTo: self.timeField.bounds,
                of: self.timeField,
                date: currentDate,
                onChange: { _ in
                },
                onCommit: { [weak self] date in
                    self?.pickerDate = date
                    self?.timeField.configure(title: self?.timeText(for: date) ?? "", caption: L("lock_time_editor.picker"))
                    self?.updateUIState()
                },
                onCancel: { [weak self] in
                    self?.pickerDate = currentDate
                    self?.timeField.configure(title: self?.timeText(for: currentDate) ?? "", caption: L("lock_time_editor.picker"))
                }
            )
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        times.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("LockTimeCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? TimeCellView) ?? TimeCellView(identifier: identifier)
        cell.configure(
            time: times[row],
            isSelected: tableView.selectedRowIndexes.contains(row)
        )
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if let row = selectedSingleRow() {
            selectTime(times[row])
        }
        updateUIState()
        tableView.reloadData()
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        TimeRowView()
    }

    @objc private func addTime() {
        let formatted = selectedTimeString()
        times.append(formatted)
        times = Settings.normalizeLockTimes(times)
        reloadTable(selectTime: formatted)
        updateUIState()
    }

    @objc private func applySelectedTimeUpdate() {
        guard let row = selectedSingleRow() else { return }
        let formatted = selectedTimeString()
        times[row] = formatted
        times = Settings.normalizeLockTimes(times)
        reloadTable(selectTime: formatted)
        updateUIState()
    }

    @objc private func removeSelectedTimes() {
        let rows = IndexSet(tableView.selectedRowIndexes)
        guard !rows.isEmpty else { return }
        guard times.count > rows.count else {
            let alert = NSAlert()
            alert.messageText = L("lock_time_editor.error.title")
            alert.informativeText = L("lock_time_editor.error.message")
            alert.runModal()
            return
        }

        times.remove(atOffsets: rows)
        times = Settings.normalizeLockTimes(times)
        let nextRow = min(tableView.selectedRow, max(times.count - 1, 0))
        reloadTable(selectRow: times.isEmpty ? nil : nextRow)
        updateUIState()
    }

    @objc private func saveAndClose() {
        let normalized = Settings.normalizeLockTimes(times)
        onSave(normalized.isEmpty ? Settings.default.lockTimes : normalized)
        closeModal()
    }

    @objc private func cancelAndClose() {
        closeModal()
    }

    private func closeModal() {
        if NSApp.modalWindow === window {
            NSApp.stopModal()
        }
        window?.close()
    }

    private func reloadTable(selectRow row: Int?) {
        tableView.reloadData()
        if times.isEmpty {
            tableView.selectRowIndexes([], byExtendingSelection: false)
            return
        }

        guard let row else {
            tableView.selectRowIndexes([], byExtendingSelection: false)
            return
        }

        let clamped = max(0, min(row, times.count - 1))
        tableView.selectRowIndexes(IndexSet(integer: clamped), byExtendingSelection: false)
        tableView.scrollRowToVisible(clamped)
        selectTime(times[clamped])
    }

    private func reloadTable(selectTime time: String) {
        tableView.reloadData()
        if let row = times.firstIndex(of: time) {
            reloadTable(selectRow: row)
        } else {
            reloadTable(selectRow: nil)
        }
    }

    private func updateUIState() {
        summaryLabel.stringValue = summaryText()
        listCountLabel.stringValue = listCountText()
        helperLabel.stringValue = helperText()
        selectedLabel.stringValue = selectionText()
        previewTimeLabel.stringValue = selectedTimeString()
        previewCaptionLabel.stringValue = previewCaptionText()
        emptyStateLabel.isHidden = !times.isEmpty
        emptyAddButton.isHidden = times.count > 0
        saveButton.isEnabled = !times.isEmpty
        updateButton.isEnabled = selectedSingleRow() != nil
        removeButton.isEnabled = !tableView.selectedRowIndexes.isEmpty && times.count > tableView.selectedRowIndexes.count
        addButton.isEnabled = true
        cancelButton.isEnabled = true
    }

    private func selectedSingleRow() -> Int? {
        guard tableView.selectedRowIndexes.count == 1 else { return nil }
        let row = tableView.selectedRow
        return row >= 0 && row < times.count ? row : nil
    }

    private func selectTime(_ time: String) {
        pickerDate = dateValue(for: time)
        timeField.configure(title: timeText(for: pickerDate), caption: L("lock_time_editor.picker"))
        updateUIState()
    }

    private func selectedTimeString() -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: pickerDate)
        let hour = max(min(components.hour ?? 0, 23), 0)
        let minute = max(min(components.minute ?? 0, 59), 0)
        return String(format: "%02d:%02d", hour, minute)
    }

    private func dateValue(for time: String) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let hour = max(min(parts.first ?? 0, 23), 0)
        let minute = max(min(parts.count > 1 ? parts[1] : 0, 59), 0)
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? now
    }

    private func summaryText() -> String {
        L("lock_time_editor.summary", times.count)
    }

    private func listCountText() -> String {
        times.count == 1
            ? L("lock_time_editor.list_count.one")
            : L("lock_time_editor.list_count.many", times.count)
    }

    private func selectionText() -> String {
        if let row = selectedSingleRow() {
            return L("lock_time_editor.selected.value", times[row])
        }
        if tableView.selectedRowIndexes.isEmpty {
            return L("lock_time_editor.selected.empty")
        }
        return L("lock_time_editor.selected.multiple", tableView.selectedRowIndexes.count)
    }

    private func helperText() -> String {
        if tableView.selectedRowIndexes.count > 1 {
            return L("lock_time_editor.helper.multi")
        }
        if selectedSingleRow() != nil {
            return L("lock_time_editor.helper.single")
        }
        return L("lock_time_editor.helper")
    }

    private func previewCaptionText() -> String {
        if let row = selectedSingleRow() {
            return L("lock_time_editor.preview.selection", times[row])
        }
        return L("lock_time_editor.preview.caption")
    }

    private func localizedTimeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func timeText(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = max(min(components.hour ?? 0, 23), 0)
        let minute = max(min(components.minute ?? 0, 59), 0)
        return String(format: "%02d:%02d", hour, minute)
    }
}

private final class TimeListTableView: NSTableView {
    var onDeleteKey: (() -> Void)?
    var onReturnKey: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117:
            onDeleteKey?()
        case 36, 76:
            onReturnKey?()
        default:
            super.keyDown(with: event)
        }
    }
}

private final class TimeCellView: NSTableCellView {
    private let capsule = NSView()
    private let timeLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")
    private let dotView = NSView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.wantsLayer = true
        capsule.layer?.cornerRadius = 14
        capsule.layer?.cornerCurve = .continuous
        addSubview(capsule)

        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3

        badgeLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        badgeLabel.stringValue = L("lock_time_editor.cell.badge")
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        let rightMeta = NSStackView(views: [dotView, badgeLabel])
        rightMeta.orientation = .horizontal
        rightMeta.alignment = .centerY
        rightMeta.spacing = 6

        let stack = NSStackView(views: [timeLabel, NSView(), rightMeta])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(stack)

        NSLayoutConstraint.activate([
            capsule.leadingAnchor.constraint(equalTo: leadingAnchor),
            capsule.trailingAnchor.constraint(equalTo: trailingAnchor),
            capsule.topAnchor.constraint(equalTo: topAnchor),
            capsule.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 6),
            dotView.heightAnchor.constraint(equalToConstant: 6)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(time: String, isSelected: Bool) {
        timeLabel.stringValue = time
        if isSelected {
            capsule.layer?.backgroundColor = NSColor(calibratedRed: 0.89, green: 0.93, blue: 0.99, alpha: 1).cgColor
            capsule.layer?.borderWidth = 1
            capsule.layer?.borderColor = NSColor(calibratedRed: 0.73, green: 0.82, blue: 0.95, alpha: 1).cgColor
            timeLabel.textColor = NSColor(calibratedRed: 0.17, green: 0.28, blue: 0.47, alpha: 1)
            badgeLabel.textColor = NSColor(calibratedRed: 0.29, green: 0.45, blue: 0.72, alpha: 1)
            dotView.layer?.backgroundColor = NSColor(calibratedRed: 0.29, green: 0.55, blue: 0.91, alpha: 1).cgColor
        } else {
            capsule.layer?.backgroundColor = NSColor.clear.cgColor
            capsule.layer?.borderWidth = 0
            timeLabel.textColor = .labelColor
            badgeLabel.textColor = .secondaryLabelColor
            dotView.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
        }
    }
}

private final class TimeRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        .normal
    }
}

private final class PreviewCardView: NSView {
    private let gradientLayer = CAGradientLayer()
    private let orbLayer = CAShapeLayer()
    private let ringLayer = CAShapeLayer()
    private let waveLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.55).cgColor

        gradientLayer.colors = [
            NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.93, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.99, green: 0.88, blue: 0.78, alpha: 1).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0.08, y: 1.0)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 0.1)
        gradientLayer.cornerRadius = 24
        layer?.addSublayer(gradientLayer)

        orbLayer.fillColor = NSColor(calibratedRed: 0.98, green: 0.80, blue: 0.58, alpha: 0.28).cgColor
        layer?.addSublayer(orbLayer)

        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.strokeColor = NSColor.white.withAlphaComponent(0.35).cgColor
        ringLayer.lineWidth = 1.5
        layer?.addSublayer(ringLayer)

        waveLayer.fillColor = NSColor.white.withAlphaComponent(0.22).cgColor
        layer?.addSublayer(waveLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        orbLayer.path = CGPath(ellipseIn: CGRect(x: bounds.maxX - 142, y: bounds.maxY - 128, width: 128, height: 128), transform: nil)
        ringLayer.path = CGPath(ellipseIn: CGRect(x: bounds.maxX - 156, y: bounds.maxY - 142, width: 156, height: 156), transform: nil)
        waveLayer.path = makeWavePath(in: bounds)
        CATransaction.commit()
    }

    private func makeWavePath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + 32))
        path.addCurve(
            to: CGPoint(x: rect.maxX * 0.45, y: rect.minY + 22),
            control1: CGPoint(x: rect.minX + 32, y: rect.minY + 52),
            control2: CGPoint(x: rect.maxX * 0.26, y: rect.minY + 8)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + 44),
            control1: CGPoint(x: rect.maxX * 0.66, y: rect.minY + 40),
            control2: CGPoint(x: rect.maxX - 44, y: rect.minY + 58)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private final class PillActionControl: NSControl {
    private let symbolView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let title: String
    private let tone: ButtonTone
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    init(title: String, symbol: String, tone: ButtonTone) {
        self.title = title
        self.tone = tone
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        focusRingType = .none
        setAccessibilityElement(true)

        layer?.cornerRadius = 15
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.10).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 14
        layer?.shadowOffset = CGSize(width: 0, height: 6)

        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        symbolView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        symbolView.setContentHuggingPriority(.required, for: .horizontal)
        symbolView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.stringValue = title
        titleLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [symbolView, titleLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 42),
            widthAnchor.constraint(greaterThanOrEqualToConstant: tone.minimumWidth),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        updateAppearance()

        guard let window else {
            isPressed = false
            updateAppearance()
            return
        }

        while let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let location = convert(nextEvent.locationInWindow, from: nil)
            let isInside = bounds.contains(location)

            switch nextEvent.type {
            case .leftMouseDragged:
                if isPressed != isInside {
                    isPressed = isInside
                    updateAppearance()
                }
            case .leftMouseUp:
                isPressed = false
                updateAppearance()
                if isInside {
                    sendAction(action, to: target)
                }
                return
            default:
                break
            }
        }
    }

    private func updateAppearance() {
        layer?.backgroundColor = tone.backgroundColor(isEnabled: isEnabled, isHovered: isHovered, isPressed: isPressed).cgColor
        layer?.borderColor = tone.borderColor(isEnabled: isEnabled).cgColor
        symbolView.contentTintColor = tone.textColor(isEnabled: isEnabled)
        titleLabel.textColor = tone.textColor(isEnabled: isEnabled)
        alphaValue = isEnabled ? 1 : 0.5
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        if event.keyCode == 36 || event.keyCode == 49 {
            sendAction(action, to: target)
        } else {
            super.keyDown(with: event)
        }
    }

    override func accessibilityLabel() -> String? {
        title
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        sendAction(action, to: target)
        return true
    }
}

private final class TimeSelectionField: NSControl {
    private let iconWrap = NSView()
    private let captionLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let arrowView = NSImageView()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false
    var onOpen: (() -> Void)?
    private var accessibilityTitle = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setAccessibilityElement(true)
        layer?.cornerRadius = 18
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor(calibratedRed: 0.98, green: 0.99, blue: 1.0, alpha: 1).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedRed: 0.84, green: 0.88, blue: 0.95, alpha: 1).cgColor
        layer?.shadowColor = NSColor(calibratedRed: 0.46, green: 0.56, blue: 0.72, alpha: 0.16).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: 10)

        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.wantsLayer = true
        iconWrap.layer?.cornerRadius = 12
        iconWrap.layer?.cornerCurve = .continuous
        iconWrap.layer?.backgroundColor = NSColor(calibratedRed: 0.91, green: 0.95, blue: 1.0, alpha: 1).cgColor

        let iconView = NSImageView(image: NSImage(systemSymbolName: "clock.fill", accessibilityDescription: nil) ?? NSImage())
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        iconView.contentTintColor = NSColor(calibratedRed: 0.19, green: 0.48, blue: 0.93, alpha: 1)
        iconWrap.addSubview(iconView)

        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        captionLabel.textColor = NSColor.secondaryLabelColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = NSColor(calibratedRed: 0.16, green: 0.21, blue: 0.30, alpha: 1)

        arrowView.translatesAutoresizingMaskIntoConstraints = false
        arrowView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        arrowView.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        arrowView.contentTintColor = NSColor(calibratedRed: 0.45, green: 0.52, blue: 0.62, alpha: 1)

        let textStack = NSStackView(views: [captionLabel, titleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        let stack = NSStackView(views: [iconWrap, textStack, NSView(), arrowView])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconWrap.widthAnchor.constraint(equalToConstant: 40),
            iconWrap.heightAnchor.constraint(equalToConstant: 40),
            iconView.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        updateAppearance()
    }

    func configure(title: String, caption: String) {
        titleLabel.stringValue = title
        captionLabel.stringValue = caption.uppercased()
        accessibilityTitle = "\(caption): \(title)"
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateAppearance()
        onOpen?()
        isPressed = false
        updateAppearance()
    }

    private func updateAppearance() {
        let borderColor = isPressed
            ? NSColor(calibratedRed: 0.42, green: 0.63, blue: 0.96, alpha: 1)
            : isHovered
                ? NSColor(calibratedRed: 0.62, green: 0.74, blue: 0.95, alpha: 1)
                : NSColor(calibratedRed: 0.84, green: 0.88, blue: 0.95, alpha: 1)
        let backgroundColor = isPressed
            ? NSColor(calibratedRed: 0.95, green: 0.98, blue: 1.0, alpha: 1)
            : isHovered
                ? NSColor(calibratedRed: 0.985, green: 0.992, blue: 1.0, alpha: 1)
                : NSColor(calibratedRed: 0.98, green: 0.99, blue: 1.0, alpha: 1)

        layer?.backgroundColor = backgroundColor.cgColor
        layer?.borderColor = borderColor.cgColor
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 {
            onOpen?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func accessibilityLabel() -> String? {
        accessibilityTitle
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .popUpButton
    }

    override func accessibilityPerformPress() -> Bool {
        onOpen?()
        return true
    }
}

private final class TimePickerPopoverController: NSPopover {
    private let content = TimePickerPanelViewController()

    override init() {
        super.init()
        behavior = .transient
        animates = true
        appearance = NSAppearance(named: .aqua)
        contentViewController = content
        content.preferredContentSize = NSSize(width: 286, height: 282)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView,
        date: Date,
        onChange: @escaping (Date) -> Void,
        onCommit: @escaping (Date) -> Void,
        onCancel: @escaping () -> Void
    ) {
        content.configure(
            date: date,
            onChange: onChange,
            onCommit: { [weak self] selectedDate in
                onCommit(selectedDate)
                self?.performClose(nil)
            },
            onCancel: { [weak self] in
                onCancel()
                self?.performClose(nil)
            }
        )
        show(relativeTo: positioningRect, of: positioningView, preferredEdge: .maxY)
    }

    #if DEBUG
    func debugExportSnapshot(to url: URL) {
        _ = content.view
        content.view.layoutSubtreeIfNeeded()
        guard let image = content.view.snapshotImage() else { return }
        guard let tiffData = image.tiffRepresentation else { return }
        guard let rep = NSBitmapImageRep(data: tiffData) else { return }
        guard let pngData = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { return }
        try? pngData.write(to: url)
    }
    #endif
}

private final class TimePickerPanelViewController: NSViewController {
    private let previewLabel = NSTextField(labelWithString: "")
    private let hourTableView = TimeWheelTableView()
    private let minuteTableView = TimeWheelTableView()
    private var onChange: ((Date) -> Void)?
    private var onCommit: ((Date) -> Void)?
    private var onCancel: (() -> Void)?
    private var selectedHour = 0
    private var selectedMinute = 0

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 286, height: 282))
        root.appearance = NSAppearance(named: .aqua)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedRed: 0.965, green: 0.973, blue: 0.988, alpha: 1).cgColor
        root.layer?.cornerRadius = 20
        root.layer?.cornerCurve = .continuous
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor(calibratedRed: 0.77, green: 0.82, blue: 0.90, alpha: 0.9).cgColor

        let title = NSTextField(labelWithString: L("lock_time_editor.picker"))
        title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        title.textColor = NSColor(calibratedRed: 0.40, green: 0.46, blue: 0.56, alpha: 1)
        title.translatesAutoresizingMaskIntoConstraints = false

        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        previewLabel.textColor = NSColor(calibratedRed: 0.18, green: 0.24, blue: 0.34, alpha: 1)

        let row = NSStackView(views: [makePickerCard(title: L("lock_time_editor.hour"), tableView: hourTableView), makePickerCard(title: L("lock_time_editor.minute"), tableView: minuteTableView)])
        row.orientation = .horizontal
        row.spacing = 12
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = PillActionControl(title: L("button.cancel"), symbol: "xmark", tone: .ghost)
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)

        let applyButton = PillActionControl(title: L("button.confirm"), symbol: "checkmark", tone: .primary)
        applyButton.target = self
        applyButton.action = #selector(applyTapped)

        let footer = NSStackView(views: [cancelButton, NSView(), applyButton])
        footer.orientation = .horizontal
        footer.spacing = 10
        footer.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(title)
        root.addSubview(previewLabel)
        root.addSubview(row)
        root.addSubview(footer)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            previewLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            previewLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            row.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 14),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            row.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14),
            cancelButton.widthAnchor.constraint(equalTo: applyButton.widthAnchor)
        ])

        view = root
    }

    func configure(date: Date, onChange: @escaping (Date) -> Void, onCommit: @escaping (Date) -> Void, onCancel: @escaping () -> Void) {
        self.onChange = onChange
        self.onCommit = onCommit
        self.onCancel = onCancel
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        selectedHour = max(min(components.hour ?? 0, 23), 0)
        selectedMinute = max(min(components.minute ?? 0, 59), 0)
        hourTableView.configure(values: (0...23).map { String(format: "%02d", $0) }, selectedIndex: selectedHour)
        minuteTableView.configure(values: (0...59).map { String(format: "%02d", $0) }, selectedIndex: selectedMinute)
        hourTableView.selectionHandler = { [weak self] index in
            self?.selectedHour = index
            self?.didChangeSelection()
        }
        minuteTableView.selectionHandler = { [weak self] index in
            self?.selectedMinute = index
            self?.didChangeSelection()
        }
        updatePreview()
    }

    private func makePickerCard(title: String, tableView: TimeWheelTableView) -> NSView {
        let caption = NSTextField(labelWithString: title)
        caption.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        caption.textColor = NSColor(calibratedRed: 0.46, green: 0.52, blue: 0.62, alpha: 1)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.appearance = NSAppearance(named: .aqua)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.cornerCurve = .continuous
        container.layer?.backgroundColor = NSColor(calibratedRed: 0.98, green: 0.985, blue: 1.0, alpha: 1).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(calibratedRed: 0.85, green: 0.89, blue: 0.95, alpha: 1).cgColor

        let stack = NSStackView(views: [caption, scrollView])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 10
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            scrollView.heightAnchor.constraint(equalToConstant: 124)
        ])

        return container
    }

    private func didChangeSelection() {
        updatePreview()
        onChange?(currentDate())
    }

    private func updatePreview() {
        previewLabel.stringValue = String(format: "%02d:%02d", selectedHour, selectedMinute)
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    @objc private func applyTapped() {
        onCommit?(currentDate())
    }

    private func currentDate() -> Date {
        let now = Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour = selectedHour
        components.minute = selectedMinute
        components.second = 0
        return Calendar.current.date(from: components) ?? now
    }
}

private final class TimeWheelTableView: NSTableView, NSTableViewDataSource, NSTableViewDelegate {
    private var values: [String] = []
    var selectionHandler: ((Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .aqua)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        column.width = 96
        addTableColumn(column)
        headerView = nil
        rowHeight = 30
        intercellSpacing = NSSize(width: 0, height: 4)
        backgroundColor = .clear
        selectionHighlightStyle = .none
        allowsMultipleSelection = false
        focusRingType = .none
        delegate = self
        dataSource = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(values: [String], selectedIndex: Int) {
        self.values = values
        reloadData()
        let clamped = max(0, min(selectedIndex, max(values.count - 1, 0)))
        if !values.isEmpty {
            selectRowIndexes(IndexSet(integer: clamped), byExtendingSelection: false)
            scrollRowToVisible(clamped)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        values.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("TimeWheelCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? TimeWheelCellView) ?? TimeWheelCellView(identifier: identifier)
        cell.configure(value: values[row], isSelected: selectedRow == row)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        reloadData()
        if selectedRow >= 0 {
            selectionHandler?(selectedRow)
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        TimeRowView()
    }
}

private final class TimeWheelCellView: NSTableCellView {
    private let capsule = NSView()
    private let valueLabel = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true

        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.wantsLayer = true
        capsule.layer?.cornerRadius = 10
        capsule.layer?.cornerCurve = .continuous
        addSubview(capsule)

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        valueLabel.alignment = .center
        capsule.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            capsule.leadingAnchor.constraint(equalTo: leadingAnchor),
            capsule.trailingAnchor.constraint(equalTo: trailingAnchor),
            capsule.topAnchor.constraint(equalTo: topAnchor),
            capsule.bottomAnchor.constraint(equalTo: bottomAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -8),
            valueLabel.centerYAnchor.constraint(equalTo: capsule.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(value: String, isSelected: Bool) {
        valueLabel.stringValue = value
        if isSelected {
            capsule.layer?.backgroundColor = NSColor(calibratedRed: 0.90, green: 0.94, blue: 1.0, alpha: 1).cgColor
            capsule.layer?.borderWidth = 1
            capsule.layer?.borderColor = NSColor(calibratedRed: 0.66, green: 0.77, blue: 0.95, alpha: 1).cgColor
            valueLabel.textColor = NSColor(calibratedRed: 0.18, green: 0.40, blue: 0.75, alpha: 1)
        } else {
            capsule.layer?.backgroundColor = NSColor.clear.cgColor
            capsule.layer?.borderWidth = 0
            valueLabel.textColor = NSColor(calibratedRed: 0.26, green: 0.30, blue: 0.37, alpha: 1)
        }
    }
}

private extension ButtonTone {
    func backgroundColor(isEnabled: Bool, isHovered: Bool, isPressed: Bool) -> NSColor {
        let alpha: CGFloat = isEnabled ? 1 : 0.72
        switch self {
        case .primary:
            if isPressed {
                return NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.86, alpha: alpha)
            }
            if isHovered {
                return NSColor(calibratedRed: 0.21, green: 0.57, blue: 0.98, alpha: alpha)
            }
            return NSColor(calibratedRed: 0.17, green: 0.53, blue: 0.96, alpha: alpha)
        case .secondary:
            if isPressed {
                return NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.99, alpha: alpha)
            }
            if isHovered {
                return NSColor(calibratedRed: 0.98, green: 0.99, blue: 1.0, alpha: alpha)
            }
            return NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.99, alpha: alpha)
        case .destructive:
            if isPressed {
                return NSColor(calibratedRed: 0.99, green: 0.90, blue: 0.90, alpha: alpha)
            }
            if isHovered {
                return NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.97, alpha: alpha)
            }
            return NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.95, alpha: alpha)
        case .ghost:
            if isPressed {
                return NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.97, alpha: alpha)
            }
            if isHovered {
                return NSColor(calibratedRed: 0.97, green: 0.98, blue: 1.0, alpha: alpha)
            }
            return NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.98, alpha: alpha)
        }
    }

    func borderColor(isEnabled: Bool) -> NSColor {
        let alpha: CGFloat = isEnabled ? 1 : 0.72
        switch self {
        case .primary:
            return NSColor(calibratedRed: 0.14, green: 0.44, blue: 0.83, alpha: alpha)
        case .secondary:
            return NSColor(calibratedRed: 0.84, green: 0.88, blue: 0.95, alpha: alpha)
        case .destructive:
            return NSColor(calibratedRed: 0.94, green: 0.78, blue: 0.78, alpha: alpha)
        case .ghost:
            return NSColor(calibratedRed: 0.83, green: 0.86, blue: 0.91, alpha: alpha)
        }
    }

    func textColor(isEnabled: Bool) -> NSColor {
        let alpha: CGFloat = isEnabled ? 1 : 0.68
        switch self {
        case .primary:
            return NSColor(calibratedWhite: 1, alpha: alpha)
        case .secondary:
            return NSColor(calibratedRed: 0.20, green: 0.35, blue: 0.62, alpha: alpha)
        case .destructive:
            return NSColor(calibratedRed: 0.78, green: 0.25, blue: 0.25, alpha: alpha)
        case .ghost:
            return NSColor(calibratedRed: 0.33, green: 0.38, blue: 0.46, alpha: alpha)
        }
    }

    var minimumWidth: CGFloat {
        switch self {
        case .primary:
            return 126
        case .secondary, .destructive, .ghost:
            return 118
        }
    }
}

private extension Array {
    mutating func remove(atOffsets offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            remove(at: offset)
        }
    }
}

#if DEBUG
private extension NSView {
    func snapshotImage() -> NSImage? {
        let bounds = self.bounds
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}
#endif
