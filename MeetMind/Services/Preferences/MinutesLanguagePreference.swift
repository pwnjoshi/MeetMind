import Foundation

/// Language used when writing minutes. Stored in UserDefaults under `MinutesLanguagePreference.key`.
public enum MinutesLanguage: String, CaseIterable, Identifiable, Sendable {
    case english
    case hindi
    case bilingual

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .english: return "English"
        case .hindi: return "Hindi"
        case .bilingual: return "English and Hindi"
        }
    }
}

public enum MinutesLanguagePreference {
    public static let key = "Manent_MinutesLanguage"

    public static func current(defaults: UserDefaults = .standard) -> MinutesLanguage {
        defaults.string(forKey: key).flatMap(MinutesLanguage.init(rawValue:)) ?? .english
    }

    public static func set(_ language: MinutesLanguage, defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: key)
    }
}
