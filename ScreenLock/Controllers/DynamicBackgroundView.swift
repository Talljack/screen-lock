import Cocoa
import QuartzCore

/// Animated background view using Core Animation.
/// Each theme gets a unique particle / motion effect rendered on the GPU.
final class DynamicBackgroundView: NSView {

    private let theme: LockScreenTheme

    init(theme: LockScreenTheme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        setupAnimations()
    }

    private func setupAnimations() {
        switch theme {
        case .peachBunny:  setupPeachBunny()
        case .cloudPudding: setupCloudPudding()
        case .starlightCat: setupStarlightCat()
        }
    }

    // MARK: - Peach Bunny — floating hearts + petal particles + breathing gradient

    private func setupPeachBunny() {
        addBreathingGradient(
            colors: [
                NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.90, alpha: 1.0),
                NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.86, alpha: 1.0),
            ],
            period: 4.0
        )

        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: -20)
        emitter.emitterSize = CGSize(width: bounds.width * 1.2, height: 1)
        emitter.emitterShape = .line
        emitter.renderMode = .additive

        let heart = makeCell(
            content: heartImage(size: 14, color: NSColor(calibratedRed: 1.0, green: 0.5, blue: 0.65, alpha: 0.7)),
            birthRate: 3, lifetime: 12, velocity: 30, velocityRange: 15,
            yAcceleration: 8, scale: 0.5, scaleRange: 0.3, spinRange: 0.3,
            alphaRange: 0.3, alphaSpeed: -0.04
        )

        let petal = makeCell(
            content: ovalImage(size: 8, color: NSColor(calibratedRed: 1.0, green: 0.75, blue: 0.82, alpha: 0.5)),
            birthRate: 5, lifetime: 14, velocity: 20, velocityRange: 10,
            yAcceleration: 6, scale: 0.4, scaleRange: 0.2, spinRange: 0.8,
            alphaRange: 0.2, alphaSpeed: -0.03
        )

        emitter.emitterCells = [heart, petal]
        layer?.addSublayer(emitter)
    }

    // MARK: - Cloud Pudding — drifting clouds + twinkling stars

    private func setupCloudPudding() {
        let starCount = 25
        for _ in 0..<starCount {
            let star = CALayer()
            let size: CGFloat = CGFloat.random(in: 2...5)
            star.frame = CGRect(
                x: CGFloat.random(in: 0...max(bounds.width, 800)),
                y: CGFloat.random(in: 0...max(bounds.height, 600)),
                width: size, height: size
            )
            star.cornerRadius = size / 2
            star.backgroundColor = NSColor.white.withAlphaComponent(0.7).cgColor

            let twinkle = CABasicAnimation(keyPath: "opacity")
            twinkle.fromValue = 0.2
            twinkle.toValue = 0.9
            twinkle.duration = Double.random(in: 1.5...3.5)
            twinkle.autoreverses = true
            twinkle.repeatCount = .infinity
            twinkle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            twinkle.beginTime = CACurrentMediaTime() + Double.random(in: 0...2)
            star.add(twinkle, forKey: "twinkle")

            layer?.addSublayer(star)
        }

        for i in 0..<4 {
            let cloud = makeCloudLayer(
                width: CGFloat.random(in: 120...220),
                height: CGFloat.random(in: 40...70),
                opacity: Float.random(in: 0.15...0.35)
            )
            let startY = CGFloat(80 + i * 120) + CGFloat.random(in: -30...30)
            cloud.frame.origin = CGPoint(x: -cloud.frame.width, y: startY)
            layer?.addSublayer(cloud)

            let drift = CABasicAnimation(keyPath: "position.x")
            drift.fromValue = -cloud.frame.width
            drift.toValue = max(bounds.width, 1200) + cloud.frame.width
            drift.duration = Double.random(in: 30...55)
            drift.repeatCount = .infinity
            drift.beginTime = CACurrentMediaTime() + Double(i) * 6.0
            cloud.add(drift, forKey: "drift")
        }
    }

    // MARK: - Starlight Cat — twinkling stars + shooting stars

    private func setupStarlightCat() {
        let starCount = 50
        for _ in 0..<starCount {
            let star = CALayer()
            let size: CGFloat = CGFloat.random(in: 1.5...4)
            star.frame = CGRect(
                x: CGFloat.random(in: 0...max(bounds.width, 1000)),
                y: CGFloat.random(in: 0...max(bounds.height, 700)),
                width: size, height: size
            )
            star.cornerRadius = size / 2
            let brightness = CGFloat.random(in: 0.7...1.0)
            star.backgroundColor = NSColor(
                calibratedRed: brightness, green: brightness,
                blue: min(brightness + 0.1, 1.0), alpha: 0.8
            ).cgColor

            let twinkle = CABasicAnimation(keyPath: "opacity")
            twinkle.fromValue = Float.random(in: 0.1...0.3)
            twinkle.toValue = Float.random(in: 0.7...1.0)
            twinkle.duration = Double.random(in: 1.0...4.0)
            twinkle.autoreverses = true
            twinkle.repeatCount = .infinity
            twinkle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            twinkle.beginTime = CACurrentMediaTime() + Double.random(in: 0...3)
            star.add(twinkle, forKey: "twinkle")

            layer?.addSublayer(star)
        }

        addMoonGlow()
        scheduleShootingStar()
    }

    // MARK: - Shared helpers

    private func addBreathingGradient(colors: [NSColor], period: Double) {
        let glow = CALayer()
        glow.frame = bounds.isEmpty
            ? CGRect(x: 0, y: 0, width: 1200, height: 800)
            : bounds
        glow.backgroundColor = colors.first?.withAlphaComponent(0.15).cgColor

        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 0.3
        breathe.toValue = 0.6
        breathe.duration = period
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.add(breathe, forKey: "breathe")

        layer?.addSublayer(glow)
    }

    private func addMoonGlow() {
        let moonSize: CGFloat = 60
        let moon = CALayer()
        moon.frame = CGRect(
            x: max(bounds.width, 800) * 0.78,
            y: max(bounds.height, 600) * 0.72,
            width: moonSize, height: moonSize
        )
        moon.cornerRadius = moonSize / 2
        moon.backgroundColor = NSColor(
            calibratedRed: 1.0, green: 0.95, blue: 0.75, alpha: 0.35
        ).cgColor

        let glow = CABasicAnimation(keyPath: "transform.scale")
        glow.fromValue = 1.0
        glow.toValue = 1.2
        glow.duration = 3.0
        glow.autoreverses = true
        glow.repeatCount = .infinity
        glow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        moon.add(glow, forKey: "glow")

        layer?.addSublayer(moon)
    }

    private var shootingStarTimer: Timer?

    private func scheduleShootingStar() {
        shootingStarTimer?.invalidate()
        shootingStarTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 4...9), repeats: false) {
            [weak self] _ in
            self?.launchShootingStar()
            self?.scheduleShootingStar()
        }
    }

    private func launchShootingStar() {
        let meteor = CALayer()
        meteor.frame = CGRect(x: 0, y: 0, width: 3, height: 3)
        meteor.cornerRadius = 1.5
        meteor.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor

        let w = max(bounds.width, 1000)
        let h = max(bounds.height, 700)
        let startX = CGFloat.random(in: w * 0.2...w * 0.9)
        let startY = CGFloat.random(in: h * 0.5...h * 0.9)
        let endX = startX - CGFloat.random(in: 150...350)
        let endY = startY - CGFloat.random(in: 100...250)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: startX, y: startY))
        path.addLine(to: CGPoint(x: endX, y: endY))

        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.duration = Double.random(in: 0.5...1.0)
        move.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = move.duration

        let group = CAAnimationGroup()
        group.animations = [move, fade]
        group.duration = move.duration
        group.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setCompletionBlock { meteor.removeFromSuperlayer() }
        layer?.addSublayer(meteor)
        meteor.add(group, forKey: "shoot")
        CATransaction.commit()
    }

    private func makeCloudLayer(width: CGFloat, height: CGFloat, opacity: Float) -> CALayer {
        let cloud = CALayer()
        cloud.frame = CGRect(x: 0, y: 0, width: width, height: height)
        cloud.opacity = opacity

        let blobCount = Int.random(in: 3...5)
        for i in 0..<blobCount {
            let blob = CALayer()
            let blobW = CGFloat.random(in: width * 0.3...width * 0.6)
            let blobH = CGFloat.random(in: height * 0.5...height * 0.9)
            blob.frame = CGRect(
                x: CGFloat(i) * (width / CGFloat(blobCount)),
                y: CGFloat.random(in: 0...(height - blobH)),
                width: blobW, height: blobH
            )
            blob.cornerRadius = min(blobW, blobH) / 2
            blob.backgroundColor = NSColor.white.cgColor
            cloud.addSublayer(blob)
        }

        return cloud
    }

    private func makeCell(
        content: CGImage?,
        birthRate: Float, lifetime: Float, velocity: CGFloat, velocityRange: CGFloat,
        yAcceleration: CGFloat, scale: CGFloat, scaleRange: CGFloat, spinRange: CGFloat,
        alphaRange: Float, alphaSpeed: Float
    ) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = content
        cell.birthRate = birthRate
        cell.lifetime = lifetime
        cell.velocity = velocity
        cell.velocityRange = velocityRange
        cell.yAcceleration = yAcceleration
        cell.scale = scale
        cell.scaleRange = scaleRange
        cell.spin = 0
        cell.spinRange = spinRange
        cell.alphaRange = alphaRange
        cell.alphaSpeed = alphaSpeed
        cell.emissionRange = .pi
        return cell
    }

    private func heartImage(size: CGFloat, color: NSColor) -> CGImage? {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            let path = NSBezierPath()
            let w = rect.width
            let h = rect.height
            path.move(to: NSPoint(x: w / 2, y: h * 0.15))
            path.curve(to: NSPoint(x: w * 0.05, y: h * 0.6),
                        controlPoint1: NSPoint(x: w / 2, y: 0),
                        controlPoint2: NSPoint(x: 0, y: h * 0.2))
            path.curve(to: NSPoint(x: w / 2, y: h),
                        controlPoint1: NSPoint(x: w * 0.1, y: h * 0.9),
                        controlPoint2: NSPoint(x: w / 2, y: h * 0.85))
            path.curve(to: NSPoint(x: w * 0.95, y: h * 0.6),
                        controlPoint1: NSPoint(x: w / 2, y: h * 0.85),
                        controlPoint2: NSPoint(x: w * 0.9, y: h * 0.9))
            path.curve(to: NSPoint(x: w / 2, y: h * 0.15),
                        controlPoint1: NSPoint(x: w, y: h * 0.2),
                        controlPoint2: NSPoint(x: w / 2, y: 0))
            path.fill()
            return true
        }
        var rect = NSRect(x: 0, y: 0, width: size, height: size)
        return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private func ovalImage(size: CGFloat, color: NSColor) -> CGImage? {
        let img = NSImage(size: NSSize(width: size, height: size * 1.5), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        var rect = NSRect(x: 0, y: 0, width: size, height: size * 1.5)
        return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    override func layout() {
        super.layout()
        layer?.sublayers?.forEach { sub in
            if let emitter = sub as? CAEmitterLayer {
                emitter.emitterPosition = CGPoint(x: bounds.midX, y: -20)
                emitter.emitterSize = CGSize(width: bounds.width * 1.2, height: 1)
            }
        }
    }

    deinit {
        shootingStarTimer?.invalidate()
    }
}
