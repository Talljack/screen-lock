import Foundation

struct Settings: Codable {
    var lockTime: String           // "HH:mm" format, e.g., "00:00"
    var warningMinutes: Int        // Minutes before lock to start dimming
    var preventSleepEnabled: Bool  // Always true when app runs

    static let `default` = Settings(
        lockTime: "00:00",
        warningMinutes: 30,
        preventSleepEnabled: true
    )
}
