import Cocoa

final class LockTimeEditorWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private var times: [String]
    private let onSave: ([String]) -> Void

    private let tableView = NSTableView()
    private let hourPopup = NSPopUpButton()
    private let minutePopup = NSPopUpButton()
    private let saveButton = NSButton(title: L("button.save"), target: nil, action: nil)
    private let removeButton = NSButton(title: L("menu.remove_lock_time"), target: nil, action: nil)
    private let addButton = NSButton(title: L("menu.add_lock_time"), target: nil, action: nil)
    private let updateButton = NSButton(title: L("menu.update_lock_time"), target: nil, action: nil)

    init(times: [String], onSave: @escaping ([String]) -> Void) {
        self.times = Settings.normalizeLockTimes(times)
        if self.times.isEmpty {
            self.times = Settings.default.lockTimes
        }
        self.onSave = onSave

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = L("lock_time_editor.title")
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = false
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

    func windowWillClose(_ notification: Notification) {
        if NSApp.modalWindow === window {
            NSApp.stopModal()
        }
    }

    // MARK: - UI

    private func configureUI(in window: NSWindow) {
        guard let root = window.contentView else { return }
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = NSTextField(labelWithString: L("lock_time_editor.title"))
        title.font = NSFont.systemFont(ofSize: 20, weight: .bold)

        let subtitle = NSTextField(labelWithString: L("lock_time_editor.message"))
        subtitle.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        subtitle.textColor = .secondaryLabelColor

        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical
        header.spacing = 6
        header.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("time"))
        tableColumn.title = L("lock_time_editor.column")
        tableColumn.width = 380

        tableView.addTableColumn(tableColumn)
        tableView.headerView = nil
        tableView.rowHeight = 32
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.target = self
        tableView.doubleAction = #selector(applySelectedTimeUpdate)
        scroll.documentView = tableView

        configureTimePopups()

        let pickerLabel = NSTextField(labelWithString: L("lock_time_editor.picker"))
        pickerLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        pickerLabel.textColor = .secondaryLabelColor

        let pickerStack = NSStackView(views: [pickerLabel, buildTimeSelectorRow()])
        pickerStack.orientation = .vertical
        pickerStack.spacing = 6
        pickerStack.translatesAutoresizingMaskIntoConstraints = false

        addButton.target = self
        addButton.action = #selector(addTime)
        updateButton.target = self
        updateButton.action = #selector(applySelectedTimeUpdate)
        removeButton.target = self
        removeButton.action = #selector(removeSelectedTimes)
        saveButton.target = self
        saveButton.action = #selector(saveAndClose)
        let cancelButton = NSButton(title: L("button.cancel"), target: self, action: #selector(cancelAndClose))

        let controls = NSStackView(views: [pickerStack, NSView(), addButton, updateButton, removeButton, saveButton, cancelButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 10
        controls.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(header)
        root.addSubview(scroll)
        root.addSubview(controls)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),

            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            scroll.heightAnchor.constraint(equalToConstant: 210),

            controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            controls.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            controls.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 18),
            controls.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
        ])

        reloadTable(selectRow: nil)
        updateButtonState()
    }

    private func configureTimePopups() {
        hourPopup.addItems(withTitles: (0...23).map { String(format: "%02d", $0) })
        minutePopup.addItems(withTitles: (0...59).map { String(format: "%02d", $0) })

        [hourPopup, minutePopup].forEach { popup in
            popup.translatesAutoresizingMaskIntoConstraints = false
            popup.target = self
            popup.action = #selector(timePopupChanged(_:))
        }

        selectTime(times.first ?? "00:00")
    }

    private func buildTimeSelectorRow() -> NSView {
        let hourLabel = NSTextField(labelWithString: L("lock_time_editor.hour"))
        hourLabel.textColor = .secondaryLabelColor

        let minuteLabel = NSTextField(labelWithString: L("lock_time_editor.minute"))
        minuteLabel.textColor = .secondaryLabelColor

        let hourStack = NSStackView(views: [hourLabel, hourPopup])
        hourStack.orientation = .vertical
        hourStack.spacing = 4

        let minuteStack = NSStackView(views: [minuteLabel, minutePopup])
        minuteStack.orientation = .vertical
        minuteStack.spacing = 4

        let row = NSStackView(views: [hourStack, minuteStack])
        row.orientation = .horizontal
        row.alignment = .top
        row.distribution = .fillEqually
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        return row
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        times.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("LockTimeCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()

        cell.textField?.stringValue = times[row]
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        if row >= 0, row < times.count {
            selectTime(times[row])
        }
        updateButtonState()
    }

    // MARK: - Actions

    @objc private func timePopupChanged(_ sender: NSPopUpButton) {
        updateButtonState()
    }

    @objc private func addTime() {
        let formatted = selectedTimeString()
        times.append(formatted)
        times = Settings.normalizeLockTimes(times)
        reloadTable(selectTime: formatted)
        updateButtonState()
    }

    @objc private func applySelectedTimeUpdate() {
        let row = tableView.selectedRow
        guard row >= 0, row < times.count else { return }

        let formatted = selectedTimeString()
        times[row] = formatted
        times = Settings.normalizeLockTimes(times)
        reloadTable(selectTime: formatted)
        updateButtonState()
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
        updateButtonState()
    }

    @objc private func saveAndClose() {
        let normalized = Settings.normalizeLockTimes(times)
        onSave(normalized.isEmpty ? Settings.default.lockTimes : normalized)
        closeModal()
    }

    @objc private func cancelAndClose() {
        closeModal()
    }

    // MARK: - Helpers

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
        if clamped < times.count {
            selectTime(times[clamped])
        }
    }

    private func reloadTable(selectTime time: String) {
        tableView.reloadData()
        if let row = times.firstIndex(of: time) {
            reloadTable(selectRow: row)
        } else {
            reloadTable(selectRow: nil)
        }
    }

    private func updateButtonState() {
        saveButton.isEnabled = !times.isEmpty
        updateButton.isEnabled = tableView.selectedRow >= 0 && tableView.selectedRow < times.count
        removeButton.isEnabled = !tableView.selectedRowIndexes.isEmpty && times.count > tableView.selectedRowIndexes.count
    }

    private func selectTime(_ time: String) {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let hour = parts.first ?? 0
        let minute = parts.count > 1 ? parts[1] : 0
        hourPopup.selectItem(at: max(0, min(hour, 23)))
        minutePopup.selectItem(at: max(0, min(minute, 59)))
    }

    private func selectedTimeString() -> String {
        let hour = max(hourPopup.indexOfSelectedItem, 0)
        let minute = max(minutePopup.indexOfSelectedItem, 0)
        return String(format: "%02d:%02d", hour, minute)
    }
}

private extension Array {
    mutating func remove(atOffsets offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            remove(at: offset)
        }
    }
}
