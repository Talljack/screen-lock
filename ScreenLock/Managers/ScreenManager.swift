import Cocoa
import CoreGraphics
import IOKit.pwr_mgt
import os.log

private let log = OSLog(subsystem: "com.yugangcao.screenlock", category: "Screen")

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

    /// Tracks whether any API capability is degraded.
    private(set) var statusMessage: String?

    private init() {
        saveOriginalGamma()
        observeDisplayChanges()
    }

    private func observeDisplayChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            os_log("Display configuration changed — refreshing gamma map", log: log, type: .info)
            self?.saveOriginalGamma()
        }
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

            guard result == .success else {
                os_log("Failed to read gamma for display %{public}d", log: log, type: .error, display)
                statusMessage = L("status.screen_unavailable")
                continue
            }

            originalGammaByDisplay[display] = (
                red: (redMin, redMax, redGamma),
                green: (greenMin, greenMax, greenGamma),
                blue: (blueMin, blueMax, blueGamma)
            )
        }

        os_log("Gamma saved for %d displays", log: log, type: .info, originalGammaByDisplay.count)
    }

    func startGradualDimming(durationMinutes: Int) {
        guard !isDimming else { return }
        isDimming = true
        saveOriginalGamma()

        os_log("Starting gradual dimming over %d minutes", log: log, type: .info, durationMinutes)

        let steps = max(durationMinutes * 2, 1)
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

    /// Stops dimming and restores original gamma. Safe to call even when not dimming.
    func cancelDimming() {
        guard isDimming else { return }
        isDimming = false
        dimmingTimer?.invalidate()
        dimmingTimer = nil
        restoreOriginalGamma()
        os_log("Dimming cancelled and gamma restored", log: log, type: .info)
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

    /// Check if displays are asleep (lid closed or display off)
    func areDisplaysAsleep() -> Bool {
        for display in activeDisplayIDs() {
            if CGDisplayIsAsleep(display) == 0 {
                return false
            }
        }
        return true
    }

    func lockScreenAndTurnOffDisplay(completion: (() -> Void)? = nil) {
        os_log("Showing forced break screen", log: log, type: .info)

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

        let settings = SettingsManager.shared.settings
        let event = LockEvent(
            date: Date(),
            lockTime: settings.lockTime,
            trigger: (ScheduleManager.shared.state == .locked) ? .scheduled : .manual,
            breakDurationSeconds: settings.forcedBreakMinutes * 60,
            completed: true
        )
        StatsManager.shared.record(event: event)

        closeLockWindows(force: true)
        performSystemLock()
        lockCompletion?()
        lockCompletion = nil
    }

    private func performSystemLock() {
        let sessionPaths = [
            "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
            "/usr/bin/pmset"
        ]

        for path in sessionPaths {
            if FileManager.default.fileExists(atPath: path) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: path)
                task.arguments = path.hasSuffix("CGSession") ? ["-suspend"] : ["displaysleepnow"]

                do {
                    try task.run()
                    os_log("System lock triggered via %{public}@", log: log, type: .info, path)
                    return
                } catch {
                    os_log("Failed with %{public}@: %{public}@", log: log, type: .error, path, error.localizedDescription)
                }
            }
        }

        os_log("No system lock method available, using display sleep", log: log, type: .info)
        statusMessage = L("status.lock_unavailable")
    }

    private func closeLockWindows(force: Bool) {
        lockTimer?.invalidate()
        lockTimer = nil

        let windows = lockWindows
        lockWindows.removeAll()

        for window in windows {
            if force {
                window.allowDismiss()
                window.orderOut(nil)
            } else {
                window.close()
            }
        }
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

        os_log("Original gamma restored", log: log, type: .info)
    }
}
