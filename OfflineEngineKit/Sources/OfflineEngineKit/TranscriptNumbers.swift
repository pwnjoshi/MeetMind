import Foundation

/// Compares the numbers in a Hindi source line with the numbers in its English translation by value, so a faithful
/// translation is not rejected for how it writes them: "15-20,000" may become "15,000 to 20,000" or "15-20 thousand",
/// and a spoken "पंद्रह से बीस हज़ार" may become "15 to 20 thousand".
///
/// Rules: every digit number in the source must appear in the English by value (or as its range-expanded value),
/// and every number the English writes in digits must be derivable from the source (digits or spoken number words).
/// Spoken number words in the source only permit values; they are not required to appear as digits.
enum TranscriptNumbers {
    struct SourceNumbers: Equatable {
        /// One entry per digit number in the source: the values that count as that number being present.
        var required: [Set<Double>] = []
        /// Every value the English may write in digits.
        var allowed: Set<Double> = []
    }

    static func accepts(english: String, source: String) -> Bool {
        let source = sourceNumbers(in: source)
        let written = englishValues(in: english)
        guard written.isSubset(of: source.allowed) else { return false }
        return source.required.allSatisfy { !$0.isDisjoint(with: written) }
    }

    // MARK: Source

    static func sourceNumbers(in text: String) -> SourceNumbers {
        var result = SourceNumbers()
        var bare: (value: Double, index: Int?)?        // a number just seen that has no multiplier
        var rangeStart: (value: Double, index: Int?)?  // that number, followed by a range separator
        var run: [Double] = []                         // consecutive number terms, e.g. "3 हज़ार 5 सौ"
        var runUsesMultiplier = false

        func endRun() {
            if run.count > 1, runUsesMultiplier { result.allowed.insert(run.reduce(0, +)) }
            run = []
            runUsesMultiplier = false
        }

        let pieces = tokenize(text)
        var position = 0
        while position < pieces.count {
            var piece = pieces[position]
            if case .word(let word) = piece {
                if let value = numberWords[word] {
                    piece = .number(value, isDigits: false, implied: nil)
                } else if let multiplier = multiplierWords[word] {
                    piece = .multiplier(multiplier)
                } else if rangeWords.contains(word) {
                    piece = .dash
                }
            }
            switch piece {
            case .number(let value, let isDigits, let implied):
                var full = value
                var multiplier = implied
                if position + 1 < pieces.count, case .word(let next) = pieces[position + 1],
                   let spoken = multiplierWords[next] {
                    full = value * spoken
                    multiplier = spoken
                    position += 1
                }
                var index: Int?
                if isDigits {
                    index = result.required.count
                    result.required.append([full])
                }
                result.allowed.insert(full)
                if let start = rangeStart, let scale = multiplier, start.value * scale < full {
                    let widened = start.value * scale
                    result.allowed.insert(widened)
                    if let startIndex = start.index { result.required[startIndex].insert(widened) }
                }
                rangeStart = nil
                if multiplier == nil { bare = (value: full, index: index) } else { bare = nil }
                run.append(full)
                runUsesMultiplier = runUsesMultiplier || multiplier != nil
            case .multiplier(let multiplier):
                result.allowed.insert(multiplier)
                run.append(multiplier)
                runUsesMultiplier = true
                bare = nil
                rangeStart = nil
            case .dash:
                endRun()
                rangeStart = bare
                bare = nil
            default:
                endRun()
                bare = nil
                rangeStart = nil
            }
            position += 1
        }
        endRun()
        return result
    }

    // MARK: English

    /// Numbers the English writes in digits, with a following "thousand", "lakh", "crore" etc. applied.
    static func englishValues(in text: String) -> Set<Double> {
        var values = Set<Double>()
        let pieces = tokenize(text)
        var position = 0
        while position < pieces.count {
            if case .number(var value, _, _) = pieces[position] {
                if position + 1 < pieces.count, case .word(let next) = pieces[position + 1],
                   let multiplier = englishMultipliers[next] {
                    value *= multiplier
                    position += 1
                }
                values.insert(value)
            }
            position += 1
        }
        return values
    }

    // MARK: Tokens

    enum Piece: Equatable {
        case number(Double, isDigits: Bool, implied: Double?)
        case word(String)
        case multiplier(Double)
        case dash
    }

    private static let tokenPattern = try! NSRegularExpression(
        pattern: "[0-9\u{0966}-\u{096F}]+(?:[,.][0-9\u{0966}-\u{096F}]+)*|[\\p{L}\\p{M}]+|[-\u{2013}\u{2014}]")

    /// Digit numbers (Devanagari digits converted, separators removed; a trailing ",000" implies thousands),
    /// lowercase words with nukta removed, and range dashes.
    static func tokenize(_ text: String) -> [Piece] {
        let whole = NSRange(text.startIndex..., in: text)
        return tokenPattern.matches(in: text, range: whole).compactMap { match -> Piece? in
            guard let range = Range(match.range, in: text) else { return nil }
            let raw = String(text[range])
            guard let first = raw.unicodeScalars.first else { return nil }
            if raw == "-" || raw == "\u{2013}" || raw == "\u{2014}" { return .dash }
            guard first.properties.numericType == .decimal else { return .word(normalized(raw)) }
            var converted = ""
            for scalar in raw.unicodeScalars {
                if (0x0966...0x096F).contains(scalar.value) {
                    converted.unicodeScalars.append(Unicode.Scalar(scalar.value - 0x0966 + 0x30)!)
                } else {
                    converted.unicodeScalars.append(scalar)
                }
            }
            guard let value = Double(converted.replacingOccurrences(of: ",", with: "")) else { return nil }
            let implied: Double? = converted.hasSuffix(",000") && value >= 1_000 ? 1_000 : nil
            return .number(value, isDigits: true, implied: implied)
        }
    }

    static func normalized(_ word: String) -> String {
        word.decomposedStringWithCanonicalMapping.lowercased().replacingOccurrences(of: "\u{093C}", with: "")
    }

    // MARK: Lexicon

    private static func lexicon(_ entries: [(Double, [String])]) -> [String: Double] {
        var table: [String: Double] = [:]
        for (value, spellings) in entries {
            for spelling in spellings { table[normalized(spelling)] = value }
        }
        return table
    }

    /// Spoken Hindi numbers 0 to 100 in common spellings, Devanagari and romanized.
    private static let numberWords = lexicon([
        (0, ["शून्य", "ज़ीरो", "zero", "shunya"]),
        (1, ["एक", "ek"]),
        (1.5, ["डेढ़", "डेढ", "dedh"]),
        (2, ["दो", "do"]),
        (2.5, ["ढाई", "dhai"]),
        (3, ["तीन", "teen"]),
        (4, ["चार", "char", "chaar"]),
        (5, ["पाँच", "पांच", "पाच", "paanch", "panch"]),
        (6, ["छह", "छः", "छे", "छ", "chhe", "chhah", "chah"]),
        (7, ["सात", "saat", "sat"]),
        (8, ["आठ", "aath", "ath"]),
        (9, ["नौ", "nau"]),
        (10, ["दस", "das"]),
        (11, ["ग्यारह", "gyarah", "giyarah"]),
        (12, ["बारह", "barah"]),
        (13, ["तेरह", "terah"]),
        (14, ["चौदह", "chaudah"]),
        (15, ["पंद्रह", "पन्द्रह", "पंद्रा", "pandrah", "pandra"]),
        (16, ["सोलह", "solah"]),
        (17, ["सत्रह", "satrah"]),
        (18, ["अठारह", "अट्ठारह", "atharah"]),
        (19, ["उन्नीस", "unnis"]),
        (20, ["बीस", "bees"]),
        (25, ["पच्चीस", "pachchis", "pachis"]),
        (30, ["तीस", "tees"]),
        (35, ["पैंतीस", "paintis"]),
        (40, ["चालीस", "chalis", "chaalis"]),
        (45, ["पैंतालीस", "paintalis"]),
        (50, ["पचास", "pachas", "pachaas"]),
        (60, ["साठ", "saath", "saadh"]),
        (70, ["सत्तर", "sattar"]),
        (75, ["पचहत्तर", "pachattar"]),
        (80, ["अस्सी", "assi"]),
        (90, ["नब्बे", "nabbe"]),
        (100, ["सौ", "sau"]),
    ])

    private static let multiplierWords = lexicon([
        (1_000, ["हज़ार", "हजार", "hazaar", "hazar", "hajar"]),
        (100_000, ["लाख", "lakh", "lac"]),
        (10_000_000, ["करोड़", "करोड", "crore", "karod"]),
        (100, ["सौ", "sau"]),
    ])

    /// Words that join the two ends of a range in speech ("पंद्रह से बीस").
    private static let rangeWords: Set<String> = ["से", "se", "to"]

    private static let englishMultipliers: [String: Double] = [
        "hundred": 100, "thousand": 1_000, "k": 1_000, "lakh": 100_000, "lakhs": 100_000, "lac": 100_000,
        "lacs": 100_000, "million": 1_000_000, "crore": 10_000_000, "crores": 10_000_000, "billion": 1_000_000_000,
    ]
}
