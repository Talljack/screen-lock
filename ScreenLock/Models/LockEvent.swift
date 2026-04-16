import Foundation

struct LockEvent: Codable, Equatable {
    let date: Date
    let lockTime: String
    let trigger: Trigger
    let breakDurationSeconds: Int
    let completed: Bool

    enum Trigger: String, Codable {
        case scheduled
        case manual
    }
}

struct Achievement: Equatable {
    let id: String
    let title: String
    let description: String
    let emoji: String
    let requirement: Int

    static let all: [Achievement] = [
        Achievement(id: "streak3",  title: L("achievement.streak3.title"),  description: L("achievement.streak3.desc"),  emoji: "🌱", requirement: 3),
        Achievement(id: "streak7",  title: L("achievement.streak7.title"),  description: L("achievement.streak7.desc"),  emoji: "🛡️", requirement: 7),
        Achievement(id: "streak14", title: L("achievement.streak14.title"), description: L("achievement.streak14.desc"), emoji: "⭐", requirement: 14),
        Achievement(id: "streak30", title: L("achievement.streak30.title"), description: L("achievement.streak30.desc"), emoji: "👑", requirement: 30),
        Achievement(id: "total10",  title: L("achievement.total10.title"),  description: L("achievement.total10.desc"),    emoji: "✨", requirement: 10),
        Achievement(id: "total50",  title: L("achievement.total50.title"),  description: L("achievement.total50.desc"),    emoji: "💪", requirement: 50),
        Achievement(id: "total100", title: L("achievement.total100.title"), description: L("achievement.total100.desc"),   emoji: "🌙", requirement: 100),
    ]
}
