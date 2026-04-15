import Cocoa
import CoreGraphics

class ScreenManager {
    static let shared = ScreenManager()

    private typealias DisplayGamma = (
        red: (min: CGGammaValue, max: CGGammaValue, gamma: CGGammaValue),
        green: (min: CGGammaValue, max: CGGammaValue, gamma: CGGammaValue),
        blue: (min: CGGammaValue, max: CGGammaValue, gamma: CGGammaValue)
    )

    private var originalGammaByDisplay: [CGDirectDisplayID: DisplayGamma] = [:]

    private var isDimming = false
    private var dimmingTimer: Timer?
    private var lockWindows: [LockScreenWindow] = []
    private var lockTimer: Timer?
    private var remainingLockSeconds = 0
    private var isSystemLockTriggered = false
    private var lockCompletion: (() -> Void)?

    private init() {
        saveOriginalGamma()
    }

    private func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)

        guard count > 0 else { return [CGMainDisplayID()] }

        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        return Array(displays.prefix(Int(count)))
    }

    private func saveOriginalGamma() {
        originalGammaByDisplay.removeAll()

        for display in activeDisplayIDs() {
            var redMin: CGGammaValue = 0, redMax: CGGammaValue = 0, redGamma: CGGammaValue = 0
            var greenMin: CGGammaValue = 0, greenMax: CGGammaValue = 0, greenGamma: CGGammaValue = 0
            var blueMin: CGGammaValue = 0, blueMax: CGGammaValue = 0, blueGamma: CGGammaValue = 0

            let result = CGGetDisplayTransferByFormula(
                display,
                &redMin, &redMax, &redGamma,
                &greenMin, &greenMax, &greenGamma,
                &blueMin, &blueMax, &blueGamma
            )

            guard result == .success else { continue }

            originalGammaByDisplay[display] = (
                red: (redMin, redMax, redGamma),
                green: (greenMin, greenMax, greenGamma),
                blue: (blueMin, blueMax, blueGamma)
            )
        }

        print("ScreenManager: Original gamma saved")
    }

    func startGradualDimming(durationMinutes: Int) {
        guard !isDimming else { return }
        isDimming = true
        saveOriginalGamma()

        print("ScreenManager: Starting gradual dimming over \(durationMinutes) minutes")

        let steps = max(durationMinutes * 2, 1) // Every 30 seconds
        var currentStep = 0

        dimmingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] timer in
            currentStep += 1
            let progress = Float(currentStep) / Float(steps)

            self?.applyDimmingAndWarmth(progress: progress)

            if currentStep >= steps {
                timer.invalidate()
                self?.dimmingTimer = nil
            }
        }
    }

    private func applyDimmingAndWarmth(progress: Float) {
        for (display, original) in originalGammaByDisplay {
            let brightnessMultiplier = 1.0 - (0.7 * CGGammaValue(progress))
            let warmthFactor = CGGammaValue(progress) * 0.3

            let redMax = original.red.max * brightnessMultiplier * (1.0 + warmthFactor)
            let greenMax = original.green.max * brightnessMultiplier
            let blueMax = original.blue.max * brightnessMultiplier * (1.0 - warmthFactor)

            CGSetDisplayTransferByFormula(
                display,
                original.red.min, redMax, original.red.gamma,
                original.green.min, greenMax, original.green.gamma,
                original.blue.min, blueMax, original.blue.gamma
            )
        }
    }

    func lockScreenAndTurnOffDisplay(completion: (() -> Void)? = nil) {
        print("ScreenManager: Showing forced break screen")

        restoreOriginalGamma()
        isDimming = false
        dimmingTimer?.invalidate()
        dimmingTimer = nil

        closeLockWindows(force: true)

        let settings = SettingsManager.shared.settings.validated()
        let appearance = settings.appearance.withRandomCopyIfNeeded()
        remainingLockSeconds = settings.forcedBreakMinutes * 60
        lockCompletion = completion
        isSystemLockTriggered = false

        NSSound(named: "Glass")?.play()

        for screen in NSScreen.screens {
            let window = LockScreenWindow(
                screen: screen,
                remainingSeconds: remainingLockSeconds,
                appearance: appearance
            )
            lockWindows.append(window)
            window.orderFrontRegardless()
            window.animateIn()
        }

        NSApp.activate(ignoringOtherApps: true)

        // Make the first window key to capture keyboard events
        lockWindows.first?.makeKeyAndOrderFront(nil)

        startLockCountdown()
    }

    private func startLockCountdown() {
        lockTimer?.invalidate()
        updateLockWindows()

        lockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }

            self.remainingLockSeconds -= 1
            self.updateLockWindows()

            if self.remainingLockSeconds <= 0 {
                timer.invalidate()
                self.lockTimer = nil
                self.completeLockSequence()
            }
        }
    }

    private func updateLockWindows() {
        for window in lockWindows {
            window.updateRemainingSeconds(max(remainingLockSeconds, 0))
        }
    }

    private func completeLockSequence() {
        guard !isSystemLockTriggered else { return }
        isSystemLockTriggered = true

        closeLockWindows(force: true)
        performSystemLock()
        lockCompletion?()
        lockCompletion = nil
    }

    private func performSystemLock() {
        let task = Process()
        task.executableURL = URL(
            fileURLWithPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        )
        task.arguments = ["-suspend"]

        do {
            try task.run()
            print("ScreenManager: macOS system lock triggered")
        } catch {
            print("ScreenManager: Failed to trigger macOS system lock: \(error)")
        }
    }

    private func closeLockWindows(force: Bool) {
        lockTimer?.invalidate()
        lockTimer = nil

        for window in lockWindows {
            if force {
                window.dismissForSystemLock()
            } else {
                window.close()
            }
        }
        lockWindows.removeAll()
    }

    func restoreOriginalGamma() {
        for (display, original) in originalGammaByDisplay {
            CGSetDisplayTransferByFormula(
                display,
                original.red.min, original.red.max, original.red.gamma,
                original.green.min, original.green.max, original.green.gamma,
                original.blue.min, original.blue.max, original.blue.gamma
            )
        }

        print("ScreenManager: Original gamma restored")
    }
}
