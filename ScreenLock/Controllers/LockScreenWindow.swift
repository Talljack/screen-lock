import Cocoa

class LockScreenWindow: NSWindow {
    private var remainingSeconds: Int
    private var timer: Timer?
    private var countdownLabel: NSTextField?
    private var messageLabel: NSTextField?

    init(durationMinutes: Int) {
        self.remainingSeconds = durationMinutes * 60

        // Get screen frame
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        setupWindow()
        setupUI()
        startCountdown()
    }

    private func setupWindow() {
        // Make window cover everything
        self.level = .screenSaver  // Above all other windows
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isOpaque = true
        self.backgroundColor = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)
        self.ignoresMouseEvents = false
        self.isMovable = false
        self.canHide = false

        // Prevent closing
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func setupUI() {
        guard let contentView = self.contentView else { return }

        // Container view
        let containerView = NSView(frame: contentView.bounds)
        containerView.autoresizingMask = [.width, .height]
        contentView.addSubview(containerView)

        // Icon (moon)
        let iconLabel = NSTextField(labelWithString: "🌙")
        iconLabel.font = NSFont.systemFont(ofSize: 80)
        iconLabel.alignment = .center
        iconLabel.textColor = .white
        iconLabel.frame = NSRect(
            x: (contentView.bounds.width - 200) / 2,
            y: contentView.bounds.height / 2 + 100,
            width: 200,
            height: 100
        )
        iconLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        containerView.addSubview(iconLabel)

        // Message label
        messageLabel = NSTextField(labelWithString: "强制休息时间")
        messageLabel?.font = NSFont.systemFont(ofSize: 32, weight: .medium)
        messageLabel?.alignment = .center
        messageLabel?.textColor = .white
        messageLabel?.frame = NSRect(
            x: (contentView.bounds.width - 400) / 2,
            y: contentView.bounds.height / 2 + 20,
            width: 400,
            height: 50
        )
        messageLabel?.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        containerView.addSubview(messageLabel!)

        // Countdown label
        countdownLabel = NSTextField(labelWithString: formatTime(remainingSeconds))
        countdownLabel?.font = NSFont.monospacedDigitSystemFont(ofSize: 72, weight: .bold)
        countdownLabel?.alignment = .center
        countdownLabel?.textColor = NSColor(calibratedRed: 0.4, green: 0.8, blue: 1.0, alpha: 1.0)
        countdownLabel?.frame = NSRect(
            x: (contentView.bounds.width - 400) / 2,
            y: contentView.bounds.height / 2 - 80,
            width: 400,
            height: 100
        )
        countdownLabel?.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        containerView.addSubview(countdownLabel!)

        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: "休息一下，保护眼睛和身体")
        subtitleLabel.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        subtitleLabel.alignment = .center
        subtitleLabel.textColor = NSColor(white: 0.7, alpha: 1.0)
        subtitleLabel.frame = NSRect(
            x: (contentView.bounds.width - 400) / 2,
            y: contentView.bounds.height / 2 - 140,
            width: 400,
            height: 30
        )
        subtitleLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        containerView.addSubview(subtitleLabel)

        // Tips
        let tips = [
            "💧 喝杯水",
            "👀 远眺窗外",
            "🧘 伸展身体",
            "🚶 走动一下"
        ]

        let tipsLabel = NSTextField(labelWithString: tips.joined(separator: "   "))
        tipsLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        tipsLabel.alignment = .center
        tipsLabel.textColor = NSColor(white: 0.5, alpha: 1.0)
        tipsLabel.frame = NSRect(
            x: (contentView.bounds.width - 600) / 2,
            y: 100,
            width: 600,
            height: 30
        )
        tipsLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        containerView.addSubview(tipsLabel)
    }

    private func startCountdown() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            self.remainingSeconds -= 1
            self.countdownLabel?.stringValue = self.formatTime(self.remainingSeconds)

            if self.remainingSeconds <= 0 {
                self.unlockScreen()
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func unlockScreen() {
        timer?.invalidate()
        timer = nil

        // Fade out animation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.close()
        })
    }

    // Override to prevent closing
    override func close() {
        if remainingSeconds > 0 {
            // Don't allow closing until time is up
            NSSound.beep()
            return
        }
        super.close()
    }

    // Prevent Cmd+Q and other shortcuts
    override func keyDown(with event: NSEvent) {
        // Block all keyboard shortcuts
        if event.modifierFlags.contains(.command) {
            NSSound.beep()
            return
        }
        super.keyDown(with: event)
    }
}
