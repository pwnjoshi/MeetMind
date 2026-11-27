import Foundation

/// Cross-script matching for Vidur: English or Hinglish questions against Devanagari transcripts.
enum VidurScript {
    private static let devanagari: [UInt32: String] = [
        0x0901: "n", 0x0902: "n",
        0x0915: "k", 0x0916: "k", 0x0917: "g", 0x0918: "g", 0x0919: "n",
        0x091A: "C", 0x091B: "C", 0x091C: "j", 0x091D: "j", 0x091E: "n",
        0x091F: "t", 0x0920: "t", 0x0921: "d", 0x0922: "d", 0x0923: "n",
        0x0924: "t", 0x0925: "t", 0x0926: "d", 0x0927: "d", 0x0928: "n",
        0x092A: "p", 0x092B: "p", 0x092C: "b", 0x092D: "b", 0x092E: "m",
        0x092F: "", 0x0930: "r", 0x0932: "l", 0x0933: "l", 0x0935: "v",
        0x0936: "s", 0x0937: "s", 0x0938: "s", 0x0939: "h",
        0x0958: "k", 0x0959: "k", 0x095A: "g", 0x095B: "j", 0x095C: "r", 0x095D: "r", 0x095E: "p", 0x095F: ""
    ]

    static func isDevanagari(_ word: String) -> Bool {
        word.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) }
    }

    /// A coarse consonant skeleton shared by Roman and Devanagari spellings.
    /// "Pawan" and its Devanagari spelling both give "pvn"; "vendor" and its Devanagari spelling give "vndr";
    /// "Neha" and its Devanagari spelling give "nh". Vowels and y are dropped. A lone h is kept, and
    /// ch, kh, gh, th, dh, bh, sh, jh, ph fold into one consonant.
    static func skeleton(_ word: String) -> String {
        let scalars = Array(word.lowercased().unicodeScalars)
        var output: [Character] = []
        func push(_ text: String) {
            for character in text where output.last != character { output.append(character) }
        }
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if (0x0900...0x097F).contains(scalar.value) {
                if scalar.value == 0x0915, index + 2 < scalars.count, scalars[index + 1].value == 0x094D,
                   scalars[index + 2].value == 0x0937 {
                    push("ks")
                    index += 3
                    continue
                }
                if let mapped = devanagari[scalar.value] { push(mapped) }
                index += 1
                continue
            }
            guard scalar.isASCII, scalar.properties.isAlphabetic else { index += 1; continue }
            let character = Character(scalar)
            let next: Character? = index + 1 < scalars.count && scalars[index + 1].isASCII
                ? Character(scalars[index + 1]) : nil
            if next == "h" {
                switch character {
                case "c": push("C"); index += 2; continue
                case "k", "g", "t", "d", "b", "s", "j", "p": push(String(character)); index += 2; continue
                default: break
                }
            }
            switch character {
            case "a", "e", "i", "o", "u", "y": break
            case "h": push("h")
            case "w": push("v")
            case "f": push("p")
            case "z": push("j")
            case "q": push("k")
            case "x": push("ks")
            case "c": push(next == "e" || next == "i" ? "s" : "k")
            default: push(String(character))
            }
            index += 1
        }
        return String(output)
    }

    // MARK: Words

    /// Lower-cased words of a text, letters and digits only.
    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Search keys of a text: stemmed word, skeleton and concept keys. Stop words are dropped.
    static func keys(_ text: String) -> [String] {
        var output: [String] = []
        for raw in words(text) where !VidurTokenizer.stopWords.contains(raw) {
            output += keys(forWord: raw)
        }
        return output
    }

    static func keys(forWord raw: String) -> [String] {
        let normalized = VidurTokenizer.normalize(raw)
        guard normalized.count >= 2 || normalized.first?.isNumber == true else { return [] }
        var output = [normalized]
        let sk = skeleton(raw)
        let isDev = isDevanagari(raw)
        if sk.count >= (isDev ? 2 : 3) { output.append("sk:" + sk) }
        if let concept = conceptTables.token[normalized] ?? (sk.count >= (isDev ? 2 : 3) ? conceptTables.skeleton[sk] : nil) {
            output.append("cx:" + concept)
        }
        return output
    }

    // MARK: Concepts

    /// The first word of a group names the concept. Latin, Hinglish and Devanagari spellings share it.
    private static let aliasGroups: [[String]] = [
        ["budget", "बजट", "kharcha", "kharch", "खर्चा", "खर्च", "funds", "paisa", "पैसा", "paise"],
        ["vendor", "वेंडर", "supplier", "सप्लायर"],
        ["launch", "लॉन्च", "लांच", "release", "रिलीज", "rollout"],
        ["price", "pricing", "rate", "rates", "कीमत", "keemat", "qeemat", "daam", "दाम", "प्राइसिंग", "प्राइस", "cost"],
        ["hiring", "hire", "recruitment", "bharti", "भर्ती", "हायरिंग"],
        ["contract", "कॉन्ट्रैक्ट", "अनुबंध"],
        ["client", "customer", "क्लाइंट", "कस्टमर", "ग्राहक", "grahak"],
        ["design", "डिज़ाइन", "डिजाइन"],
        ["presentation", "प्रेजेंटेशन", "deck", "slides", "ppt"],
        ["payment", "पेमेंट", "भुगतान", "bhugtan", "invoice", "इनवॉइस", "bill", "बिल"],
        ["review", "रिव्यू", "समीक्षा"],
        ["report", "रिपोर्ट"],
        ["testing", "test", "टेस्टिंग", "टेस्ट", "qa"],
        ["salary", "सैलरी", "वेतन", "payroll"],
        ["marketing", "मार्केटिंग", "campaign", "कैंपेन"],
        ["office", "ऑफिस", "दफ्तर"],
        ["server", "सर्वर", "hosting", "होस्टिंग"],
        ["training", "ट्रेनिंग", "प्रशिक्षण"],
        ["target", "टारगेट", "लक्ष्य"],
        ["sales", "सेल्स", "बिक्री", "bikri"],
        ["leave", "छुट्टी", "chhutti", "holiday"],
        ["feedback", "फीडबैक", "सुझाव"],
        ["website", "वेबसाइट", "site", "साइट"],
        ["quote", "quotation", "कोटेशन"],
        ["delay", "देरी", "deri", "late", "postpone", "postponed"],
        ["pune", "पुणे"],
        ["mumbai", "मुंबई"],
        ["delhi", "दिल्ली"],
        ["roadmap", "रोडमैप"],
        ["checklist", "चेकलिस्ट"],
        ["agenda", "एजेंडा"],
        ["demo", "डेमो"],
        ["partner", "पार्टनर", "partnership"],
        ["investor", "इन्वेस्टर", "funding", "फंडिंग"]
    ]

    private static let conceptTables: (token: [String: String], skeleton: [String: String]) = {
        var token: [String: String] = [:]
        var skeletons: [String: String] = [:]
        for group in aliasGroups {
            guard let first = group.first else { continue }
            let concept = VidurTokenizer.normalize(first.lowercased())
            for word in group {
                let lowered = word.lowercased()
                token[VidurTokenizer.normalize(lowered)] = concept
                let sk = VidurScript.skeleton(lowered)
                if sk.count >= 2, skeletons[sk] == nil { skeletons[sk] = concept }
            }
        }
        return (token, skeletons)
    }()
}

// MARK: - People

struct VidurPerson: Equatable, Sendable {
    let canonical: String
    /// Lower-cased first-name spellings seen for this person (Latin, Hinglish, Devanagari).
    let firsts: Set<String>
}

struct VidurPersonIndex {
    private(set) var people: [VidurPerson] = []

    static func isGenericLabel(_ raw: String) -> Bool {
        let value = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return true }
        if ["note", "notes", "you", "me", "unknown", "unknown speaker", "speaker"].contains(value) { return true }
        if value.hasPrefix("speaker") {
            return value.dropFirst(7).allSatisfy { $0.isNumber || $0 == " " || $0 == "_" || $0 == "-" }
        }
        if value.hasPrefix("s"), value.count > 1, value.dropFirst().allSatisfy(\.isNumber) { return true }
        return false
    }

    static let honorifics: Set<String> = ["dr", "mr", "mrs", "ms", "miss", "shri", "smt", "prof", "sir", "madam", "ji"]

    static func firstToken(_ name: String) -> String? {
        var tokens = name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        while tokens.count > 1, let first = tokens.first, honorifics.contains(first) { tokens.removeFirst() }
        return tokens.first
    }

    static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let left = VidurScript.skeleton(lhs)
        guard !left.isEmpty, left == VidurScript.skeleton(rhs) else { return false }
        if left.count >= 2 { return true }
        // A one-consonant skeleton ("n" for Neha) is only trusted across scripts, for words of 3+ letters.
        return VidurScript.isDevanagari(lhs) != VidurScript.isDevanagari(rhs)
            && lhs.unicodeScalars.count >= 3 && rhs.unicodeScalars.count >= 3
    }

    init(names: [String]) {
        var canonicals: [String] = []
        var firsts: [Set<String>] = []
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !Self.isGenericLabel(name), let first = Self.firstToken(name), first.count >= 2 else { continue }
            if let found = firsts.firstIndex(where: { set in set.contains { Self.sameName($0, first) } }) {
                firsts[found].insert(first)
                let current = canonicals[found]
                let currentIsDev = VidurScript.isDevanagari(current)
                let newIsDev = VidurScript.isDevanagari(name)
                if (currentIsDev && !newIsDev)
                    || (currentIsDev == newIsDev && name.split(separator: " ").count > current.split(separator: " ").count) {
                    canonicals[found] = name
                }
            } else {
                canonicals.append(name)
                firsts.append([first])
            }
        }
        people = zip(canonicals, firsts).map { VidurPerson(canonical: $0, firsts: $1) }
    }

    func person(forWord word: String) -> VidurPerson? {
        guard word.count >= 2 else { return nil }
        return people.first { person in person.firsts.contains { Self.sameName($0, word) } }
    }

    func person(forRaw raw: String?) -> VidurPerson? {
        guard let raw, let first = Self.firstToken(raw) else { return nil }
        return person(forWord: first)
    }

    func matches(_ raw: String?, _ person: VidurPerson) -> Bool {
        guard let raw, let first = Self.firstToken(raw) else { return false }
        return person.firsts.contains { Self.sameName($0, first) }
    }

    /// True when any word of `text` is this person's first name.
    func mentions(_ text: String, _ person: VidurPerson) -> Bool {
        VidurScript.words(text).contains { word in
            word.count >= 2 && person.firsts.contains { Self.sameName($0, word) }
        }
    }
}
