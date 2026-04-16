import Cocoa

struct LockScreenPalette {
    let gradientColors: [NSColor]
    let overlayColor: NSColor
    let cardColor: NSColor
    let cardBorderColor: NSColor
    let accentColor: NSColor
    let secondaryTextColor: NSColor
    let footerTextColor: NSColor
    let symbol: String
}

extension LockScreenTheme {
    var palette: LockScreenPalette {
        switch self {
        case .peachBunny:
            return LockScreenPalette(
                gradientColors: [
                    NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.90, alpha: 1.0),
                    NSColor(calibratedRed: 1.0, green: 0.94, blue: 0.82, alpha: 1.0),
                    NSColor(calibratedRed: 0.98, green: 0.77, blue: 0.87, alpha: 1.0)
                ],
                overlayColor: NSColor(calibratedRed: 0.47, green: 0.16, blue: 0.28, alpha: 0.18),
                cardColor: NSColor(calibratedWhite: 1.0, alpha: 0.72),
                cardBorderColor: NSColor(calibratedRed: 0.96, green: 0.58, blue: 0.73, alpha: 0.45),
                accentColor: NSColor(calibratedRed: 0.91, green: 0.35, blue: 0.58, alpha: 1.0),
                secondaryTextColor: NSColor(calibratedRed: 0.51, green: 0.22, blue: 0.35, alpha: 1.0),
                footerTextColor: NSColor(calibratedRed: 0.56, green: 0.36, blue: 0.41, alpha: 1.0),
                symbol: "🐰"
            )
        case .cloudPudding:
            return LockScreenPalette(
                gradientColors: [
                    NSColor(calibratedRed: 0.78, green: 0.91, blue: 1.0, alpha: 1.0),
                    NSColor(calibratedRed: 0.99, green: 0.96, blue: 0.84, alpha: 1.0),
                    NSColor(calibratedRed: 0.82, green: 0.96, blue: 0.90, alpha: 1.0)
                ],
                overlayColor: NSColor(calibratedRed: 0.16, green: 0.30, blue: 0.42, alpha: 0.16),
                cardColor: NSColor(calibratedWhite: 1.0, alpha: 0.76),
                cardBorderColor: NSColor(calibratedRed: 0.42, green: 0.72, blue: 0.92, alpha: 0.32),
                accentColor: NSColor(calibratedRed: 0.31, green: 0.60, blue: 0.88, alpha: 1.0),
                secondaryTextColor: NSColor(calibratedRed: 0.18, green: 0.34, blue: 0.49, alpha: 1.0),
                footerTextColor: NSColor(calibratedRed: 0.30, green: 0.43, blue: 0.54, alpha: 1.0),
                symbol: "☁️"
            )
        case .starlightCat:
            return LockScreenPalette(
                gradientColors: [
                    NSColor(calibratedRed: 0.24, green: 0.22, blue: 0.45, alpha: 1.0),
                    NSColor(calibratedRed: 0.49, green: 0.33, blue: 0.58, alpha: 1.0),
                    NSColor(calibratedRed: 0.98, green: 0.74, blue: 0.78, alpha: 1.0)
                ],
                overlayColor: NSColor(calibratedRed: 0.06, green: 0.05, blue: 0.15, alpha: 0.28),
                cardColor: NSColor(calibratedRed: 0.15, green: 0.14, blue: 0.27, alpha: 0.70),
                cardBorderColor: NSColor(calibratedRed: 0.98, green: 0.79, blue: 0.84, alpha: 0.25),
                accentColor: NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.58, alpha: 1.0),
                secondaryTextColor: NSColor(calibratedRed: 0.97, green: 0.92, blue: 0.97, alpha: 1.0),
                footerTextColor: NSColor(calibratedRed: 0.90, green: 0.84, blue: 0.94, alpha: 1.0),
                symbol: "🌟"
            )
        }
    }
}

private final class LockScreenBackgroundView: NSView {
    private let gradientLayer = CAGradientLayer()
    private let overlayLayer = CALayer()
    private let imageView = NSImageView()
    private var dynamicBgView: DynamicBackgroundView?

    init(palette: LockScreenPalette, theme: LockScreenTheme, backgroundImagePath: String?) {
        super.init(frame: .zero)
        wantsLayer = true

        gradientLayer.colors = palette.gradientColors.map(\.cgColor)
        gradientLayer.startPoint = CGPoint(x: 0, y: 1)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(gradientLayer)

        let hasCustomImage = backgroundImagePath != nil && !backgroundImagePath!.isEmpty

        if hasCustomImage {
            imageView.imageScaling = .scaleAxesIndependently
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
                imageView.topAnchor.constraint(equalTo: topAnchor),
                imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            imageView.image = NSImage(contentsOfFile: backgroundImagePath!)
        } else {
            let bgView = DynamicBackgroundView(theme: theme)
            bgView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(bgView)
            NSLayoutConstraint.activate([
                bgView.leadingAnchor.constraint(equalTo: leadingAnchor),
                bgView.trailingAnchor.constraint(equalTo: trailingAnchor),
                bgView.topAnchor.constraint(equalTo: topAnchor),
                bgView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            dynamicBgView = bgView
        }

        overlayLayer.backgroundColor = palette.overlayColor.cgColor
        layer?.addSublayer(overlayLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
        overlayLayer.frame = bounds
    }
}

class LockScreenWindow: NSWindow {
    private let lockAppearance: LockScreenAppearance
    private let palette: LockScreenPalette
    private var countdownLabel: NSTextField?
    private var cardView: NSVisualEffectView?
    private var allowClose = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(screen: NSScreen, remainingSeconds: Int, appearance: LockScreenAppearance) {
        self.lockAppearance = appearance.validated()
        self.palette = appearance.theme.palette

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        setFrame(screen.frame, display: false)
        alphaValue = 0
        setupWindow()
        setupUI(remainingSeconds: remainingSeconds)
    }

    func animateIn() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.6
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }

        if let card = cardView?.layer {
            card.transform = CATransform3DMakeTranslation(0, -40, 0)
            let spring = CASpringAnimation(keyPath: "transform.translation.y")
            spring.fromValue = -40
            spring.toValue = 0
            spring.mass = 1.0
            spring.stiffness = 120
            spring.damping = 14
            spring.initialVelocity = 0
            spring.duration = spring.settlingDuration
            card.add(spring, forKey: "cardEntrance")
            card.transform = CATransform3DIdentity
        }
    }

    private func setupWindow() {
        // NSWindow.Level 值越高越在前面。screenSaver = 1000，
        // 但某些全屏 app 可能挡住它。用更高的 level 确保覆盖一切。
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        isMovable = false
        canHide = false
        hasShadow = false

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func setupUI(remainingSeconds: Int) {
        let backgroundView = LockScreenBackgroundView(
            palette: palette,
            theme: lockAppearance.theme,
            backgroundImagePath: lockAppearance.backgroundImagePath
        )
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentView = backgroundView

        let card = NSVisualEffectView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.material = .hudWindow
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.backgroundColor = palette.cardColor.cgColor
        card.layer?.borderColor = palette.cardBorderColor.cgColor
        card.layer?.borderWidth = 1.0
        card.layer?.cornerRadius = 34
        backgroundView.addSubview(card)
        self.cardView = card

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        card.addSubview(stack)

        let badge = makeLabel(
            "\(palette.symbol)  \(lockAppearance.theme.displayName)",
            size: 17, weight: .semibold
        )
        badge.textColor = palette.secondaryTextColor
        badge.alignment = .center
        stack.addArrangedSubview(badge)

        let titleLabel = makeLabel(lockAppearance.titleText, size: 34, weight: .bold)
        titleLabel.maximumNumberOfLines = 2
        titleLabel.textColor = palette.secondaryTextColor
        titleLabel.alignment = .center
        stack.addArrangedSubview(titleLabel)

        let subtitleLabel = makeLabel(lockAppearance.subtitleText, size: 18, weight: .medium)
        subtitleLabel.maximumNumberOfLines = 3
        subtitleLabel.textColor = palette.secondaryTextColor.withAlphaComponent(0.92)
        subtitleLabel.alignment = .center
        stack.addArrangedSubview(subtitleLabel)

        let countdownContainer = NSView()
        countdownContainer.translatesAutoresizingMaskIntoConstraints = false
        countdownContainer.wantsLayer = true
        countdownContainer.layer?.backgroundColor = palette.accentColor.withAlphaComponent(0.12).cgColor
        countdownContainer.layer?.cornerRadius = 24
        countdownContainer.layer?.borderWidth = 1
        countdownContainer.layer?.borderColor = palette.accentColor.withAlphaComponent(0.25).cgColor
        stack.addArrangedSubview(countdownContainer)

        countdownLabel = makeLabel(formatTime(remainingSeconds), size: 54, weight: .bold, monospaced: true)
        countdownLabel?.translatesAutoresizingMaskIntoConstraints = false
        countdownLabel?.textColor = palette.accentColor
        countdownLabel?.alignment = .center
        countdownContainer.addSubview(countdownLabel!)

        let footerLabel = makeLabel(lockAppearance.footerText, size: 15, weight: .medium)
        footerLabel.maximumNumberOfLines = 4
        footerLabel.textColor = palette.footerTextColor
        footerLabel.alignment = .center
        stack.addArrangedSubview(footerLabel)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 620),
            card.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: backgroundView.leadingAnchor, constant: 32),
            card.trailingAnchor.constraint(lessThanOrEqualTo: backgroundView.trailingAnchor, constant: -32),

            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -40),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 36),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -36),

            countdownContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            countdownContainer.heightAnchor.constraint(equalToConstant: 116),

            countdownLabel!.centerXAnchor.constraint(equalTo: countdownContainer.centerXAnchor),
            countdownLabel!.centerYAnchor.constraint(equalTo: countdownContainer.centerYAnchor)
        ])
    }

    func updateRemainingSeconds(_ seconds: Int) {
        countdownLabel?.stringValue = formatTime(seconds)
        pulseCountdown()
    }

    private func pulseCountdown() {
        guard let label = countdownLabel else { return }
        label.wantsLayer = true
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1.0, 1.03, 1.0]
        pulse.keyTimes = [0, 0.3, 1.0]
        pulse.duration = 0.4
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        label.layer?.add(pulse, forKey: "pulse")
    }

    func dismissForSystemLock() {
        allowClose = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.close()
        })
    }

    override func close() {
        if !allowClose {
            NSSound.beep()
            return
        }
        super.close()
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            NSSound.beep()
            return
        }
        super.keyDown(with: event)
    }

    private func makeLabel(
        _ text: String, size: CGFloat, weight: NSFont.Weight, monospaced: Bool = false
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byWordWrapping
        label.font = monospaced
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : roundedFont(size: size, weight: weight)
        return label
    }

    private func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let desc = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: desc, size: size) ?? base
    }

    private func formatTime(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
