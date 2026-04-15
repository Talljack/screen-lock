import Foundation

enum LockScreenTheme: String, Codable, CaseIterable {
    case peachBunny
    case cloudPudding
    case starlightCat

    var displayName: String {
        switch self {
        case .peachBunny:  return "蜜桃兔兔"
        case .cloudPudding: return "云朵布丁"
        case .starlightCat: return "星星晚安"
        }
    }

    struct CopySet: Equatable {
        let title: String
        let subtitle: String
        let footer: String
    }

    var defaultCopy: CopySet {
        return copySets[0]
    }

    var copySets: [CopySet] {
        switch self {
        case .peachBunny:
            return [
                CopySet(title: "先休息一下下",
                        subtitle: "给眼睛、肩膀和脑袋一个可爱的暂停键",
                        footer: "喝口水 / 伸个懒腰 / 看看远处 / 等会儿再继续加油"),
                CopySet(title: "该睡觉觉啦",
                        subtitle: "小兔子都回窝了，你也快去休息吧",
                        footer: "抱抱枕头 / 闻闻薰衣草 / 数绵羊 / 晚安"),
                CopySet(title: "电量不足，请充电",
                        subtitle: "你的能量条快见底了，睡一觉就满格啦",
                        footer: "放下手机 / 拉好被子 / 明天继续闪闪发光"),
                CopySet(title: "月亮出来啦",
                        subtitle: "连月亮都在提醒你：该休息了哦",
                        footer: "关灯 / 躺好 / 让梦来找你"),
            ]
        case .cloudPudding:
            return [
                CopySet(title: "今天已经很棒了",
                        subtitle: "睡眠是最好的充电器，让大脑好好休息吧",
                        footer: "闭上眼睛 / 深呼吸三次 / 和今天说晚安"),
                CopySet(title: "辛苦了，放松一下",
                        subtitle: "世界不会因为你晚睡而变得更好",
                        footer: "热牛奶 / 轻音乐 / 一个好梦"),
                CopySet(title: "把烦恼留给昨天",
                        subtitle: "睡一觉，明天的你会更有办法",
                        footer: "放下焦虑 / 相信自己 / 安心入睡"),
                CopySet(title: "时间到了",
                        subtitle: "最好的自律，是按时休息",
                        footer: "整理思绪 / 写下感恩 / 温柔入梦"),
            ]
        case .starlightCat:
            return [
                CopySet(title: "星星也要休息了",
                        subtitle: "夜深了，把未完成的事交给明天的自己",
                        footer: "月亮替你值班 / 明天又是元气满满的一天"),
                CopySet(title: "夜色温柔",
                        subtitle: "繁星说：今晚的故事到这里就好了",
                        footer: "合上屏幕 / 看看窗外 / 让星光陪你入眠"),
                CopySet(title: "晚安，追梦人",
                        subtitle: "梦想不会因为早睡而迟到",
                        footer: "枕着星河 / 带着期待 / 在梦中继续冒险"),
                CopySet(title: "宇宙也在休息",
                        subtitle: "银河系都暗下来了，你也该闭眼了",
                        footer: "听听风声 / 感受宁静 / 晚安，地球人"),
            ]
        }
    }

    func randomCopy() -> CopySet {
        return copySets.randomElement() ?? defaultCopy
    }
}

struct LockScreenAppearance: Codable, Equatable {
    var theme: LockScreenTheme
    var titleText: String
    var subtitleText: String
    var footerText: String
    var backgroundImagePath: String?
    var isCustomCopy: Bool

    static let `default` = LockScreenAppearance(
        theme: .peachBunny,
        titleText: LockScreenTheme.peachBunny.defaultCopy.title,
        subtitleText: LockScreenTheme.peachBunny.defaultCopy.subtitle,
        footerText: LockScreenTheme.peachBunny.defaultCopy.footer,
        backgroundImagePath: nil,
        isCustomCopy: false
    )

    func validated() -> LockScreenAppearance {
        var a = self

        a.titleText = a.titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        a.subtitleText = a.subtitleText.trimmingCharacters(in: .whitespacesAndNewlines)
        a.footerText = a.footerText.trimmingCharacters(in: .whitespacesAndNewlines)
        a.backgroundImagePath = a.backgroundImagePath?.trimmingCharacters(in: .whitespacesAndNewlines)

        let fallback = theme.defaultCopy
        if a.titleText.isEmpty { a.titleText = fallback.title }
        if a.subtitleText.isEmpty { a.subtitleText = fallback.subtitle }
        if a.footerText.isEmpty { a.footerText = fallback.footer }
        if a.backgroundImagePath?.isEmpty == true { a.backgroundImagePath = nil }

        return a
    }

    /// Returns an appearance with random copy from the theme pool.
    /// Only randomizes if the user hasn't set custom copy.
    func withRandomCopyIfNeeded() -> LockScreenAppearance {
        guard !isCustomCopy else { return self }
        let copy = theme.randomCopy()
        var a = self
        a.titleText = copy.title
        a.subtitleText = copy.subtitle
        a.footerText = copy.footer
        return a
    }
}

struct Settings: Codable {
    var lockTime: String
    var warningMinutes: Int
    var preventSleepEnabled: Bool
    var lockEnabled: Bool
    var forcedBreakMinutes: Int
    var appearance: LockScreenAppearance
    var autoStartEnabled: Bool
    var hasShownPermissionGuide: Bool

    static let `default` = Settings(
        lockTime: "00:00",
        warningMinutes: 30,
        preventSleepEnabled: true,
        lockEnabled: true,
        forcedBreakMinutes: 15,
        appearance: .default,
        autoStartEnabled: false,
        hasShownPermissionGuide: false
    )

    enum CodingKeys: String, CodingKey {
        case lockTime, warningMinutes, preventSleepEnabled, lockEnabled
        case forcedBreakMinutes, appearance, autoStartEnabled, hasShownPermissionGuide
    }

    init(
        lockTime: String,
        warningMinutes: Int,
        preventSleepEnabled: Bool,
        lockEnabled: Bool,
        forcedBreakMinutes: Int,
        appearance: LockScreenAppearance,
        autoStartEnabled: Bool = false,
        hasShownPermissionGuide: Bool = false
    ) {
        self.lockTime = lockTime
        self.warningMinutes = warningMinutes
        self.preventSleepEnabled = preventSleepEnabled
        self.lockEnabled = lockEnabled
        self.forcedBreakMinutes = forcedBreakMinutes
        self.appearance = appearance
        self.autoStartEnabled = autoStartEnabled
        self.hasShownPermissionGuide = hasShownPermissionGuide
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.lockTime = try container.decodeIfPresent(String.self, forKey: .lockTime) ?? Self.default.lockTime
        self.warningMinutes = try container.decodeIfPresent(Int.self, forKey: .warningMinutes)
            ?? Self.default.warningMinutes
        self.preventSleepEnabled = try container.decodeIfPresent(Bool.self, forKey: .preventSleepEnabled)
            ?? Self.default.preventSleepEnabled
        self.lockEnabled = try container.decodeIfPresent(Bool.self, forKey: .lockEnabled)
            ?? Self.default.lockEnabled
        self.forcedBreakMinutes = try container.decodeIfPresent(Int.self, forKey: .forcedBreakMinutes)
            ?? Self.default.forcedBreakMinutes
        self.appearance = try container.decodeIfPresent(LockScreenAppearance.self, forKey: .appearance)
            ?? Self.default.appearance
        self.autoStartEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoStartEnabled)
            ?? Self.default.autoStartEnabled
        self.hasShownPermissionGuide = try container.decodeIfPresent(Bool.self, forKey: .hasShownPermissionGuide)
            ?? Self.default.hasShownPermissionGuide
    }

    func validated() -> Settings {
        Settings(
            lockTime: lockTime,
            warningMinutes: max(1, warningMinutes),
            preventSleepEnabled: preventSleepEnabled,
            lockEnabled: lockEnabled,
            forcedBreakMinutes: max(1, forcedBreakMinutes),
            appearance: appearance.validated(),
            autoStartEnabled: autoStartEnabled,
            hasShownPermissionGuide: hasShownPermissionGuide
        )
    }
}
