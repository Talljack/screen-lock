import Cocoa
import CoreGraphics
import IOKit.pwr_mgt
import os.log

private let log = OSLog(subsystem: "com.yugangcao.screenlock", category: "Screen")

class ScreenManager {
    static let shared = ScreenManager()

    struct SleepTransitionState: Equatable {
        var inactiveSince: Date?
        var lastWakeAt: Date?

        func crossed(_ moment: Date, now: Date) -> Bool {
            guard let inactiveSince, inactiveSince <= moment else { return false }
            let wakeReference = lastWakeAt ?? now
            return wakeReference >= moment
        }
    }

    struct SoftnessProfile: Equatable {
        let brightnessReduction: Double
        let warmthStrength: Double
        let manualStrengthProgress: Float
    }

    private typealias DisplayGamma = (
        red: (min: CGGammaValue, max: CGGammaValue, gamma: CGGammaValue),
        green: (min: CGGammaValue, max: CGGammaValue, gamma: CGGammaValue),
        blue: (min: CGGammaValue, max: CGGammaValue, gamma: CGGammaValue)
    )

    private var originalGammaByDisplay: [CGDirectDisplayID: DisplayGamma] = [:]

    private var isDimming = false
    private var dimmingTimer: Timer?
    private var dimmingStartDate: Date?
    private var dimmingDurationSeconds: TimeInterval = 0
    private var currentDimmingProgress: Float = 0
    private var lockWindows: [LockScreenWindow] = []
    private var lockTimer: DispatchSourceTimer?
    private var remainingLockSeconds = 0
    private var isCompletingLockSequence = false
    private var lockCompletion: (() -> Void)?
    private var currentLockAppearance: LockScreenAppearance?
    private var currentLockTrigger: LockEvent.Trigger = .manual
    private var currentScheduledLockTime: String?
    private var previousActivationPolicy: NSApplication.ActivationPolicy?
    private var previousPresentationOptions: NSApplication.PresentationOptions = []
    private var isLockModeActive = false
    private var isAwaitingLockActivation = false
    private var hasPresentedLockWindows = false
    private var sleepTransitionState = SleepTransitionState()
    private var notificationObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var reactivationWorkItems: [DispatchWorkItem] = []
    private var previewRestoreWorkItem: DispatchWorkItem?
    private var isManualSoftnessPreviewActive = false
    private var isApplyingGammaUpdate = false
    private var isApplyingLockModeTransition = false
    /// Tracks whether any API capability is degraded.
    private(set) var statusMessage: String?

    private init() {
        restoreSystemColorState(resyncBaseline: true)
        observeDisplayChanges()
        observeApplicationChanges()
    }

    private func cancelLockTimer(reason: String) {
        guard let lockTimer else { return }
        os_log(
            "Cancelling lock countdown at %d seconds (%{public}@)",
            log: log,
            type: .info,
            remainingLockSeconds,
            reason
        )
        lockTimer.cancel()
        self.lockTimer = nil
    }

    private func observeDisplayChanges() {
        let observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            guard !self.isApplyingGammaUpdate else { return }
            if self.isApplyingLockModeTransition {
                os_log(
                    "Display configuration changed during lock mode transition — skipping rebuild",
                    log: log,
                    type: .info
                )
                self.saveOriginalGamma()
                return
            }
            os_log(
                "Display configuration changed — refreshing gamma map (lockActive=%{public}@, windows=%d, remaining=%d)",
                log: log,
                type: .info,
                self.isLockModeActive ? "true" : "false",
                self.lockWindows.count,
                self.remainingLockSeconds
            )
            self.saveOriginalGamma()
            self.rebuildLockWindowsIfNeeded(animated: false)
        }
        notificationObservers.append(observer)
    }

    private func observeApplicationChanges() {
        let appDidBecomeActive = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            os_log(
                "App became active (lockActive=%{public}@, awaiting=%{public}@, presented=%{public}@)",
                log: log,
                type: .info,
                self.isLockModeActive ? "true" : "false",
                self.isAwaitingLockActivation ? "true" : "false",
                self.hasPresentedLockWindows ? "true" : "false"
            )
            self.completePendingLockPresentationIfNeeded()
        }
        notificationObservers.append(appDidBecomeActive)

        let appDidResignActive = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            os_log(
                "App resigned active (lockActive=%{public}@, windows=%d)",
                log: log,
                type: .info,
                self.isLockModeActive ? "true" : "false",
                self.lockWindows.count
            )
            self.reactivateLockModeIfNeeded()
        }
        notificationObservers.append(appDidResignActive)

        let workspaceCenter = NSWorkspace.shared.notificationCenter

        let activeSpaceChanged = workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            os_log(
                "Active space changed (lockActive=%{public}@, windows=%d)",
                log: log,
                type: .info,
                self.isLockModeActive ? "true" : "false",
                self.lockWindows.count
            )
            self.reactivateLockModeIfNeeded()
        }
        workspaceObservers.append(activeSpaceChanged)

        let screensDidSleep = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemInactivityStarted(reason: "screens slept")
        }
        workspaceObservers.append(screensDidSleep)

        let screensDidWake = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWake(reason: "screens woke")
        }
        workspaceObservers.append(screensDidWake)

        let willSleep = workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemInactivityStarted(reason: "system will sleep")
        }
        workspaceObservers.append(willSleep)

        let didWake = workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWake(reason: "system woke")
        }
        workspaceObservers.append(didWake)
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

    private func restoreSystemColorState(resyncBaseline: Bool) {
        isApplyingGammaUpdate = true
        defer { isApplyingGammaUpdate = false }

        // Restore the display pipeline back to the system-managed ColorSync state
        // so turning softness "off" removes only ScreenLock's tint instead of
        // restoring a previously tinted baseline.
        CGDisplayRestoreColorSyncSettings()

        if resyncBaseline {
            saveOriginalGamma()
        }
    }

    private func ensureOriginalGamma() {
        guard originalGammaByDisplay.isEmpty else { return }
        saveOriginalGamma()
    }

    func startGradualDimming(
        durationMinutes: Int,
        softnessLevel: WarningSoftnessLevel,
        initialProgress: Float = 0
    ) {
        guard softnessLevel != .off else {
            cancelDimming()
            return
        }

        if !isDimming {
            isDimming = true
            ensureOriginalGamma()
        }

        let clampedProgress = min(max(initialProgress, 0), 1)
        dimmingDurationSeconds = max(Double(durationMinutes) * 60, 1)
        dimmingStartDate = Date().addingTimeInterval(-dimmingDurationSeconds * Double(clampedProgress))
        currentDimmingProgress = clampedProgress

        os_log(
            "Starting gradual dimming over %d minutes at progress %.2f",
            log: log,
            type: .info,
            durationMinutes,
            clampedProgress
        )

        applyDimmingAndWarmth(progress: clampedProgress, softnessLevel: softnessLevel)
        ensureDimmingTimer()
    }

    /// Stops dimming and restores original gamma. Safe to call even when not dimming.
    func cancelDimming() {
        guard isDimming else { return }
        isDimming = false
        dimmingTimer?.invalidate()
        dimmingTimer = nil
        dimmingStartDate = nil
        dimmingDurationSeconds = 0
        currentDimmingProgress = 0
        restoreOriginalGamma()
        os_log("Dimming cancelled and gamma restored", log: log, type: .info)
    }

    func refreshWarningDimming(
        progress: Float,
        durationMinutes: Int,
        softnessLevel: WarningSoftnessLevel
    ) {
        startGradualDimming(
            durationMinutes: durationMinutes,
            softnessLevel: softnessLevel,
            initialProgress: progress
        )
    }

    func applySoftnessSelectionPreview() {
        previewRestoreWorkItem?.cancel()
        previewRestoreWorkItem = nil

        applyCurrentSoftnessSetting()
    }

    func applyCurrentSoftnessSetting() {
        previewRestoreWorkItem?.cancel()
        previewRestoreWorkItem = nil

        SunCycleManager.shared.requestLocationIfNeeded()

        let settings = SettingsManager.shared.settings.validated()
        let level = settings.warningSoftnessLevel
        let profile = resolvedSoftnessProfile(for: settings.warningSoftnessLevel)

        if ScheduleManager.shared.isInWarningState {
            isManualSoftnessPreviewActive = false
            refreshWarningDimming(
                progress: currentDimmingProgress,
                durationMinutes: settings.warningMinutes,
                softnessLevel: level
            )
            return
        }

        applyManualSoftness(level, profile: profile)
    }

    func clearManualSoftnessPreviewIfNeeded() {
        guard isManualSoftnessPreviewActive else { return }
        isManualSoftnessPreviewActive = false
        restoreOriginalGamma()
    }

    private func applyManualSoftness(_ level: WarningSoftnessLevel, profile: SoftnessProfile) {
        isManualSoftnessPreviewActive = level != .off
        cancelDimming()

        guard level != .off else {
            restoreOriginalGamma()
            return
        }

        restoreOriginalGamma()
        ensureOriginalGamma()
        applyDimmingAndWarmth(progress: profile.manualStrengthProgress, softnessLevel: level, profile: profile)
    }

    private func resolvedSoftnessProfile(for level: WarningSoftnessLevel, now: Date = Date()) -> SoftnessProfile {
        guard level == .smart else {
            return SoftnessProfile(
                brightnessReduction: level.brightnessReduction,
                warmthStrength: level.warmthStrength,
                manualStrengthProgress: level.manualStrengthProgress
            )
        }

        let bias = SettingsManager.shared.settings.validated().smartSoftnessBias

        if let solarProfile = resolvedSolarSoftnessProfile(now: now, bias: bias) {
            return solarProfile
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let hour = Double(components.hour ?? 0)
        let minute = Double(components.minute ?? 0)
        let currentHour = hour + (minute / 60.0)

        let brightness = interpolatedValue(
            at: currentHour,
            points: [
                (0.0, 0.16),
                (2.0, 0.20),
                (6.0, 0.10),
                (9.0, 0.05),
                (12.0, 0.04),
                (18.0, 0.07),
                (21.0, 0.11),
                (23.0, 0.15),
                (24.0, 0.16),
            ]
        )

        let warmth = interpolatedValue(
            at: currentHour,
            points: [
                (0.0, 0.13),
                (2.0, 0.16),
                (6.0, 0.08),
                (9.0, 0.04),
                (12.0, 0.03),
                (18.0, 0.06),
                (21.0, 0.10),
                (23.0, 0.13),
                (24.0, 0.13),
            ]
        )

        let progress = interpolatedValue(
            at: currentHour,
            points: [
                (0.0, 0.62),
                (2.0, 0.72),
                (6.0, 0.48),
                (9.0, 0.32),
                (12.0, 0.28),
                (18.0, 0.38),
                (21.0, 0.50),
                (23.0, 0.60),
                (24.0, 0.62),
            ]
        )

        return scaledSmartProfile(
            brightnessReduction: brightness,
            warmthStrength: warmth,
            manualStrengthProgress: progress,
            bias: bias
        )
    }

    func debugResolvedSoftnessProfile(for level: WarningSoftnessLevel, now: Date = Date()) -> SoftnessProfile {
        resolvedSoftnessProfile(for: level, now: now)
    }

    func debugResolvedSolarSoftnessProfile(
        now: Date,
        sunrise: Date,
        sunset: Date,
        bias: Double
    ) -> SoftnessProfile {
        resolvedSolarSoftnessProfile(
            now: now,
            sunrise: sunrise,
            sunset: sunset,
            bias: bias
        ) ?? SoftnessProfile(brightnessReduction: 0.12, warmthStrength: 0.10, manualStrengthProgress: 0.55)
    }

    private func resolvedSolarSoftnessProfile(
        now: Date,
        bias: Double
    ) -> SoftnessProfile? {
        guard let sunTimes = SunCycleManager.shared.currentSunTimes(now: now) else { return nil }
        return resolvedSolarSoftnessProfile(
            now: now,
            sunrise: sunTimes.sunrise,
            sunset: sunTimes.sunset,
            bias: bias
        )
    }

    private func resolvedSolarSoftnessProfile(
        now: Date,
        sunrise: Date,
        sunset: Date,
        bias: Double
    ) -> SoftnessProfile? {
        let preSunrise = sunrise.addingTimeInterval(-90 * 60)
        let lateMorning = sunrise.addingTimeInterval(3 * 60 * 60)
        let preSunset = sunset.addingTimeInterval(-90 * 60)
        let lateEvening = sunset.addingTimeInterval(5 * 60 * 60)
        let afterMidnight = sunset.addingTimeInterval(8 * 60 * 60)

        let brightness: Double
        let warmth: Double
        let progress: Double

        switch now {
        case ..<preSunrise:
            brightness = 0.18
            warmth = 0.14
            progress = 0.66
        case preSunrise..<sunrise:
            let t = blendProgress(from: preSunrise, to: sunrise, now: now)
            brightness = lerp(0.18, 0.10, t)
            warmth = lerp(0.14, 0.08, t)
            progress = lerp(0.66, 0.48, t)
        case sunrise..<lateMorning:
            let t = blendProgress(from: sunrise, to: lateMorning, now: now)
            brightness = lerp(0.10, 0.04, t)
            warmth = lerp(0.08, 0.03, t)
            progress = lerp(0.48, 0.28, t)
        case lateMorning..<preSunset:
            brightness = 0.04
            warmth = 0.03
            progress = 0.28
        case preSunset..<sunset:
            let t = blendProgress(from: preSunset, to: sunset, now: now)
            brightness = lerp(0.06, 0.11, t)
            warmth = lerp(0.05, 0.09, t)
            progress = lerp(0.36, 0.50, t)
        case sunset..<lateEvening:
            let t = blendProgress(from: sunset, to: lateEvening, now: now)
            brightness = lerp(0.11, 0.17, t)
            warmth = lerp(0.09, 0.14, t)
            progress = lerp(0.50, 0.66, t)
        case lateEvening..<afterMidnight:
            let t = blendProgress(from: lateEvening, to: afterMidnight, now: now)
            brightness = lerp(0.17, 0.20, t)
            warmth = lerp(0.14, 0.16, t)
            progress = lerp(0.66, 0.72, t)
        default:
            brightness = 0.20
            warmth = 0.16
            progress = 0.72
        }

        return scaledSmartProfile(
            brightnessReduction: brightness,
            warmthStrength: warmth,
            manualStrengthProgress: progress,
            bias: bias
        )
    }

    private func scaledSmartProfile(
        brightnessReduction: Double,
        warmthStrength: Double,
        manualStrengthProgress: Double,
        bias: Double
    ) -> SoftnessProfile {
        let clampedBias = min(max(bias, 0.0), 1.0)
        let brightnessMultiplier = lerp(0.84, 1.08, clampedBias)
        let warmthMultiplier = lerp(0.90, 1.36, clampedBias)
        let progressMultiplier = lerp(0.88, 1.04, clampedBias)

        return SoftnessProfile(
            brightnessReduction: min(max(brightnessReduction * brightnessMultiplier, 0.0), 0.22),
            warmthStrength: min(max(warmthStrength * warmthMultiplier, 0.0), 0.22),
            manualStrengthProgress: Float(min(max(manualStrengthProgress * progressMultiplier, 0.0), 0.78))
        )
    }

    private func blendProgress(from start: Date, to end: Date, now: Date) -> Double {
        let total = max(end.timeIntervalSince(start), 1)
        return min(max(now.timeIntervalSince(start) / total, 0), 1)
    }

    private func lerp(_ start: Double, _ end: Double, _ progress: Double) -> Double {
        start + ((end - start) * progress)
    }

    private func interpolatedValue(at hour: Double, points: [(Double, Double)]) -> Double {
        guard let first = points.first else { return 0 }
        guard hour > first.0 else { return first.1 }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let next = points[index]

            if hour <= next.0 {
                let span = max(next.0 - previous.0, 0.0001)
                let progress = (hour - previous.0) / span
                return previous.1 + ((next.1 - previous.1) * progress)
            }
        }

        return points.last?.1 ?? first.1
    }

    private func applyTimedPreview(level: WarningSoftnessLevel, profile: SoftnessProfile) {
        isManualSoftnessPreviewActive = false

        guard level != .off else {
            cancelDimming()
            restoreOriginalGamma()
            return
        }

        restoreOriginalGamma()
        ensureOriginalGamma()
        applyDimmingAndWarmth(progress: 1.0, softnessLevel: level, profile: profile)

        let restoreWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.previewRestoreWorkItem = nil
            if !ScheduleManager.shared.isInWarningState {
                self.restoreOriginalGamma()
            }
        }

        previewRestoreWorkItem = restoreWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: restoreWorkItem)
    }

    private func ensureDimmingTimer() {
        guard dimmingTimer == nil else { return }

        dimmingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            guard self.isDimming else {
                timer.invalidate()
                self.dimmingTimer = nil
                return
            }

            self.updateActiveDimming()

            if self.currentDimmingProgress >= 1 {
                timer.invalidate()
                self.dimmingTimer = nil
            }
        }

        if let dimmingTimer {
            RunLoop.current.add(dimmingTimer, forMode: .common)
        }
    }

    private func updateActiveDimming() {
        guard isDimming, let dimmingStartDate else { return }

        let softnessLevel = SettingsManager.shared.settings.validated().warningSoftnessLevel
        guard softnessLevel != .off else {
            cancelDimming()
            return
        }

        let elapsed = Date().timeIntervalSince(dimmingStartDate)
        let total = max(dimmingDurationSeconds, 1)
        currentDimmingProgress = min(max(Float(elapsed / total), 0), 1)
        applyDimmingAndWarmth(progress: currentDimmingProgress, softnessLevel: softnessLevel)
    }

    private func applyDimmingAndWarmth(
        progress: Float,
        softnessLevel: WarningSoftnessLevel,
        profile: SoftnessProfile? = nil
    ) {
        let resolvedProfile = profile ?? resolvedSoftnessProfile(for: softnessLevel)
        let safeBrightnessFloor: CGGammaValue = 0.72
        let safeBlueFloor: CGGammaValue = 0.60
        let safeBlueBalanceFloor: CGGammaValue = 0.72
        isApplyingGammaUpdate = true
        defer { isApplyingGammaUpdate = false }

        for (display, original) in originalGammaByDisplay {
            let brightnessReduction = CGGammaValue(resolvedProfile.brightnessReduction)
            let warmthStrength = CGGammaValue(resolvedProfile.warmthStrength)
            let brightnessMultiplier = max(safeBrightnessFloor, 1.0 - (brightnessReduction * CGGammaValue(progress)))
            let warmthFactor = warmthStrength * CGGammaValue(progress)
            let blueBalance = max(safeBlueBalanceFloor, 1.0 - warmthFactor)

            let redMax = min(original.red.max, max(original.red.max * safeBrightnessFloor, original.red.max * brightnessMultiplier * (1.0 + warmthFactor)))
            let greenMax = max(original.green.max * safeBrightnessFloor, original.green.max * brightnessMultiplier)
            let blueMax = max(
                max(original.blue.min, original.blue.max * safeBlueFloor),
                original.blue.max * brightnessMultiplier * blueBalance
            )

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

    func lockScreenAndTurnOffDisplay(trigger: LockEvent.Trigger, lockTime: String? = nil, completion: (() -> Void)? = nil) {
        os_log("Showing forced break screen", log: log, type: .info)

        restoreOriginalGamma()
        isDimming = false
        dimmingTimer?.invalidate()
        dimmingTimer = nil

        disposeLockWindows()

        let settings = SettingsManager.shared.settings.validated()
        let appearance = settings.appearance.withRandomCopyIfNeeded()
        remainingLockSeconds = settings.forcedBreakMinutes * 60
        lockCompletion = completion
        isCompletingLockSequence = false
        currentLockAppearance = appearance
        currentLockTrigger = trigger
        currentScheduledLockTime = lockTime ?? settings.normalizedLockTimes.first ?? settings.lockTime
        hasPresentedLockWindows = false
        isAwaitingLockActivation = false

        NSSound(named: "Glass")?.play()

        enterLockMode()
        requestLockActivationAndPresent()
    }

    private func startLockCountdown() {
        cancelLockTimer(reason: "restarting countdown")
        updateLockWindows()
        os_log(
            "Starting lock countdown from %d seconds",
            log: log,
            type: .info,
            remainingLockSeconds
        )

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }

            self.remainingLockSeconds -= 1
            os_log(
                "Lock timer handler fired; remaining=%d",
                log: log,
                type: .info,
                self.remainingLockSeconds
            )
            self.updateLockWindows()

            if self.remainingLockSeconds <= 0 {
                self.cancelLockTimer(reason: "countdown completed")
                self.completeLockSequence()
            }
        }
        lockTimer = timer
        timer.setCancelHandler {
            os_log("Lock timer cancel handler executed", log: log, type: .info)
        }
        timer.resume()
    }

    private func updateLockWindows() {
        os_log(
            "Lock countdown tick: %d",
            log: log,
            type: .info,
            max(remainingLockSeconds, 0)
        )
        for window in lockWindows {
            window.updateRemainingSeconds(max(remainingLockSeconds, 0))
        }
    }

    private func completeLockSequence() {
        guard !isCompletingLockSequence else { return }
        isCompletingLockSequence = true

        let settings = SettingsManager.shared.settings
        let event = LockEvent(
            date: Date(),
            lockTime: currentScheduledLockTime ?? settings.normalizedLockTimes.first ?? settings.lockTime,
            trigger: currentLockTrigger,
            breakDurationSeconds: settings.forcedBreakMinutes * 60,
            completed: true
        )
        StatsManager.shared.record(event: event)

        closeLockWindows(force: true)
        lockCompletion?()
        lockCompletion = nil
        currentScheduledLockTime = nil
        isCompletingLockSequence = false
    }

    private func closeLockWindows(force: Bool) {
        cancelLockTimer(reason: "closing lock windows")
        currentLockAppearance = nil
        hasPresentedLockWindows = false
        isAwaitingLockActivation = false

        if force {
            disposeLockWindows()
        } else {
            let windows = lockWindows
            lockWindows.removeAll()

            for window in windows {
                window.close()
            }
        }

        exitLockMode()
    }

    private func disposeLockWindows() {
        let windows = lockWindows
        lockWindows.removeAll()

        os_log(
            "Disposing %d lock windows",
            log: log,
            type: .info,
            windows.count
        )

        for window in windows {
            window.allowDismiss()
            window.close()
        }
    }

    private func enterLockMode() {
        guard !isLockModeActive else { return }

        isLockModeActive = true
        previousActivationPolicy = NSApp.activationPolicy()
        previousPresentationOptions = NSApp.presentationOptions
        isApplyingLockModeTransition = true

        if previousActivationPolicy != .regular {
            _ = NSApp.setActivationPolicy(.regular)
        }

        if lockWindows.isEmpty, currentLockAppearance != nil {
            os_log("Preparing lock windows before applying lock mode restrictions", log: log, type: .info)
            rebuildLockWindows(animated: false)
        }

        NSApp.presentationOptions = [
            .autoHideDock,
            .autoHideMenuBar,
            .disableProcessSwitching,
            .disableHideApplication,
            .disableForceQuit,
            .disableSessionTermination
        ]

        NSRunningApplication.current.unhide()
        NSApp.unhide(nil)
        isApplyingLockModeTransition = false
        os_log(
            "Entered lock mode; previous policy=%{public}ld",
            log: log,
            type: .info,
            previousActivationPolicy?.rawValue ?? -1
        )
    }

    private func exitLockMode() {
        guard isLockModeActive else { return }

        cancelPendingReactivations()
        NSApp.presentationOptions = previousPresentationOptions
        previousActivationPolicy = nil
        isLockModeActive = false
    }

    private func rebuildLockWindowsIfNeeded(animated: Bool) {
        guard isLockModeActive else { return }
        if isAwaitingLockActivation && !hasPresentedLockWindows {
            os_log(
                "Skipping lock window rebuild while awaiting activation (windows=%d, remaining=%d)",
                log: log,
                type: .info,
                lockWindows.count,
                remainingLockSeconds
            )
            return
        }
        os_log(
            "Rebuild requested while locked (animated=%{public}@, windows=%d, remaining=%d)",
            log: log,
            type: .info,
            animated ? "true" : "false",
            lockWindows.count,
            remainingLockSeconds
        )
        rebuildLockWindows(animated: animated)
    }

    private func rebuildLockWindows(animated: Bool) {
        guard let appearance = currentLockAppearance else { return }

        disposeLockWindows()
        os_log(
            "Rebuilding lock windows for %d screens (animated=%{public}@)",
            log: log,
            type: .info,
            NSScreen.screens.count,
            animated ? "true" : "false"
        )

        for screen in NSScreen.screens {
            os_log(
                "Creating lock window for screen frame=%{public}@ visible=%{public}@",
                log: log,
                type: .info,
                NSStringFromRect(screen.frame),
                NSStringFromRect(screen.visibleFrame)
            )
            let window = LockScreenWindow(
                screen: screen,
                remainingSeconds: remainingLockSeconds,
                appearance: appearance
            )
            lockWindows.append(window)
        }

        os_log(
            "Created %d lock windows",
            log: log,
            type: .info,
            lockWindows.count
        )

        activateLockWindows(animated: animated)
    }

    private func activateLockWindows(animated: Bool) {
        guard isLockModeActive, !lockWindows.isEmpty else { return }
        let isActive = NSApp.isActive

        os_log(
            "Activating lock windows (animated=%{public}@, active=%{public}@, windows=%d)",
            log: log,
            type: .info,
            animated ? "true" : "false",
            isActive ? "true" : "false",
            lockWindows.count
        )

        let isFirstPresentation = !hasPresentedLockWindows
        if isFirstPresentation {
            hasPresentedLockWindows = true
        }
        isAwaitingLockActivation = !isActive

        for window in lockWindows {
            os_log(
                "Presenting lock window number=%{public}@ frame=%{public}@ level=%d visible=%{public}@",
                log: log,
                type: .info,
                String(describing: window.windowNumber),
                NSStringFromRect(window.frame),
                Int(window.level.rawValue),
                window.isVisible ? "true" : "false"
            )
            if animated && isActive {
                window.reinforceFrontmost()
                window.animateIn()
            } else {
                window.showImmediately()
            }
        }

        os_log("Presenting lock windows (active=%{public}@)", log: log, type: .info, isActive ? "true" : "false")
        lockWindows.first?.makeKeyAndOrderFront(nil)

        if isFirstPresentation && lockTimer == nil {
            startLockCountdown()
        }

        if !isActive {
            os_log(
                "Lock windows waiting for activation (animated=%{public}@, windows=%d)",
                log: log,
                type: .info,
                animated ? "true" : "false",
                lockWindows.count
            )
            requestAppActivation()
        }
    }

    private func activateLockWindowsIfNeeded() {
        guard isLockModeActive else { return }
        activateLockWindows(animated: false)
    }

    private func reactivateLockModeIfNeeded() {
        guard isLockModeActive, !lockWindows.isEmpty else { return }
        activateLockWindows(animated: false)
        scheduleReactivationBurst()
    }

    private func requestLockActivationAndPresent() {
        guard isLockModeActive else { return }

        os_log("Requesting lock activation", log: log, type: .info)

        if lockWindows.isEmpty {
            rebuildLockWindows(animated: false)
        } else {
            activateLockWindows(animated: false)
        }

        scheduleReactivationBurst()
        completePendingLockPresentationIfNeeded()
    }

    private func requestAppActivation() {
        os_log("Requesting app activation", log: log, type: .info)
        NSRunningApplication.current.unhide()
        NSApp.unhide(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
    }

    private func completePendingLockPresentationIfNeeded() {
        guard isAwaitingLockActivation, isLockModeActive else { return }
        guard NSApp.isActive else {
            os_log("Lock presentation still waiting for active app", log: log, type: .info)
            return
        }

        os_log("Lock activation confirmed; presenting lock windows", log: log, type: .info)
        isAwaitingLockActivation = false
        if lockWindows.isEmpty {
            rebuildLockWindows(animated: true)
        } else {
            activateLockWindows(animated: false)
        }
    }

    private func scheduleReactivationBurst() {
        cancelPendingReactivations()

        for delay in [0.0, 0.05, 0.2, 0.6] {
            let workItem = DispatchWorkItem { [weak self] in
                self?.activateLockWindowsIfNeeded()
                self?.completePendingLockPresentationIfNeeded()
            }
            reactivationWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func cancelPendingReactivations() {
        for workItem in reactivationWorkItems {
            workItem.cancel()
        }
        reactivationWorkItems.removeAll()
    }

    private func handleSystemInactivityStarted(reason: String) {
        sleepTransitionState.inactiveSince = Date()
        os_log(
            "Observed inactivity start: %{public}@ (lockActive=%{public}@, windows=%d, remaining=%d)",
            log: log,
            type: .info,
            reason,
            isLockModeActive ? "true" : "false",
            lockWindows.count,
            remainingLockSeconds
        )
        abortActiveLockSequence(reason: reason)
    }

    private func handleSystemWake(reason: String) {
        sleepTransitionState.lastWakeAt = Date()
        os_log(
            "Observed wake: %{public}@ (lockActive=%{public}@, windows=%d, remaining=%d)",
            log: log,
            type: .info,
            reason,
            isLockModeActive ? "true" : "false",
            lockWindows.count,
            remainingLockSeconds
        )
        abortActiveLockSequence(reason: reason)
    }

    private func abortActiveLockSequence(reason: String) {
        guard isLockModeActive || lockTimer != nil || !lockWindows.isEmpty else { return }

        os_log("Aborting lock UI due to %{public}@", log: log, type: .info, reason)

        cancelLockTimer(reason: "aborting lock UI: \(reason)")
        remainingLockSeconds = 0
        currentLockAppearance = nil
        isCompletingLockSequence = false
        currentScheduledLockTime = nil
        hasPresentedLockWindows = false
        isAwaitingLockActivation = false
        cancelPendingReactivations()
        disposeLockWindows()
        exitLockMode()

        let completion = lockCompletion
        lockCompletion = nil
        completion?()
    }

    func didSleepThrough(_ moment: Date, now: Date = Date()) -> Bool {
        sleepTransitionState.crossed(moment, now: now)
    }

    func restoreOriginalGamma() {
        previewRestoreWorkItem?.cancel()
        previewRestoreWorkItem = nil
        restoreSystemColorState(resyncBaseline: true)

        os_log("Original gamma restored", log: log, type: .info)
    }
}
