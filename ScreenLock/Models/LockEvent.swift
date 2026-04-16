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
        Achievement(id: "streak3",  title: "早睡新手",  description: "连续 3 天按时锁屏",  emoji: "🌱", requirement: 3),
        Achievement(id: "streak7",  title: "睡眠卫士",  description: "连续 7 天按时锁屏",  emoji: "🛡️", requirement: 7),
        Achievement(id: "streak14", title: "作息达人",  description: "连续 14 天按时锁屏", emoji: "⭐", requirement: 14),
        Achievement(id: "streak30", title: "健康冠军",  description: "连续 30 天按时锁屏", emoji: "👑", requirement: 30),
        Achievement(id: "total10",  title: "起步之星",  description: "累计锁屏 10 次",    emoji: "✨", requirement: 10),
        Achievement(id: "total50",  title: "坚持有方",  description: "累计锁屏 50 次",    emoji: "💪", requirement: 50),
        Achievement(id: "total100", title: "月光使者",  description: "累计锁屏 100 次",   emoji: "🌙", requirement: 100),
    ]
}
