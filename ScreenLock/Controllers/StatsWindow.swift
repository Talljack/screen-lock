import Cocoa

class StatsWindow: NSWindow {

    private var periodDays = 7

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 760),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        title = "锁屏统计"
        center()
        isReleasedWhenClosed = false
        backgroundColor = .windowBackgroundColor

        let root = NSView()
        root.wantsLayer = true
        contentView = root
        setupUI(in: root)
    }

    func refresh() {
        guard let root = contentView else { return }
        root.subviews.forEach { $0.removeFromSuperview() }
        setupUI(in: root)
    }

    // MARK: - Layout

    private func setupUI(in root: NSView) {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        root.addSubview(scroll)

        let container = FlippedView()
        container.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = container

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            container.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        let margin: CGFloat = 24
        var y: CGFloat = 0

        // Header
        let header = createHeader()
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 100),
        ])
        y += 112

        // Stats cards (2x2 grid)
        let stats = StatsManager.shared
        let cardGrid = createCardGrid(
            streak: stats.currentStreak,
            longestStreak: stats.longestStreak,
            totalCount: stats.totalCount,
            avgHour: stats.averageLockHour(days: periodDays)
        )
        cardGrid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(cardGrid)
        NSLayoutConstraint.activate([
            cardGrid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            cardGrid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),
            cardGrid.topAnchor.constraint(equalTo: container.topAnchor, constant: y),
            cardGrid.heightAnchor.constraint(equalToConstant: 180),
        ])
        y += 196

        // Weekly comparison + completion rate row
        let insightRow = createInsightRow(stats: stats)
        insightRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(insightRow)
        NSLayoutConstraint.activate([
            insightRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            insightRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),
            insightRow.topAnchor.constraint(equalTo: container.topAnchor, constant: y),
            insightRow.heightAnchor.constraint(equalToConstant: 68),
        ])
        y += 82

        // Chart section title + period toggle
        let chartHeader = NSStackView()
        chartHeader.orientation = .horizontal
        chartHeader.translatesAutoresizingMaskIntoConstraints = false

        let chartTitle = NSTextField(labelWithString: "锁屏趋势")
        chartTitle.font = NSFont.systemFont(ofSize: 15, weight: .semibold)

        let toggle = NSSegmentedControl(labels: ["7 天", "30 天"], trackingMode: .selectOne, target: self, action: #selector(periodChanged(_:)))
        toggle.selectedSegment = (periodDays == 7) ? 0 : 1
        toggle.controlSize = .small

        chartHeader.addArrangedSubview(chartTitle)
        chartHeader.addArrangedSubview(NSView()) // spacer
        chartHeader.addArrangedSubview(toggle)

        container.addSubview(chartHeader)
        NSLayoutConstraint.activate([
            chartHeader.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            chartHeader.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),
            chartHeader.topAnchor.constraint(equalTo: container.topAnchor, constant: y),
        ])
        y += 32

        // Bar chart
        let chartContainer = NSView()
        chartContainer.wantsLayer = true
        chartContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        chartContainer.layer?.cornerRadius = 14
        chartContainer.translatesAutoresizingMaskIntoConstraints = false

        let chartView = BarChartView(data: stats.dailyCounts(days: periodDays))
        chartView.translatesAutoresizingMaskIntoConstraints = false
        chartContainer.addSubview(chartView)

        container.addSubview(chartContainer)
        NSLayoutConstraint.activate([
            chartContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            chartContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),
            chartContainer.topAnchor.constraint(equalTo: container.topAnchor, constant: y),
            chartContainer.heightAnchor.constraint(equalToConstant: 200),
            chartView.leadingAnchor.constraint(equalTo: chartContainer.leadingAnchor, constant: 8),
            chartView.trailingAnchor.constraint(equalTo: chartContainer.trailingAnchor, constant: -8),
            chartView.topAnchor.constraint(equalTo: chartContainer.topAnchor, constant: 12),
            chartView.bottomAnchor.constraint(equalTo: chartContainer.bottomAnchor, constant: -4),
        ])
        y += 216

        // Achievements section
        let achieveTitle = NSTextField(labelWithString: "成就墙")
        achieveTitle.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        achieveTitle.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(achieveTitle)
        NSLayoutConstraint.activate([
            achieveTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            achieveTitle.topAnchor.constraint(equalTo: container.topAnchor, constant: y),
        ])
        y += 28

        let unlocked = Set(stats.unlockedAchievements.map(\.id))
        let allAchievements = Achievement.all
        let columns = 3
        let spacing: CGFloat = 12
        let tileSize: CGFloat = ((560 - margin * 2) - spacing * CGFloat(columns - 1)) / CGFloat(columns)

        for (i, a) in allAchievements.enumerated() {
            let col = i % columns
            let row = i / columns
            let isUnlocked = unlocked.contains(a.id)

            let tile = createAchievementTile(a, unlocked: isUnlocked, size: tileSize)
            tile.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(tile)

            NSLayoutConstraint.activate([
                tile.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin + CGFloat(col) * (tileSize + spacing)),
                tile.topAnchor.constraint(equalTo: container.topAnchor, constant: y + CGFloat(row) * (tileSize + spacing)),
                tile.widthAnchor.constraint(equalToConstant: tileSize),
                tile.heightAnchor.constraint(equalToConstant: tileSize),
            ])
        }

        let totalRows = (allAchievements.count + columns - 1) / columns
        y += CGFloat(totalRows) * (tileSize + spacing) + 24

        // Bottom spacer for scroll
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(spacer)
        NSLayoutConstraint.activate([
            spacer.topAnchor.constraint(equalTo: container.topAnchor, constant: y),
            spacer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            spacer.heightAnchor.constraint(equalToConstant: 1),
            spacer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        ])
    }

    // MARK: - Header

    private func createHeader() -> NSView {
        let header = NSView()
        header.wantsLayer = true

        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            NSColor(calibratedRed: 0.95, green: 0.78, blue: 0.88, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.85, green: 0.72, blue: 0.92, alpha: 1.0).cgColor,
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        header.layer = gradientLayer

        let stats = StatsManager.shared
        let streak = stats.currentStreak

        let greeting: String
        if streak >= 30 {
            greeting = "你真是睡眠大师！"
        } else if streak >= 7 {
            greeting = "坚持得很棒，继续加油！"
        } else if streak >= 1 {
            greeting = "好的开始，继续保持！"
        } else {
            greeting = "今晚开始早睡吧"
        }

        let titleLabel = NSTextField(labelWithString: "你的锁屏旅程")
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(labelWithString: greeting)
        subtitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(titleLabel)
        header.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            titleLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 28),
            subtitleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
        ])

        return header
    }

    // MARK: - Card Grid (2x2)

    private func createCardGrid(streak: Int, longestStreak: Int, totalCount: Int, avgHour: Double?) -> NSView {
        let grid = NSView()

        let avgText: String
        if let avg = avgHour {
            let h = Int(avg)
            let m = Int((avg - Double(h)) * 60)
            avgText = String(format: "%02d:%02d", h, m)
        } else {
            avgText = "--:--"
        }

        let cards: [(emoji: String, title: String, value: String, gradientStart: NSColor, gradientEnd: NSColor)] = [
            ("🔥", "当前连续", streak > 0 ? "\(streak) 天" : "0 天",
             NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.45, alpha: 0.12),
             NSColor(calibratedRed: 1.0, green: 0.75, blue: 0.4, alpha: 0.08)),
            ("🏆", "最长连续", "\(longestStreak) 天",
             NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.3, alpha: 0.12),
             NSColor(calibratedRed: 0.98, green: 0.9, blue: 0.5, alpha: 0.08)),
            ("🌙", "总锁屏", "\(totalCount) 次",
             NSColor(calibratedRed: 0.55, green: 0.5, blue: 0.95, alpha: 0.12),
             NSColor(calibratedRed: 0.7, green: 0.65, blue: 1.0, alpha: 0.08)),
            ("📊", "平均时间", avgText,
             NSColor(calibratedRed: 0.35, green: 0.78, blue: 0.7, alpha: 0.12),
             NSColor(calibratedRed: 0.5, green: 0.85, blue: 0.78, alpha: 0.08)),
        ]

        let spacing: CGFloat = 14
        for (i, card) in cards.enumerated() {
            let col = i % 2
            let row = i / 2
            let cardView = makeStatCard(
                emoji: card.emoji, title: card.title, value: card.value,
                gradientStart: card.gradientStart, gradientEnd: card.gradientEnd
            )
            cardView.translatesAutoresizingMaskIntoConstraints = false
            grid.addSubview(cardView)

            NSLayoutConstraint.activate([
                cardView.topAnchor.constraint(equalTo: grid.topAnchor, constant: CGFloat(row) * (80 + spacing)),
                cardView.heightAnchor.constraint(equalToConstant: 80),
            ])

            if col == 0 {
                cardView.leadingAnchor.constraint(equalTo: grid.leadingAnchor).isActive = true
                cardView.trailingAnchor.constraint(equalTo: grid.centerXAnchor, constant: -spacing / 2).isActive = true
            } else {
                cardView.leadingAnchor.constraint(equalTo: grid.centerXAnchor, constant: spacing / 2).isActive = true
                cardView.trailingAnchor.constraint(equalTo: grid.trailingAnchor).isActive = true
            }
        }

        return grid
    }

    private func makeStatCard(emoji: String, title: String, value: String,
                              gradientStart: NSColor, gradientEnd: NSColor) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 14

        let bgLayer = CAGradientLayer()
        bgLayer.colors = [gradientStart.cgColor, gradientEnd.cgColor]
        bgLayer.startPoint = CGPoint(x: 0, y: 0)
        bgLayer.endPoint = CGPoint(x: 1, y: 1)
        bgLayer.cornerRadius = 14
        card.layer?.addSublayer(bgLayer)

        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.15).cgColor
        card.layer?.borderWidth = 1

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.06)
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 8
        card.shadow = shadow

        let emojiLabel = NSTextField(labelWithString: emoji)
        emojiLabel.font = NSFont.systemFont(ofSize: 22)
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(emojiLabel)
        card.addSubview(titleLabel)
        card.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            emojiLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            emojiLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),

            titleLabel.leadingAnchor.constraint(equalTo: emojiLabel.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: emojiLabel.centerYAnchor),

            valueLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            valueLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])

        // Resize gradient layer when card resizes
        card.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: card, queue: .main) { _ in
            bgLayer.frame = card.bounds
        }

        return card
    }

    // MARK: - Insight Row (Weekly Comparison + Completion Rate + Trigger Split)

    private func createInsightRow(stats: StatsManager) -> NSView {
        let row = NSStackView()
        row.distribution = .fillEqually
        row.spacing = 12

        // Weekly comparison
        let weekly = stats.weeklyComparison
        let diff = weekly.thisWeek - weekly.lastWeek
        let arrow: String
        let trendColor: NSColor
        if diff > 0 {
            arrow = "↑\(diff)"
            trendColor = .systemGreen
        } else if diff < 0 {
            arrow = "↓\(abs(diff))"
            trendColor = .systemOrange
        } else {
            arrow = "→"
            trendColor = .secondaryLabelColor
        }
        row.addArrangedSubview(makeInsightCard(
            label: "本周 vs 上周",
            value: "\(weekly.thisWeek) vs \(weekly.lastWeek)",
            badge: arrow,
            badgeColor: trendColor
        ))

        // Completion rate
        let rate = stats.completionRate
        let rateStr = String(format: "%.0f%%", rate * 100)
        row.addArrangedSubview(makeInsightCard(
            label: "完成率",
            value: rateStr,
            badge: nil,
            badgeColor: .clear
        ))

        // Trigger distribution
        let scheduled = stats.scheduledCount
        let manual = stats.manualCount
        row.addArrangedSubview(makeInsightCard(
            label: "定时 / 手动",
            value: "\(scheduled) / \(manual)",
            badge: nil,
            badgeColor: .clear
        ))

        return row
    }

    private func makeInsightCard(label: String, value: String, badge: String?, badgeColor: NSColor) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 12

        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .tertiaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .bold)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(titleLabel)
        card.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            valueLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            valueLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
        ])

        if let badge = badge {
            let badgeLabel = NSTextField(labelWithString: badge)
            badgeLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            badgeLabel.textColor = badgeColor
            badgeLabel.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(badgeLabel)
            NSLayoutConstraint.activate([
                badgeLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
                badgeLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            ])
        }

        return card
    }

    // MARK: - Period toggle

    @objc private func periodChanged(_ sender: NSSegmentedControl) {
        periodDays = (sender.selectedSegment == 0) ? 7 : 30
        refresh()
    }

    // MARK: - Achievement Tile (3-column grid)

    private func createAchievementTile(_ a: Achievement, unlocked: Bool, size: CGFloat) -> NSView {
        let tile = NSView()
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 14

        if unlocked {
            tile.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
            tile.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
            tile.layer?.borderWidth = 1.5

            let shadow = NSShadow()
            shadow.shadowColor = NSColor.controlAccentColor.withAlphaComponent(0.15)
            shadow.shadowOffset = .zero
            shadow.shadowBlurRadius = 10
            tile.shadow = shadow
        } else {
            tile.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            tile.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.1).cgColor
            tile.layer?.borderWidth = 1
        }

        let emoji = NSTextField(labelWithString: a.emoji)
        emoji.font = NSFont.systemFont(ofSize: 28)
        emoji.alignment = .center
        emoji.translatesAutoresizingMaskIntoConstraints = false
        emoji.alphaValue = unlocked ? 1.0 : 0.25

        let title = NSTextField(labelWithString: a.title)
        title.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        title.alignment = .center
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        title.alphaValue = unlocked ? 1.0 : 0.4

        let desc = NSTextField(labelWithString: a.description)
        desc.font = NSFont.systemFont(ofSize: 9)
        desc.textColor = .secondaryLabelColor
        desc.alignment = .center
        desc.lineBreakMode = .byTruncatingTail
        desc.translatesAutoresizingMaskIntoConstraints = false
        desc.alphaValue = unlocked ? 0.8 : 0.3

        tile.addSubview(emoji)
        tile.addSubview(title)
        tile.addSubview(desc)

        NSLayoutConstraint.activate([
            emoji.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            emoji.topAnchor.constraint(equalTo: tile.topAnchor, constant: size * 0.18),

            title.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            title.topAnchor.constraint(equalTo: emoji.bottomAnchor, constant: 6),
            title.widthAnchor.constraint(lessThanOrEqualTo: tile.widthAnchor, constant: -12),

            desc.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            desc.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            desc.widthAnchor.constraint(lessThanOrEqualTo: tile.widthAnchor, constant: -12),
        ])

        if !unlocked {
            let lockIcon = NSTextField(labelWithString: "🔒")
            lockIcon.font = NSFont.systemFont(ofSize: 10)
            lockIcon.translatesAutoresizingMaskIntoConstraints = false
            tile.addSubview(lockIcon)
            NSLayoutConstraint.activate([
                lockIcon.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -8),
                lockIcon.topAnchor.constraint(equalTo: tile.topAnchor, constant: 8),
            ])
        }

        return tile
    }
}

// MARK: - Flipped View

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Bar Chart View

private class BarChartView: NSView {
    private let data: [(date: Date, count: Int)]

    init(data: [(date: Date, count: Int)]) {
        self.data = data
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !data.isEmpty else { return }

        let maxCount = max(data.map(\.count).max() ?? 1, 1)
        let yAxisWidth: CGFloat = 28
        let chartLeft = yAxisWidth
        let chartRight = bounds.width
        let chartBottom: CGFloat = 22
        let chartTop = bounds.height - 8
        let chartHeight = chartTop - chartBottom
        let barAreaWidth = chartRight - chartLeft
        let barWidth = barAreaWidth / CGFloat(data.count)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Grid lines
        let gridSteps = [0.0, 0.5, 1.0]
        for frac in gridSteps {
            let lineY = chartBottom + chartHeight * CGFloat(frac)
            let linePath = NSBezierPath()
            linePath.move(to: NSPoint(x: chartLeft, y: lineY))
            linePath.lineAt(to: NSPoint(x: chartRight, y: lineY))
            NSColor.separatorColor.withAlphaComponent(0.2).setStroke()
            linePath.lineWidth = 0.5
            let pattern: [CGFloat] = [4, 3]
            linePath.setLineDash(pattern, count: 2, phase: 0)
            linePath.stroke()
        }

        // Y-axis labels
        let yAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        ("0" as NSString).draw(at: NSPoint(x: 4, y: chartBottom - 5), withAttributes: yAttrs)
        let midLabel = "\(maxCount / 2)" as NSString
        midLabel.draw(at: NSPoint(x: 4, y: chartBottom + chartHeight * 0.5 - 5), withAttributes: yAttrs)
        let topLabel = "\(maxCount)" as NSString
        topLabel.draw(at: NSPoint(x: 4, y: chartTop - 5), withAttributes: yAttrs)

        // Bars
        let formatter = DateFormatter()
        formatter.dateFormat = data.count <= 7 ? "E" : "d"

        let accentColor = NSColor.controlAccentColor

        for (i, entry) in data.enumerated() {
            let x = chartLeft + CGFloat(i) * barWidth + barWidth * 0.15
            let w = barWidth * 0.7
            let h = chartHeight * CGFloat(entry.count) / CGFloat(maxCount)
            let barH = max(h, 2)

            let isToday = calendar.isDate(entry.date, inSameDayAs: today)
            let barRect = NSRect(x: x, y: chartBottom, width: w, height: barH)
            let path = NSBezierPath(roundedRect: barRect, xRadius: 4, yRadius: 4)

            if entry.count > 0 {
                // Gradient fill
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                let startColor = isToday
                    ? NSColor.systemPink.withAlphaComponent(0.9)
                    : accentColor.withAlphaComponent(0.6)
                let endColor = isToday
                    ? NSColor.systemOrange.withAlphaComponent(0.7)
                    : accentColor.withAlphaComponent(0.3)
                let gradient = NSGradient(starting: endColor, ending: startColor)
                gradient?.draw(in: barRect, angle: 90)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                NSColor.separatorColor.withAlphaComponent(0.15).setFill()
                path.fill()
            }

            // Day label
            let label = formatter.string(from: entry.date) as NSString
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: isToday ? .bold : .regular),
                .foregroundColor: isToday ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
            ]
            let labelSize = label.size(withAttributes: labelAttrs)
            let labelX = x + (w - labelSize.width) / 2
            label.draw(at: NSPoint(x: labelX, y: 4), withAttributes: labelAttrs)

            // Count on top
            if entry.count > 0 {
                let countStr = "\(entry.count)" as NSString
                let countAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: isToday ? NSColor.systemPink : NSColor.labelColor,
                ]
                let countSize = countStr.size(withAttributes: countAttrs)
                let countX = x + (w - countSize.width) / 2
                countStr.draw(at: NSPoint(x: countX, y: chartBottom + barH + 2), withAttributes: countAttrs)
            }
        }
    }
}

private extension NSBezierPath {
    func lineAt(to point: NSPoint) {
        line(to: point)
    }
}
