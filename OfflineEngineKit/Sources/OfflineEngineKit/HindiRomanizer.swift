import Foundation

/// Display-only conversion of Devanagari text to readable Hinglish in Latin letters,
/// for example "कल तक भेज देना।" becomes "Kal tak bhej dena."
///
/// It is a spelling aid, not an ISO transliteration: there are no diacritics, common words use their usual
/// Hinglish spelling (from the shared lexicon), unknown words are spelled phonetically with the inherent
/// vowel dropped where Hindi drops it, and Latin text, digits and punctuation pass through unchanged.
/// Pure and deterministic. Stored transcripts are never rewritten with it.
public enum HindiRomanizer {
    /// Returns `text` unchanged when it contains no Devanagari.
    public static func romanize(_ text: String) -> String {
        guard HindiText.containsDevanagari(text) else { return text }
        var output = ""
        var run: [Unicode.Scalar] = []
        var sentenceStart = true

        func flush() {
            guard !run.isEmpty else { return }
            var word = romanizeWord(run)
            run.removeAll()
            guard !word.isEmpty else { return }
            if sentenceStart, let first = word.first { word = String(first).uppercased() + String(word.dropFirst()) }
            output += word
            sentenceStart = false
        }

        for scalar in text.unicodeScalars {
            let value = scalar.value
            if isWordScalar(value) {
                run.append(scalar)
                continue
            }
            flush()
            switch value {
            case 0x0964, 0x0965:
                output += "."
                sentenceStart = true
            case 0x0970:
                output += "."
            case 0x0966...0x096F:
                output += String(value - 0x0966)
                sentenceStart = false
            default:
                output.unicodeScalars.append(scalar)
                if value == 0x2E || value == 0x3F || value == 0x21 {
                    sentenceStart = true
                } else if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                    sentenceStart = false
                }
            }
        }
        flush()
        // Whisper spells "let's" as two Devanagari words, which romanize to "let es".
        return output.replacingOccurrences(of: #"\b([Ll])et es\b"#, with: "$1et's", options: .regularExpression)
    }

    // MARK: - Words

    private static func isWordScalar(_ value: UInt32) -> Bool {
        (value >= 0x0900 && value <= 0x0963) || (value >= 0x0971 && value <= 0x097F)
            || value == 0x200C || value == 0x200D
    }

    private enum Vowel {
        case inherent
        case silent
        case explicit(String)
    }

    private struct Syllable {
        var letters: String
        var vowel: Vowel
        var nasal = false
        var visarga = false
    }

    private static func romanizeWord(_ run: [Unicode.Scalar]) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: run)
        let word = String(view)
        if let known = HindiText.lookup(HindiText.normalized(word)) { return known }
        if let split = HindiText.fusedSplit(word) { return split.first + " " + split.second }

        let scalars = Array(word.decomposedStringWithCanonicalMapping.unicodeScalars).filter {
            $0.value != 0x200C && $0.value != 0x200D
        }
        func code(_ index: Int) -> UInt32 { index >= 0 && index < scalars.count ? scalars[index].value : 0 }

        var units: [Syllable] = []
        var index = 0
        while index < scalars.count {
            let current = code(index)
            if let base = consonant(current) {
                var letters = base
                var next = index + 1
                if current == 0x091C, code(next) == 0x094D, code(next + 1) == 0x091E {
                    letters = "gy"
                    next += 2
                } else if code(next) == 0x093C {
                    letters = nuktaConsonant(current) ?? base
                    next += 1
                }
                var unit = Syllable(letters: letters, vowel: .inherent)
                if code(next) == 0x094D {
                    unit.vowel = .silent
                    next += 1
                } else if let sign = vowelSign(code(next)) {
                    unit.vowel = .explicit(sign)
                    next += 1
                }
                next = markNasal(&unit, scalars: scalars, at: next)
                units.append(unit)
                index = next
            } else if let vowel = independentVowel(current) {
                var unit = Syllable(letters: "", vowel: .explicit(vowel))
                index = markNasal(&unit, scalars: scalars, at: index + 1)
                units.append(unit)
            } else {
                index += 1
            }
        }
        guard !units.isEmpty else { return "" }

        // Hindi drops the inherent vowel at the end of a word and between two pronounced vowels.
        var kept: [Bool] = units.map { unit in
            if case .silent = unit.vowel { return false }
            return true
        }
        func droppable(_ position: Int) -> Bool {
            if case .inherent = units[position].vowel { return !units[position].nasal && !units[position].visarga }
            return false
        }
        if units.count >= 2, droppable(units.count - 1) { kept[units.count - 1] = false }
        if units.count >= 3 {
            var position = units.count - 2
            while position >= 1 {
                if droppable(position), kept[position], kept[position + 1], kept[position - 1], !units[position - 1].nasal {
                    kept[position] = false
                }
                position -= 1
            }
        }

        var result = ""
        for (position, unit) in units.enumerated() {
            result += unit.letters
            switch unit.vowel {
            case .inherent: if kept[position] { result += "a" }
            case .silent: break
            case .explicit(let sign):
                // A long final "aa" after a consonant is spelled "a" ("dena", "karna").
                if sign == "aa", position == units.count - 1, !unit.letters.isEmpty, !unit.nasal { result += "a" } else { result += sign }
            }
            if unit.nasal {
                var nasal = "n"
                if position + 1 < units.count, let first = units[position + 1].letters.first, "pbm".contains(first) { nasal = "m" }
                result += nasal
            }
            if unit.visarga { result += "h" }
        }
        return result
    }

    private static func markNasal(_ unit: inout Syllable, scalars: [Unicode.Scalar], at index: Int) -> Int {
        guard index < scalars.count else { return index }
        let value = scalars[index].value
        if value == 0x0902 || value == 0x0901 {
            unit.nasal = true
            return index + 1
        }
        if value == 0x0903 {
            unit.visarga = true
            return index + 1
        }
        return index
    }

    // MARK: - Letter tables

    private static func consonant(_ code: UInt32) -> String? {
        switch code {
        case 0x0915: return "k"
        case 0x0916: return "kh"
        case 0x0917: return "g"
        case 0x0918: return "gh"
        case 0x0919: return "n"
        case 0x091A: return "ch"
        case 0x091B: return "chh"
        case 0x091C: return "j"
        case 0x091D: return "jh"
        case 0x091E: return "n"
        case 0x091F: return "t"
        case 0x0920: return "th"
        case 0x0921: return "d"
        case 0x0922: return "dh"
        case 0x0923: return "n"
        case 0x0924: return "t"
        case 0x0925: return "th"
        case 0x0926: return "d"
        case 0x0927: return "dh"
        case 0x0928: return "n"
        case 0x092A: return "p"
        case 0x092B: return "ph"
        case 0x092C: return "b"
        case 0x092D: return "bh"
        case 0x092E: return "m"
        case 0x092F: return "y"
        case 0x0930: return "r"
        case 0x0932: return "l"
        case 0x0933: return "l"
        case 0x0935: return "v"
        case 0x0936: return "sh"
        case 0x0937: return "sh"
        case 0x0938: return "s"
        case 0x0939: return "h"
        default: return nil
        }
    }

    /// Consonants written with a nukta.
    private static func nuktaConsonant(_ code: UInt32) -> String? {
        switch code {
        case 0x0915: return "q"
        case 0x0916: return "kh"
        case 0x0917: return "g"
        case 0x091C: return "z"
        case 0x0921: return "r"
        case 0x0922: return "rh"
        case 0x092B: return "f"
        default: return nil
        }
    }

    private static func vowelSign(_ code: UInt32) -> String? {
        switch code {
        case 0x093E: return "aa"
        case 0x093F: return "i"
        case 0x0940: return "i"
        case 0x0941: return "u"
        case 0x0942: return "oo"
        case 0x0943: return "ri"
        case 0x0945: return "e"
        case 0x0947: return "e"
        case 0x0948: return "ai"
        case 0x0949: return "o"
        case 0x094B: return "o"
        case 0x094C: return "au"
        default: return nil
        }
    }

    private static func independentVowel(_ code: UInt32) -> String? {
        switch code {
        case 0x0905: return "a"
        case 0x0906: return "aa"
        case 0x0907: return "i"
        case 0x0908: return "i"
        case 0x0909: return "u"
        case 0x090A: return "oo"
        case 0x090B: return "ri"
        case 0x090F: return "e"
        case 0x0910: return "ai"
        case 0x0911: return "o"
        case 0x0913: return "o"
        case 0x0914: return "au"
        default: return nil
        }
    }
}
