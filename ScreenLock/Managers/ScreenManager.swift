import Cocoa
import CoreGraphics

class ScreenManager {
    static let shared = ScreenManager()

    private var originalGamma: (red: (min: CGGammaValue, max: CGGammaValue, gamma: CGGammaValue),
                                green: (min: CGGammaValue, max: CGGammaValue, gamma: CGGammaValue),
                                blue: (min: CGGammaValue, max: CGGammaValue, gamma: CGGammaValue))?

    private var isDimming = false
    private var dimmingTimer: Timer?

    private init() {
        saveOriginalGamma()
    }

    private func saveOriginalGamma() {
        let display = CGMainDisplayID()

        var redMin: CGGammaValue = 0, redMax: CGGammaValue = 0, redGamma: CGGammaValue = 0
        var greenMin: CGGammaValue = 0, greenMax: CGGammaValue = 0, greenGamma: CGGammaValue = 0
        var blueMin: CGGammaValue = 0, blueMax: CGGammaValue = 0, blueGamma: CGGammaValue = 0

        CGGetDisplayTransferByFormula(
            display,
            &redMin, &redMax, &redGamma,
            &greenMin, &greenMax, &greenGamma,
            &blueMin, &blueMax, &blueGamma
        )

        originalGamma = (
            red: (redMin, redMax, redGamma),
            green: (greenMin, greenMax, greenGamma),
            blue: (blueMin, blueMax, blueGamma)
        )

        print("ScreenManager: Original gamma saved")
    }

    func startGradualDimming(durationMinutes: Int) {
        guard !isDimming else { return }
        isDimming = true

        print("ScreenManager: Starting gradual dimming over \(durationMinutes) minutes")

        let steps = durationMinutes * 2 // Every 30 seconds
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
        let display = CGMainDisplayID()
        guard let original = originalGamma else { return }

        // Dim to 30% brightness
        let brightnessMultiplier = 1.0 - (0.7 * CGGammaValue(progress))

        // Warm color: increase red, decrease blue
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

    func lockScreenAndTurnOffDisplay() {
        print("ScreenManager: Locking screen and turning off display")

        // Lock screen
        let task = Process()
        task.launchPath = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        task.arguments = ["-suspend"]
        task.launch()

        // Turn off display (using pmset)
        let displayOffTask = Process()
        displayOffTask.launchPath = "/usr/bin/pmset"
        displayOffTask.arguments = ["displaysleepnow"]
        displayOffTask.launch()

        // Reset dimming state
        isDimming = false
        dimmingTimer?.invalidate()
        dimmingTimer = nil
    }

    func restoreOriginalGamma() {
        let display = CGMainDisplayID()
        guard let original = originalGamma else { return }

        CGSetDisplayTransferByFormula(
            display,
            original.red.min, original.red.max, original.red.gamma,
            original.green.min, original.green.max, original.green.gamma,
            original.blue.min, original.blue.max, original.blue.gamma
        )

        print("ScreenManager: Original gamma restored")
    }
}
