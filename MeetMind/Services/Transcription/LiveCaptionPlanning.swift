import Foundation

/// The meeting language the user chose for the saved (Whisper) transcript.
/// Raw values match `SettingsViewModel.SavedRecordingLanguage`, which is
/// persisted under `LiveCaptionLanguage.defaultsKey`. The speech service reads
/// the stored value directly so live captions follow the same setting.
public enum LiveCaptionLanguage: String, Sendable, CaseIterable, Equatable {
    case hinglish
    case hindi
    case english
    case automatic

    public static let defaultsKey = "MeetMind_SavedRecordingLanguage"

    /// Reads the stored recording language. Unknown or missing values mean Hinglish,
    /// the app default.
    public static func stored(in defaults: UserDefaults = .standard) -> LiveCaptionLanguage {
        guard let raw = defaults.string(forKey: defaultsKey),
              let language = LiveCaptionLanguage(rawValue: raw) else {
            return .hinglish
        }
        return language
    }
}

/// Ordered list of locale identifiers to try for live captions.
public struct LiveCaptionLocalePlan: Equatable, Sendable {
    /// BCP-47 identifiers with a hyphen, best first (for example `["en-IN", "en-US"]`).
    public let candidates: [String]
    /// Human readable language for notices (for example "Hindi").
    public let languageName: String

    public init(candidates: [String], languageName: String) {
        self.candidates = candidates
        self.languageName = languageName
    }
}

/// Locales for a code-switching session: one plan per language, run side by side.
public struct LiveCaptionDualPlan: Equatable, Sendable {
    public let english: LiveCaptionLocalePlan
    public let hindi: LiveCaptionLocalePlan

    public init(english: LiveCaptionLocalePlan, hindi: LiveCaptionLocalePlan) {
        self.english = english
        self.hindi = hindi
    }
}

/// Pure locale selection for live captions.
public enum LiveCaptionLocalePlanner {
    public static let hindi = "hi-IN"
    public static let indianEnglish = "en-IN"
    public static let usEnglish = "en-US"

    /// Converts `hi_IN` style identifiers to `hi-IN` and trims whitespace.
    public static func normalized(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let cleaned = identifier.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-")
        return cleaned.isEmpty ? nil : cleaned
    }

    /// - Parameters:
    ///   - language: the saved recording language.
    ///   - preferredLocaleIdentifier: the separate preview locale from Settings (`speechLanguageLocale`).
    ///     It only matters for English variants and for the "automatic" language.
    public static func plan(language: LiveCaptionLanguage, preferredLocaleIdentifier: String?) -> LiveCaptionLocalePlan {
        let preferred = normalized(preferredLocaleIdentifier)
        switch language {
        case .hindi, .hinglish:
            // Single-recognizer fallback. Hinglish normally runs `dualPlan` (English + Hindi) instead;
            // this plan is used when only Hindi is available. There is deliberately no English
            // fallback here: it would turn Hindi speech into nonsense.
            return LiveCaptionLocalePlan(candidates: [hindi], languageName: "Hindi")
        case .english:
            var list = [indianEnglish, usEnglish]
            if let preferred, isEnglish(preferred), !list.contains(preferred) {
                list.insert(preferred, at: 0)
            }
            return LiveCaptionLocalePlan(candidates: list, languageName: "English")
        case .automatic:
            // Apple recognizers cannot detect a language, so follow the Settings preview locale.
            let chosen = preferred ?? hindi
            return LiveCaptionLocalePlan(candidates: [chosen], languageName: displayName(forIdentifier: chosen))
        }
    }

    /// Locales for code-switching captions: an English and a Hindi recognizer run together and
    /// `LiveCaptionLanguageArbiter` picks the language of each phrase. Only Hinglish and
    /// Automatic switch; English and Hindi stay single-language (use `plan`). Returns nil for those.
    public static func dualPlan(language: LiveCaptionLanguage, preferredLocaleIdentifier: String?) -> LiveCaptionDualPlan? {
        switch language {
        case .hindi, .english:
            return nil
        case .hinglish, .automatic:
            let english = plan(language: .english, preferredLocaleIdentifier: preferredLocaleIdentifier)
            let hindiPlan = LiveCaptionLocalePlan(candidates: [hindi], languageName: "Hindi")
            return LiveCaptionDualPlan(english: english, hindi: hindiPlan)
        }
    }

    public static func isEnglish(_ identifier: String) -> Bool {
        identifier.lowercased().hasPrefix("en")
    }

    public static func displayName(forIdentifier identifier: String) -> String {
        let lower = identifier.lowercased()
        if lower.hasPrefix("hi") { return "Hindi" }
        if lower.hasPrefix("en") { return "English" }
        let languageCode = identifier.split(separator: "-").first.map(String.init) ?? identifier
        return Locale(identifier: "en").localizedString(forLanguageCode: languageCode) ?? identifier
    }
}

/// User-facing messages that live captions can show in place of text.
public enum LiveCaptionNotice {
    public static func unavailable(languageName: String) -> String {
        "Live captions for \(languageName) aren't available on this iPhone; the full transcript is created after recording."
    }

    public static func downloading(languageName: String) -> String {
        "Downloading \(languageName) speech model. Live captions start when it finishes; recording is not affected."
    }
}

/// Builds the recognizer hint list from meeting participants and agenda text.
public enum LiveCaptionContext {
    public static let maximumStrings = 100
    public static let maximumLength = 40

    /// Names and short phrases help recognizers with proper nouns. The result is
    /// de-duplicated (case-insensitive), trimmed, length limited and capped.
    public static func contextualStrings(participants: [String], agenda: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        func add(_ raw: String) {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count >= 2, value.count <= maximumLength else { return }
            let key = value.lowercased()
            guard seen.insert(key).inserted else { return }
            result.append(value)
        }

        for name in participants {
            add(name)
            // First names are what people actually say aloud.
            let parts = name.split(whereSeparator: { $0.isWhitespace })
            if parts.count > 1, let first = parts.first { add(String(first)) }
        }
        for line in agenda {
            add(line)
            for word in line.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }) {
                let token = String(word)
                // Capitalised or long tokens are the likely terms; skip common short words.
                if token.count >= 4, token.first?.isUppercase == true { add(token) }
            }
        }
        return Array(result.prefix(maximumStrings))
    }
}
