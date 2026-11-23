import Foundation

struct HindiKeyedTask {
    let turn: Int
    let piece: Int
    let task: SuggestedTask
}

struct HindiDecision {
    var text: String
    var evidence: [SourceEvidence]
    var proposed: Bool
    var detail: String?
    var turnIndex: Int
}

struct HindiOpenIssue {
    var subject: String
    var pending: Bool
    var nextMeeting: Bool
    var undecided: Bool
    var evidence: [SourceEvidence]
    var turnIndex: Int

    var text: String {
        let suffix = nextMeeting ? " (next meeting)" : ""
        if undecided { return subject + " not yet decided" + suffix }
        if pending { return subject + " is still pending" + suffix }
        return subject + " to be discussed in the next meeting"
    }
}

struct HindiTopic {
    var title: String
    var evidence: SourceEvidence
}

struct HindiOpinion {
    var subject: String
    var reason: String?
    var evidence: SourceEvidence
}

/// Everything the Hindi/Hinglish grammar found in a transcript.
struct HindiAnalysis {
    var tasks: [HindiKeyedTask] = []
    var decisions: [HindiDecision] = []
    var openIssues: [HindiOpenIssue] = []
    var topics: [HindiTopic] = []
    var statementTopics: [String] = []
    var opinions: [HindiOpinion] = []
    var claimedKeys: Set<String> = []
    var hasDevanagari = false

    var isActive: Bool {
        !(tasks.isEmpty && decisions.isEmpty && openIssues.isEmpty && topics.isEmpty)
    }

    var agendaTopics: [String] { topics.map { $0.title } }

    /// True when the Hindi grammar already handled this sentence, so the older
    /// rules must not produce a second, lower quality item from it.
    func isClaimed(_ sentence: String) -> Bool {
        if claimedKeys.isEmpty { return false }
        for part in sentence.components(separatedBy: "\u{0964}") {
            let key = HindiText.claimKey(part)
            if !key.isEmpty, claimedKeys.contains(key) { return true }
        }
        return false
    }
}

enum HindiMeetingExtractor {
    static func analyze(_ turns: [AnalysisTurn], context: ExtractionContext) -> HindiAnalysis {
        let runner = Runner(turns: turns, context: context)
        return runner.run()
    }

    /// True when a "chalo ... karte hain" sentence names a date or stresses the choice, so it is a decision
    /// and not just "let's start the meeting".
    static func settlesChoice(_ sentence: String) -> Bool {
        let keys = HindiText.tokenize(sentence).map { $0.key }
        if keys.contains("hi") || keys.contains("final") { return true }
        for index in 0..<keys.count where index + 1 < keys.count {
            if Int(keys[index]) != nil, HindiText.months.contains(keys[index + 1]) { return true }
        }
        return false
    }

    // MARK: - Vocabulary

    static let leadFillers: Set<String> = [
        "haan", "ji", "hello", "hi", "namaste", "accha", "ok", "okay", "aur", "to", "toh", "arre", "are", "so",
        "well", "and", "also", "then", "zaroor", "bilkul", "sure", "yes", "yeah", "right", "great", "perfect",
        "achha", "dekho", "suno", "waise", "matlab", "phir", "fir", "actually", "basically", "lekin", "thik"
    ]
    static let tailFillers: Set<String> = [
        "hai", "hain", "ho", "hoga", "hogi", "honge", "na", "ji", "please", "plz", "pls", "to", "toh", "zara", "yaar", "bhai"
    ]
    static let pronouns: Set<String> = [
        "main", "mai", "mujhe", "mujhse", "hum", "hamein", "tum", "tumhe", "tumse", "aap", "aapko", "tu", "wo", "ye", "yah",
        "yahi", "us", "is", "uska", "iska", "mere", "hamara", "i", "you", "we"
    ]
    static let objectNoise: Set<String> = [
        "tak", "ko", "ka", "ki", "ke", "se", "par", "pe", "mein", "bhi", "hi", "ek", "ab", "abhi", "kya", "na",
        "please", "plz", "zara", "jaldi", "to", "aur", "ya", "phir", "bas", "kuch", "sab"
    ]
    static let phraseNoise: Set<String> = [
        "ko", "ka", "ki", "ke", "se", "par", "pe", "mein", "bhi", "hi", "ek", "ab", "abhi", "kya", "na", "to", "ya",
        "yah", "yahi", "ye", "wo", "wahi", "is", "us", "hamein", "hum", "main", "tum", "aap", "mujhe", "lagta", "hai",
        "hain", "ho", "hoga", "mere", "hisaab", "khayal", "ki", "isko", "usko", "aur", "chalo", "thik", "haan",
        "karna", "karni", "karne", "kar", "karte", "karenge", "lete", "rakhte", "chahiye", "sahi", "rahega", "accha"
    ]
    static let documentWords: Set<String> = [
        "agenda", "report", "presentation", "plan", "deck", "document", "notes", "summary", "proposal", "budget",
        "schedule", "timeline", "slides", "sheet", "minutes", "draft", "email", "mail", "invoice", "quote",
        "contract", "list"
    ]
    static let determiners: Set<String> = ["the", "a", "an", "this", "that", "our", "my", "your", "his", "her", "their", "some", "all"]
    static let englishVerbs: Set<String> = [
        "send", "share", "prepare", "create", "update", "review", "approve", "confirm", "schedule", "contact", "check",
        "provide", "complete", "submit", "draft", "call", "email", "deliver", "finalize", "finalise", "investigate",
        "resolve", "book", "organize", "organise", "arrange", "fix", "ping", "remind", "coordinate", "publish",
        "forward", "upload", "notify", "inform", "discuss", "cancel", "reschedule", "follow", "test"
    ]
    static let subjectNoise: Set<String> = ["abhi", "ab", "bhi", "to", "hi", "ka", "ki", "ke", "ko", "par", "pe", "mein", "se",
                "ye", "yah", "wo", "uska", "uski", "us", "is", "isko", "usko", "hai", "hain", "ho", "hua", "hui", "hue",
                "ya", "nahi", "karna", "karne", "karni", "chahiye", "kya", "agli", "agle", "meeting", "baat", "karenge",
                "hamara", "tha", "gaya", "pata", "wala", "sab", "kuch"]
    static let launchVerbs: Set<String> = ["launch", "release", "ship", "start", "deploy", "publish", "begin"]

    static let nounVerbs: [String: String] = [
        "taiyaar": "Prepare", "baat": "Discuss", "shuru": "Start", "khatam": "Finish", "poora": "Complete", "final": "Finalize"
    ]
    static let baseLemma: [String: String] = [
        "kar": "Handle", "bhej": "Send", "bana": "Create", "de": "Provide", "dekh": "Review"
    ]
    static let stemKeys: Set<String> = ["kar", "bhej", "bana", "de", "dekh"]

    enum Person { case first, second, third }

    struct Inflection {
        let person: Person
        let aux: Bool
        let stem: String?
        let modal: Bool
        let obligation: Bool
    }

    static let inflections: [String: Inflection] = {
        var table: [String: Inflection] = [:]
        func add(_ keys: [String], _ person: Person, aux: Bool, stem: String?, modal: Bool = false, obligation: Bool = false) {
            for key in keys {
                table[key] = Inflection(person: person, aux: aux, stem: stem, modal: modal, obligation: obligation)
            }
        }
        add(["dena", "do", "dijiye", "lo", "lena"], .second, aux: true, stem: nil)
        add(["doge", "dogi", "loge", "logi"], .second, aux: true, stem: nil)
        add(["sakte", "sakti", "sakta"], .second, aux: true, stem: nil, modal: true)
        add(["dunga", "dungi", "lunga", "lungi"], .first, aux: true, stem: nil)
        add(["dega", "degi", "denge", "lega", "legi", "lenge"], .third, aux: true, stem: nil)
        add(["karo", "kijiye", "kariye", "karen", "karoge", "karogi"], .second, aux: false, stem: "kar")
        add(["karna", "karni", "karne"], .second, aux: false, stem: "kar", obligation: true)
        add(["karega", "karegi", "karenge"], .third, aux: false, stem: "kar")
        add(["karunga", "karungi"], .first, aux: false, stem: "kar")
        add(["bhejo", "bhejiye", "bhejoge", "bhejogi"], .second, aux: false, stem: "bhej")
        add(["bhejna"], .second, aux: false, stem: "bhej", obligation: true)
        add(["bhejega", "bhejegi", "bhejenge"], .third, aux: false, stem: "bhej")
        add(["bhejunga", "bhejungi"], .first, aux: false, stem: "bhej")
        add(["banao", "banaiye", "banaoge", "banaogi"], .second, aux: false, stem: "bana")
        add(["banana"], .second, aux: false, stem: "bana", obligation: true)
        add(["banayega", "banayegi", "banayenge"], .third, aux: false, stem: "bana")
        add(["banaunga", "banaungi"], .first, aux: false, stem: "bana")
        add(["dekhna"], .second, aux: false, stem: "dekh", obligation: true)
        add(["dekhega", "dekhegi", "dekhenge"], .third, aux: false, stem: "dekh")
        add(["dekhunga", "dekhungi"], .first, aux: false, stem: "dekh")
        return table
    }()

    // MARK: - Runner

    private struct LeadScan {
        var start: Int
        var vocative: HindiToken?
        var chalo: Bool
    }

    private struct Proposal {
        var text: String
        var detail: String?
        var evidence: SourceEvidence
        var turnIndex: Int
        var keys: Set<String>
    }

    private struct Draft {
        var title: String
        var owner: String?
        var deadline: String?
        var evidence: [SourceEvidence]
        var promiseEvidence: [SourceEvidence]
        var objectKeys: Set<String>
        var turn: Int
        var piece: Int
        var speaker: String?
        var isRequest: Bool
        var isQuestion: Bool
        var confirmed: Bool
    }

    private final class Runner {
        let turns: [AnalysisTurn]
        let context: ExtractionContext
        var analysis = HindiAnalysis()
        var drafts: [Draft] = []
        var lastProposal: Proposal?
        var lastDecisionIndex: Int?
        var lastOpenIndex: Int?
        var observed: [String] = []
        var pieces: [[String]] = []

        init(turns: [AnalysisTurn], context: ExtractionContext) {
            self.turns = turns
            self.context = context
        }

        func run() -> HindiAnalysis {
            pieces = ActionExtractor.sentencePieces(turns)
            prescan()
            for (turnIndex, turn) in turns.enumerated() {
                for (pieceIndex, piece) in pieces[turnIndex].enumerated() {
                    let devanagari = HindiText.containsDevanagari(piece)
                    if !devanagari { addEnglishTopics(piece, turn: turn) }
                    // Devanagari and romanized Hindi share one grammar (the lexicon folds Devanagari
                    // onto the same keys). Plain English is left to the English rules.
                    guard devanagari || HindiText.looksRomanizedHindi(piece) else { continue }
                    if devanagari { analysis.hasDevanagari = true }
                    var claimed = false
                    for clause in HindiText.clauses(of: HindiText.tokenize(piece)) {
                        if processClause(clause, piece: piece, turnIndex: turnIndex, pieceIndex: pieceIndex, turn: turn) {
                            claimed = true
                        }
                    }
                    if claimed { analysis.claimedKeys.insert(HindiText.claimKey(piece)) }
                }
            }
            finishTasks()
            return analysis
        }

        // MARK: Names

        func prescan() {
            for piece in pieces.flatMap({ $0 }) where HindiText.looksHindi(piece) {
                let scan = scanLead(HindiText.tokenize(piece))
                if let vocative = scan.vocative { observed.append(vocative.raw) }
            }
        }

        func isNameCandidate(_ token: HindiToken) -> Bool {
            if token.isDevanagari { return !token.isKnown && token.raw.count >= 2 }
            guard let first = token.raw.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first) else { return false }
            return ActionExtractor.resolveOwner(token.raw, context: context) != nil
        }

        func isKnownPerson(_ token: HindiToken) -> Bool {
            let people = context.participants
            if HindiText.matchParticipant(token.raw, participants: people) != nil { return true }
            for name in observed where HindiText.namesMatch(name, token.raw) { return true }
            return false
        }

        func ownerName(_ token: HindiToken) -> String {
            let people = context.participants.filter { !$0.lowercased().hasPrefix("speaker") }
            if let match = HindiText.matchParticipant(token.raw, participants: people) { return match }
            return HindiText.displayName(token.raw)
        }

        func scanLead(_ tokens: [HindiToken]) -> LeadScan {
            var scan = LeadScan(start: 0, vocative: nil, chalo: false)
            var guardCount = 0
            while scan.start < tokens.count, guardCount < 8 {
                guardCount += 1
                let token = tokens[scan.start]
                if token.key == "chalo" { scan.chalo = true; scan.start += 1; continue }
                if token.key == "thik", scan.start + 1 < tokens.count, tokens[scan.start + 1].key == "hai" {
                    scan.start += 2
                    continue
                }
                if HindiMeetingExtractor.leadFillers.contains(token.key) { scan.start += 1; continue }
                if scan.vocative == nil, isNameCandidate(token) {
                    var isVocative = token.commaAfter
                    if !isVocative, scan.start + 1 < tokens.count {
                        let next = tokens[scan.start + 1].key
                        isVocative = next == "kya" || next == "tum" || next == "aap" || next == "please" || next == "plz"
                    }
                    if isVocative { scan.vocative = token; scan.start += 1; continue }
                }
                break
            }
            return scan
        }

        // MARK: Clause

        func processClause(_ tokens: [HindiToken], piece: String, turnIndex: Int, pieceIndex: Int,
                           turn: AnalysisTurn) -> Bool {
            let scan = scanLead(tokens)
            guard scan.start < tokens.count else { return false }
            let rest = Array(tokens[scan.start...])
            let keys = rest.map { $0.key }
            let quote = HindiText.text(of: tokens, in: piece)
            let evidence = SourceEvidence(turnID: turn.id, quote: quote)
            let questionWords: Set<String> = ["kya", "kaun", "kab", "kyun", "kaise", "kahan", "kitna"]
            let isQuestion = quote.contains("?") || keys.contains(where: { questionWords.contains($0) })

            if !isQuestion {
                if handleAgenda(rest, keys: keys, evidence: evidence) { return true }
                if handleOpen(rest, keys: keys, evidence: evidence, turnIndex: turnIndex) { return true }
                if handleDecision(rest, keys: keys, chalo: scan.chalo, evidence: evidence, turnIndex: turnIndex) { return true }
                if handleProposal(rest, keys: keys, evidence: evidence, turnIndex: turnIndex) { return true }
                if handleOpinion(rest, keys: keys, evidence: evidence) { return true }
            }
            return handleTask(rest, keys: keys, vocative: scan.vocative, isQuestion: isQuestion, quote: quote,
                              piece: piece, turn: turn, turnIndex: turnIndex, pieceIndex: pieceIndex)
        }

        // MARK: Topics

        func addTopic(_ title: String, evidence: SourceEvidence) {
            let words = Set(title.lowercased().split(separator: " ").map(String.init))
            for (index, existing) in analysis.topics.enumerated() {
                let known = Set(existing.title.lowercased().split(separator: " ").map(String.init))
                if words.isSubset(of: known) { return }
                if known.isSubset(of: words) {
                    analysis.topics[index] = HindiTopic(title: title, evidence: evidence)
                    return
                }
            }
            analysis.topics.append(HindiTopic(title: title, evidence: evidence))
        }

        func topicTitle(_ tokens: [HindiToken]) -> String? {
            let noise: Set<String> = ["ka", "ki", "ke", "par", "pe", "mein", "ko", "se", "the", "wala", "ek", "hamara",
                                      "hum", "hamein", "aaj", "bhi", "hi", "ya", "baare", "is", "us", "yah", "wo"]
            var words: [String] = []
            for token in tokens where !noise.contains(token.key) { words.append(token.display) }
            guard !words.isEmpty, words.count <= 4 else { return nil }
            return HindiText.capitalizeFirst(words.joined(separator: " "))
        }

        func splitTopics(_ tokens: [HindiToken]) -> [[HindiToken]] {
            var groups: [[HindiToken]] = []
            var current: [HindiToken] = []
            for token in tokens {
                if token.key == "aur" || token.key == "and" {
                    if !current.isEmpty { groups.append(current) }
                    current = []
                    continue
                }
                current.append(token)
                if token.commaAfter { groups.append(current); current = [] }
            }
            if !current.isEmpty { groups.append(current) }
            return groups
        }

        func handleAgenda(_ rest: [HindiToken], keys: [String], evidence: SourceEvidence) -> Bool {
            var groups: [[HindiToken]] = []
            var statement = false
            if let par = keys.firstIndex(where: { $0 == "par" || $0 == "pe" }), keys.contains("baat") {
                var begin = 0
                var sawLead = false
                for index in 0..<par where keys[index] == "aaj" || keys[index] == "hamein" || keys[index] == "hum" {
                    begin = index + 1
                    sawLead = true
                }
                if sawLead, par > begin {
                    groups = splitTopics(Array(rest[begin..<par]))
                    statement = true
                }
            }
            if groups.isEmpty, let agenda = keys.firstIndex(of: "agenda"), agenda + 2 < keys.count,
               keys[agenda + 1] == "hai" {
                groups = splitTopics(Array(rest[(agenda + 2)...]))
                statement = true
            }
            if groups.isEmpty, keys.first == "pehle" || keys.first == "ab", keys.contains("baat") {
                let markers: Set<String> = ["ki", "ke", "ka", "par", "pe"]
                if let marker = keys.indices.first(where: { $0 > 1 && markers.contains(keys[$0]) }) {
                    groups = [Array(rest[1..<marker])]
                }
            }
            guard !groups.isEmpty else { return false }
            var found = false
            for group in groups {
                guard let title = topicTitle(group) else { continue }
                addTopic(title, evidence: evidence)
                if statement { analysis.statementTopics.append(title) }
                found = true
            }
            return found
        }

        func addEnglishTopics(_ piece: String, turn: AnalysisTurn) {
            let patterns: [String] = [
                #"(?i)\b(?:we(?:'ll|\s+will|\s+are\s+going\s+to|\s+need\s+to|\s+should|\s+shall)|let(?:'s|s|\s+us))\s+(?:discuss|talk\s+about|cover|go\s+over)\s+(.+?)[.!?]*$"#,
                #"(?i)\b(?:the\s+)?agenda\s+(?:for\s+today\s+)?(?:is|includes)\s*:?\s+(.+?)[.!?]*$"#,
                #"(?i)\bon\s+the\s+agenda\s+(?:is|are)\s*:?\s+(.+?)[.!?]*$"#
            ]
            let banned: Set<String> = ["it", "this", "that", "them", "tomorrow", "later", "today", "next", "again", "more", "now"]
            let matchText = piece.replacingOccurrences(of: "\u{2019}", with: "'")
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(matchText.startIndex..<matchText.endIndex, in: matchText)
                guard let match = regex.firstMatch(in: matchText, options: [], range: range), match.numberOfRanges > 1,
                      let found = Range(match.range(at: 1), in: matchText) else { continue }
                let list = String(matchText[found]).replacingOccurrences(of: " and ", with: ",")
                for part in list.split(separator: ",") {
                    var words = part.split(separator: " ").map(String.init)
                    if words.first?.lowercased() == "the" { words.removeFirst() }
                    guard !words.isEmpty, words.count <= 3,
                          !words.contains(where: { banned.contains($0.lowercased()) }) else { continue }
                    addTopic(HindiText.capitalizeFirst(words.joined(separator: " ")),
                             evidence: SourceEvidence(turnID: turn.id, quote: piece))
                }
                return
            }
        }

        // MARK: Open issues

        func subjectTitle(_ tokens: [HindiToken]) -> String? {
var words: [String] = []
            for token in tokens where !HindiMeetingExtractor.subjectNoise.contains(token.key) {
                words.append(token.key == "aur" ? "and" : token.display)
            }
            guard !words.isEmpty else { return nil }
            if words.count > 4 { words = Array(words.prefix(4)) }
            return HindiText.capitalizeFirst(words.joined(separator: " "))
        }

        func qualifier(for tokens: [HindiToken], turnIndex: Int) -> String? {
            guard turnIndex > 0, let last = tokens.last(where: { ($0.isKnown || !$0.isDevanagari) && !HindiMeetingExtractor.subjectNoise.contains($0.key) }) else { return nil }
            var previous: [HindiToken] = []
            for piece in pieces[turnIndex - 1] { previous.append(contentsOf: HindiText.tokenize(piece)) }
            let previousKeys = previous.map { $0.key }
            guard previousKeys.contains(last.key) else { return nil }
            for index in 1..<max(1, previous.count - 1) where previousKeys[index] == "ke" && previousKeys[index + 1] == "liye" {
                let candidate = previous[index - 1]
                if candidate.key != last.key, !candidate.isDevanagari || candidate.isKnown { return candidate.display }
            }
            return nil
        }

        func handleOpen(_ rest: [HindiToken], keys: [String], evidence: SourceEvidence, turnIndex: Int) -> Bool {
            var marker: Int?
            var pending = false
            let decideWords: Set<String> = ["decide", "decided", "tay", "final", "faisla"]
            for index in 0..<keys.count {
                if decideWords.contains(keys[index]), index + 1 < keys.count, keys[index + 1] == "nahi" { marker = index; break }
                if keys[index] == "pata", index + 1 < keys.count, keys[index + 1] == "nahi" { marker = index; break }
                if keys[index] == "pending" { marker = index; pending = true; break }
            }
            let deferral = (keys.contains("agli") || keys.contains("agle")) && keys.contains("meeting") && keys.contains("baat")
            guard marker != nil || deferral else { return false }
            var subjectTokens: [HindiToken] = []
            if let marker = marker {
                subjectTokens = Array(rest[0..<marker])
            } else if let par = keys.firstIndex(where: { $0 == "par" || $0 == "pe" }) {
                subjectTokens = Array(rest[0..<par])
            }
            guard let subject = subjectTitle(subjectTokens) else {
                if let index = lastOpenIndex, turnIndex - analysis.openIssues[index].turnIndex <= 2 {
                    analysis.openIssues[index].evidence.append(evidence)
                    if deferral { analysis.openIssues[index].nextMeeting = true }
                }
                return true
            }
            var title = subject
            let parts = subject.split(separator: " ")
            if parts.count == 1, let extra = qualifier(for: subjectTokens, turnIndex: turnIndex) {
                title = HindiText.capitalizeFirst(extra) + " " + HindiText.lowercaseFirst(subject)
            }
            let undecided = marker != nil && !pending
            let wanted = Set(title.lowercased().split(separator: " ").map(String.init))
            for (index, issue) in analysis.openIssues.enumerated() {
                let have = Set(issue.subject.lowercased().split(separator: " ").map(String.init))
                if have == wanted {
                    analysis.openIssues[index].evidence.append(evidence)
                    if deferral { analysis.openIssues[index].nextMeeting = true }
                    lastOpenIndex = index
                    return true
                }
            }
            analysis.openIssues.append(HindiOpenIssue(subject: title, pending: pending, nextMeeting: deferral,
                undecided: undecided, evidence: [evidence], turnIndex: turnIndex))
            lastOpenIndex = analysis.openIssues.count - 1
            addTopic(subject, evidence: evidence)
            return true
        }

        // MARK: Decisions

        func isDayNumber(_ key: String) -> Bool {
            var digits = key
            for suffix in ["st", "nd", "rd", "th"] where digits.hasSuffix(suffix) { digits = String(digits.dropLast(2)) }
            guard let value = Int(digits) else { return false }
            return value >= 1 && value <= 31
        }

        func article(_ tokens: [HindiToken]) -> String {
            guard let first = tokens.first else { return "" }
            let known = tokens.allSatisfy { !$0.isDevanagari || $0.isKnown }
            if !known || HindiMeetingExtractor.determiners.contains(first.key) { return "" }
            if let character = first.key.first, character.isNumber { return "" }
            return "the "
        }

        /// Builds an English decision or proposal text, for example "Launch on 20 November".
        func phrase(_ tokens: [HindiToken], forFinal: Bool) -> (text: String, detail: String?)? {
            let words = tokens.filter { !HindiMeetingExtractor.phraseNoise.contains($0.key) }
            var date: String?
            var rest: [HindiToken] = []
            var index = 0
            while index < words.count {
                if index + 1 < words.count, isDayNumber(words[index].key), HindiText.months.contains(words[index + 1].key) {
                    date = words[index].key + " " + HindiText.capitalizeFirst(words[index + 1].key)
                    index += 2
                    continue
                }
                if HindiText.weekdays.contains(words[index].key), date == nil {
                    date = HindiText.capitalizeFirst(words[index].key)
                    index += 1
                    continue
                }
                rest.append(words[index])
                index += 1
            }
            let text = rest.map { $0.display }.joined(separator: " ")
            if rest.isEmpty {
                guard let date = date else { return nil }
                return ("Finalize " + date, date)
            }
            if let date = date {
                let last = rest[rest.count - 1].key
                if last == "date" || last == "deadline" { return (HindiText.capitalizeFirst(text) + " set to " + date, date) }
                return (HindiText.capitalizeFirst(text) + " on " + date, date)
            }
            if forFinal { return ("Finalize " + article(rest) + text, nil) }
            return (HindiText.capitalizeFirst(text), nil)
        }

        func addDecision(text: String, detail: String?, proposed: Bool, evidence: [SourceEvidence], turnIndex: Int) {
            for (index, existing) in analysis.decisions.enumerated() where existing.text.lowercased() == text.lowercased() {
                analysis.decisions[index].evidence.append(contentsOf: evidence)
                analysis.decisions[index].proposed = existing.proposed || proposed
                analysis.decisions[index].turnIndex = turnIndex
                lastDecisionIndex = index
                return
            }
            analysis.decisions.append(HindiDecision(text: text, evidence: evidence, proposed: proposed,
                                                    detail: detail, turnIndex: turnIndex))
            lastDecisionIndex = analysis.decisions.count - 1
        }

        func recentProposal(_ evidence: [SourceEvidence], turnIndex: Int, text: String, detail: String?) -> (Bool, [SourceEvidence]) {
            guard let proposal = lastProposal, turnIndex - proposal.turnIndex <= 3,
                  proposal.text.lowercased() == text.lowercased() || (detail != nil && proposal.detail == detail) else {
                return (false, evidence)
            }
            return (true, [proposal.evidence] + evidence)
        }

        func handleDecision(_ rest: [HindiToken], keys: [String], chalo: Bool, evidence: SourceEvidence,
                            turnIndex: Int) -> Bool {
            // "let's go with X"
            if let go = keys.firstIndex(of: "go"), go + 2 < keys.count, keys[go + 1] == "with" {
                let object = Array(rest[(go + 2)...]).filter { !HindiMeetingExtractor.phraseNoise.contains($0.key) || $0.key == "the" }
                guard !object.isEmpty else { return false }
                let words = object.map { $0.display }.joined(separator: " ")
                let text = "Go with " + article(object) + words
                addDecision(text: text, detail: nil, proposed: false, evidence: [evidence], turnIndex: turnIndex)
                return true
            }
            // "X ke saath chalte hain"
            if let saath = keys.firstIndex(of: "saath"), saath >= 2, keys[saath - 1] == "ke", keys.contains("chalte") {
                let object = Array(rest[0..<(saath - 1)]).filter { !HindiMeetingExtractor.phraseNoise.contains($0.key) }
                if !object.isEmpty {
                    let text = "Go with " + article(object) + object.map { $0.display }.joined(separator: " ")
                    addDecision(text: text, detail: nil, proposed: false, evidence: [evidence], turnIndex: turnIndex)
                    return true
                }
            }
            // "... final hai / final karte hain / tay hua"
            let allowedTail: Set<String> = ["hai", "hain", "ho", "gaya", "gayi", "hua", "karte", "kar", "dete", "lete",
                                            "karenge", "kiya", "diya", "liya", "hi", "bhi", "to", "chuke", "rahega"]
            let trigger: Set<String> = ["final", "tay", "decide", "decided"]
            for index in 0..<keys.count where trigger.contains(keys[index]) {
                if keys.contains("nahi") || keys.contains("agar") { return false }
                var tail = Array(keys[(index + 1)...])
                if let comma = rest[index...].firstIndex(where: { $0.commaAfter }), comma > index {
                    tail = Array(keys[(index + 1)...comma])
                }
                // "Stripe final hai kyunki price kam hai": the reason clause is not part of the decision.
                if let reason = tail.firstIndex(where: { $0 == "kyonki" || $0 == "because" || $0 == "isliye" }) {
                    tail = Array(tail[..<reason])
                }
                let isFinal = keys[index] == "final"
                if isFinal {
                    guard tail.allSatisfy({ allowedTail.contains($0) }) else { continue }
                } else {
                    guard let first = tail.first, ["hua", "ho", "kiya", "kar", "hui"].contains(first) else { continue }
                }
                var before = Array(rest[0..<index])
                if !isFinal, let ki = keys.firstIndex(of: "ki"), ki > index { before = Array(rest[(ki + 1)...]) }
                return applyDecision(before, evidence: evidence, turnIndex: turnIndex)
            }
            // "chalo X karte hain" settles a choice only when it names a date or stresses it.
            if chalo, let last = keys.last, ["hain", "hai"].contains(last) || last == "karenge" {
                let hasDate = zip(keys, keys.dropFirst()).contains { isDayNumber($0.0) && HindiText.months.contains($0.1) }
                if hasDate || keys.contains("hi") {
                    let verbs: Set<String> = ["karte", "karenge", "lete", "rakhte", "kar"]
                    let before = rest.filter { !verbs.contains($0.key) }
                    if let result = phrase(before, forFinal: true) {
                        addDecision(text: result.text, detail: result.detail, proposed: false, evidence: [evidence],
                                    turnIndex: turnIndex)
                        return true
                    }
                }
            }
            // "20 November सही रहेगा" confirming the previous proposal
            let confirms = (keys.contains("sahi") || keys.contains("thik") || keys.contains("accha")) && keys.contains("rahega")
            if confirms, let proposal = lastProposal, turnIndex - proposal.turnIndex <= 1 {
                let content = keys.filter { !HindiMeetingExtractor.phraseNoise.contains($0) }
                let overlaps = content.contains(where: { proposal.keys.contains($0) })
                if overlaps || content.isEmpty {
                    addDecision(text: proposal.text, detail: proposal.detail, proposed: true,
                                evidence: [proposal.evidence, evidence], turnIndex: turnIndex)
                    return true
                }
            }
            return false
        }

        func applyDecision(_ before: [HindiToken], evidence: SourceEvidence, turnIndex: Int) -> Bool {
            let content = before.filter { !HindiMeetingExtractor.phraseNoise.contains($0.key) }
            if content.isEmpty {
                // A bare "yah final hai" settles the latest proposal or decision.
                if let index = lastDecisionIndex, turnIndex - analysis.decisions[index].turnIndex <= 3,
                   lastProposal == nil || analysis.decisions[index].turnIndex >= lastProposal!.turnIndex {
                    analysis.decisions[index].evidence.append(evidence)
                    analysis.decisions[index].turnIndex = turnIndex
                    return true
                }
                if let proposal = lastProposal, turnIndex - proposal.turnIndex <= 3 {
                    addDecision(text: proposal.text, detail: proposal.detail, proposed: true,
                                evidence: [proposal.evidence, evidence], turnIndex: turnIndex)
                    return true
                }
                return false
            }
            guard let result = phrase(before, forFinal: true) else { return false }
            let merged = recentProposal([evidence], turnIndex: turnIndex, text: result.text, detail: result.detail)
            addDecision(text: result.text, detail: result.detail, proposed: merged.0, evidence: merged.1, turnIndex: turnIndex)
            return true
        }

        func handleProposal(_ rest: [HindiToken], keys: [String], evidence: SourceEvidence, turnIndex: Int) -> Bool {
            guard let chahiye = keys.firstIndex(of: "chahiye"), chahiye > 0 else { return false }
            var before = Array(rest[0..<chahiye])
            if let lagta = before.firstIndex(where: { $0.key == "lagta" }) {
                var cut = lagta + 1
                while cut < before.count, ["hai", "ki"].contains(before[cut].key) { cut += 1 }
                before = Array(before[cut...])
            }
            guard let result = phrase(before, forFinal: false) else { return false }
            let proposalKeys = Set(before.map { $0.key }.filter { !HindiMeetingExtractor.phraseNoise.contains($0) })
            lastProposal = Proposal(text: result.text, detail: result.detail, evidence: evidence,
                                    turnIndex: turnIndex, keys: proposalKeys)
            return true
        }

        func handleOpinion(_ rest: [HindiToken], keys: [String], evidence: SourceEvidence) -> Bool {
            guard let good = keys.firstIndex(of: "accha"), good > 0 else { return false }
            let skip: Set<String> = ["mere", "hisaab", "khayal", "se", "lagta", "hai", "ki", "ye", "wo", "bahut", "kaafi",
                                     "bhi", "hi", "wala", "to", "yah", "mujhe"]
            let subject = rest[0..<good].filter { !skip.contains($0.key) }
            guard !subject.isEmpty, subject.count <= 4 else { return false }
            var reason: String?
            let priceWords: [String] = ["price", "cost", "rate"]
            let lowWords: [String] = ["kam", "sasta", "cheap", "cheaper", "low"]
            if let price = priceWords.first(where: { keys.contains($0) }), lowWords.contains(where: { keys.contains($0) }) {
                reason = "lower " + price
            }
            let text = subject.map { $0.display }.joined(separator: " ")
            analysis.opinions.append(HindiOpinion(subject: HindiText.capitalizeFirst(text), reason: reason, evidence: evidence))
            return true
        }

        // MARK: Tasks

        func resolvedSpeaker(_ turn: AnalysisTurn) -> String? {
            guard let label = turn.speaker else { return nil }
            return context.speakerNames[label]
        }

        func handleTask(_ rest: [HindiToken], keys: [String], vocative: HindiToken?, isQuestion: Bool, quote: String,
                        piece: String, turn: AnalysisTurn, turnIndex: Int, pieceIndex: Int) -> Bool {
            var end = keys.count
            while end > 0, HindiMeetingExtractor.tailFillers.contains(keys[end - 1]) { end -= 1 }
            guard end >= 2, let inflection = HindiMeetingExtractor.inflections[keys[end - 1]] else { return false }
            var verbIndex = end - 1
            var stem = inflection.stem ?? ""
            if inflection.aux {
                guard HindiMeetingExtractor.stemKeys.contains(keys[end - 2]) else { return false }
                stem = keys[end - 2]
                verbIndex = end - 2
            }
            var lemma = HindiMeetingExtractor.baseLemma[stem] ?? "Handle"
            var objectEnd = verbIndex
            if stem == "kar", verbIndex >= 1 {
                let before = keys[verbIndex - 1]
                if let noun = HindiMeetingExtractor.nounVerbs[before] {
                    lemma = noun
                    objectEnd = verbIndex - 1
                } else if HindiMeetingExtractor.englishVerbs.contains(before) {
                    lemma = HindiText.capitalizeFirst(rest[verbIndex - 1].display)
                    objectEnd = verbIndex - 1
                }
            }
            let head = Array(rest[0..<objectEnd])
            let headKeys = head.map { $0.key }
            let hasSecond = headKeys.contains("tum") || headKeys.contains("aap") || headKeys.contains("tumhe") || headKeys.contains("aapko")
            let hasFirst = headKeys.contains("main") || headKeys.contains("hum") || headKeys.contains("hamein")

            // Owner
            var owner: String?
            var removed = Set<Int>()
            var koOwner = false
            var recipient: String?
            for (index, token) in head.enumerated() where token.key == "ko" && index >= 1 {
                let previous = head[index - 1]
                if isNameCandidate(previous), inflection.person != .first, !(lemma == "Send" && !isKnownPerson(previous)) {
                    owner = ownerName(previous)
                    koOwner = true
                    removed.insert(index - 1)
                    removed.insert(index)
                } else if (lemma == "Send" || lemma == "Provide"), !previous.isDevanagari || previous.isKnown {
                    recipient = previous.display
                    removed.insert(index - 1)
                    removed.insert(index)
                }
            }
            if let vocative = vocative, inflection.person == .second { owner = ownerName(vocative) }
            switch inflection.person {
            case .second:
                if inflection.modal {
                    guard vocative != nil || hasSecond || isQuestion else { return false }
                    if hasFirst && !hasSecond && vocative == nil { return false }
                } else if inflection.obligation {
                    guard owner != nil else { return false }
                } else {
                    guard vocative != nil || hasSecond || koOwner else { return false }
                }
            case .third:
                if owner == nil, let first = head.first, isNameCandidate(first), isKnownPerson(first) {
                    owner = ownerName(first)
                    removed.insert(0)
                }
                guard owner != nil else { return false }
            case .first:
                if hasSecond && !hasFirst { return false }
                owner = resolvedSpeaker(turn)
            }

            // Deadline
            var deadline: String?
            if let found = findDeadline(head) {
                deadline = HindiText.text(of: Array(head[found.lowerBound...found.upperBound]), in: piece)
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                for index in found { removed.insert(index) }
            }

            // Object
            var object: [HindiToken] = []
            for (index, token) in head.enumerated() where !removed.contains(index) {
                if HindiMeetingExtractor.pronouns.contains(token.key) || HindiMeetingExtractor.objectNoise.contains(token.key)
                    || HindiMeetingExtractor.leadFillers.contains(token.key) { continue }
                object.append(token)
            }
            guard !object.isEmpty else { return false }
            let objectKeys = Set(object.map { $0.key })
            if lemma == "Create", !objectKeys.isDisjoint(with: HindiMeetingExtractor.documentWords) { lemma = "Prepare" }
            var title = lemma + " " + article(object) + object.map { $0.display }.joined(separator: " ")
            if let recipient = recipient { title += " to the " + recipient }
            let evidence = SourceEvidence(turnID: turn.id, quote: quote)

            if inflection.person == .first {
                return mergePromise(title: title, owner: owner, deadline: deadline, evidence: evidence,
                                    objectKeys: objectKeys, turn: turn, turnIndex: turnIndex, pieceIndex: pieceIndex)
            }
            drafts.append(Draft(title: title, owner: owner, deadline: deadline, evidence: [evidence], promiseEvidence: [],
                                objectKeys: objectKeys, turn: turnIndex, piece: pieceIndex, speaker: turn.speaker,
                                isRequest: true, isQuestion: quote.hasSuffix("?"), confirmed: false))
            return true
        }

        func mergePromise(title: String, owner: String?, deadline: String?, evidence: SourceEvidence,
                          objectKeys: Set<String>, turn: AnalysisTurn, turnIndex: Int, pieceIndex: Int) -> Bool {
            for index in drafts.indices.reversed() {
                let draft = drafts[index]
                guard draft.isRequest, !draft.confirmed, turnIndex - draft.turn <= 3, turnIndex > draft.turn || pieceIndex > draft.piece else { continue }
                if let requester = draft.speaker, let speaker = turn.speaker, requester == speaker { continue }
                guard !draft.objectKeys.isDisjoint(with: objectKeys) else { continue }
                drafts[index].promiseEvidence.append(evidence)
                drafts[index].confirmed = true
                if drafts[index].owner == nil { drafts[index].owner = owner }
                if drafts[index].deadline == nil { drafts[index].deadline = deadline }
                return true
            }
            var resolved = owner
            if resolved == nil {
                resolved = drafts.last(where: { turnIndex - $0.turn == 1 && $0.owner != nil })?.owner
            }
            drafts.append(Draft(title: title, owner: resolved, deadline: deadline, evidence: [evidence], promiseEvidence: [],
                                objectKeys: objectKeys, turn: turnIndex, piece: pieceIndex, speaker: turn.speaker,
                                isRequest: false, isQuestion: false, confirmed: false))
            return true
        }

        /// Index range of the first deadline phrase ("Friday तक", "कल तक", "20 November").
        func findDeadline(_ tokens: [HindiToken]) -> ClosedRange<Int>? {
            let keys = tokens.map { $0.key }
            for index in 0..<keys.count {
                let key = keys[index]
                let hasTak = index + 1 < keys.count && keys[index + 1] == "tak"
                if isDayNumber(key), index + 1 < keys.count, HindiText.months.contains(keys[index + 1]) {
                    let upper = index + 2 < keys.count && keys[index + 2] == "tak" ? index + 2 : index + 1
                    return index...upper
                }
                if HindiText.weekdays.contains(key) || key == "kal" || key == "parso" || key == "aaj" || key == "tomorrow" || key == "today" {
                    let lower = index > 0 && (keys[index - 1] == "agle" || keys[index - 1] == "by") ? index - 1 : index
                    return lower...(hasTak ? index + 1 : index)
                }
                if (key == "agle" || key == "agli" || key == "is"), index + 1 < keys.count, keys[index + 1] == "hafte" {
                    return index...(index + 2 < keys.count && keys[index + 2] == "tak" ? index + 2 : index + 1)
                }
            }
            return nil
        }

        func finishTasks() {
            for draft in drafts {
                var evidence = draft.evidence
                if ActionExtractor.isCancelled(turns: turns, pieces: pieces, turnIndex: draft.turn, sentenceIndex: draft.piece) {
                    continue
                }
                if draft.isRequest {
                    let outcome = ActionExtractor.replies(turns: turns, pieces: pieces, turnIndex: draft.turn,
                                                          sentenceIndex: draft.piece, requestIsQuestion: draft.isQuestion)
                    if outcome.refused { continue }
                    if let accepted = outcome.acceptance { evidence.append(accepted) }
                }
                evidence.append(contentsOf: draft.promiseEvidence)
                var seen = Set<String>()
                var unique: [SourceEvidence] = []
                for item in evidence where seen.insert(item.turnID + "\u{0}" + item.quote).inserted { unique.append(item) }
                let task = SuggestedTask(title: draft.title, category: MeetingAnalysisReducer.category(for: draft.title),
                                         owner: draft.owner, deadlineText: draft.deadline, priority: nil, evidence: unique)
                analysis.tasks.append(HindiKeyedTask(turn: draft.turn, piece: draft.piece, task: task))
            }
        }
    }
}

