import Foundation
import OfflineEngineKit

/// How Hindi words are shown on screen. Display only: stored transcripts, minutes and exports keep
/// the Devanagari the speech engine produced.
public enum HindiScriptStyle: String, CaseIterable, Identifiable, Sendable {
    case devanagari
    case roman

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .devanagari: return "Devanagari (\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940})"
        case .roman: return "Roman letters (Hinglish)"
        }
    }

    public var example: String {
        switch self {
        case .devanagari: return "\u{0915}\u{0932} \u{0924}\u{0915} \u{092D}\u{0947}\u{091C} \u{0926}\u{0947}\u{0928}\u{093E}\u{0964}"
        case .roman: return "Kal tak bhej dena."
        }
    }
}

/// UserDefaults-backed choice of `HindiScriptStyle`, shared by the transcript and live caption views.
public enum HindiScriptPreference {
    public static let key = "Manent_HindiScript"

    public static func current(defaults: UserDefaults = .standard) -> HindiScriptStyle {
        defaults.string(forKey: key).flatMap(HindiScriptStyle.init(rawValue:)) ?? .devanagari
    }

    public static func set(_ style: HindiScriptStyle, defaults: UserDefaults = .standard) {
        defaults.set(style.rawValue, forKey: key)
    }

    /// The text as it should be displayed. Latin text and the Devanagari style return `text` unchanged.
    public static func display(_ text: String, style: HindiScriptStyle) -> String {
        style == .roman ? HindiRomanizer.romanize(text) : text
    }

    /// Variant for views that read the raw `@AppStorage` string.
    public static func display(_ text: String, raw: String) -> String {
        display(text, style: HindiScriptStyle(rawValue: raw) ?? .devanagari)
    }
}
