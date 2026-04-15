import Foundation

struct Settings: Codable {
    var lockTime: String           // "HH:mm" format, e.g., "00:00"
    var warningMinutes: Int        // Minutes before lock to start dimming
    var preventSleepEnabled: Bool  // Prevent sleep when lid closed
    var lockEnabled: Bool          // Enable/disable scheduled locking
    var forcedBreakMinutes: Int    // Duration of forced break when locked

    static let `default` = Settings(
        lockTime: "00:00",
        warningMinutes: 30,
        preventSleepEnabled: true,
        lockEnabled: true,
        forcedBreakMinutes: 15
    )
}
