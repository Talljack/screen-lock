import Foundation

enum AppLanguage: String, Codable, CaseIterable {
    case auto = "auto"
    case zhHans = "zh-Hans"
    case en = "en"

    var displayName: String {
        switch self {
        case .auto: return L("lang.auto")
        case .zhHans: return "中文"
        case .en: return "English"
        }
    }
}

final class LanguageManager {
    static let shared = LanguageManager()

    private var overrideBundle: Bundle?

    private init() {}

    func applyLanguage(_ language: AppLanguage) {
        if language == .auto {
            overrideBundle = nil
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
            if let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                overrideBundle = bundle
            }
        }
    }

    func localizedString(_ key: String) -> String {
        if let bundle = overrideBundle {
            return bundle.localizedString(forKey: key, value: nil, table: nil)
        }
        return NSLocalizedString(key, comment: "")
    }
}

func L(_ key: String) -> String {
    LanguageManager.shared.localizedString(key)
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: LanguageManager.shared.localizedString(key), arguments: args)
}
