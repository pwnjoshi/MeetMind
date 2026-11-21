import Foundation

/// Names the reducer may attach to extracted tasks. Everything is optional: with
/// an empty context the extractor still finds tasks but only uses names that are
/// written in the sentence itself.
struct ExtractionContext {
    /// Named meeting attendees (never generic labels such as "Speaker 1").
    var participants: [String] = []
    /// Maps a transcript speaker label to the attendee name the user gave it.
    var speakerNames: [String: String] = [:]
}

/// Grounded, deterministic extraction of requests, assignments and commitments
/// in English, Hinglish (Latin) and Hindi (Devanagari). Every task quotes the
/// exact transcript sentence it came from and stays a suggestion for review.
enum ActionExtractor {
    // MARK: - Public entry point

    static func tasks(in turns: [AnalysisTurn], context: ExtractionContext) -> [SuggestedTask] {
        tasks(in: turns, context: context, hindi: HindiMeetingExtractor.analyze(turns, context: context))
    }

    static func tasks(in turns: [AnalysisTurn], context: ExtractionContext, hindi: HindiAnalysis) -> [SuggestedTask] {
        let rules = englishRules()
        let pieces = sentencePieces(turns)
        var keyed: [HindiKeyedTask] = hindi.tasks
        for (turnIndex, turn) in turns.enumerated() {
            for (sentenceIndex, sentence) in pieces[turnIndex].enumerated() {
                guard !hindi.isClaimed(sentence) else { continue }
                guard !MeetingAnalysisReducer.isNonCommittalSentence(sentence) else { continue }
                guard var task = extract(sentence, turn: turn, rules: rules, context: context) else { continue }
                let outcome = replies(turns: turns, pieces: pieces, turnIndex: turnIndex,
                                      sentenceIndex: sentenceIndex, requestIsQuestion: sentence.hasSuffix("?"))
                if outcome.refused { continue }
                if let accepted = outcome.acceptance {
                    task = SuggestedTask(title: task.title, category: task.category, owner: task.owner,
                        deadlineText: task.deadlineText, priority: task.priority,
                        evidence: task.evidence + [accepted])
                }
                keyed.append(HindiKeyedTask(turn: turnIndex, piece: sentenceIndex, task: task))
            }
        }
        var ordered: [(offset: Int, element: HindiKeyedTask)] = []
        for (offset, item) in keyed.enumerated() { ordered.append((offset, item)) }
        ordered.sort { lhs, rhs in
            if lhs.element.turn != rhs.element.turn { return lhs.element.turn < rhs.element.turn }
            if lhs.element.piece != rhs.element.piece { return lhs.element.piece < rhs.element.piece }
            return lhs.offset < rhs.offset
        }
        return ordered.map { $0.element.task }
    }

    /// True when the sentence that grounds a (model-proposed) task was a request that
    /// the next speaker explicitly declined ("I can't", "nahi ho payega").
    static func isRefusedRequest(evidence: [SourceEvidence], in turns: [AnalysisTurn]) -> Bool {
        guard let first = evidence.first, let turnIndex = turns.firstIndex(where: { $0.id == first.turnID }) else { return false }
        let pieces = sentencePieces(turns)
        guard let sentenceIndex = pieces[turnIndex].firstIndex(where: { $0.contains(first.quote) || first.quote.contains($0) }) else {
            return false
        }
        let sentence = pieces[turnIndex][sentenceIndex]
        return replies(turns: turns, pieces: pieces, turnIndex: turnIndex, sentenceIndex: sentenceIndex,
                       requestIsQuestion: sentence.hasSuffix("?")).refused
    }

    static func sentencePieces(_ turns: [AnalysisTurn]) -> [[String]] {
        turns.map { turn in
            MeetingAnalysisReducer.sentences(in: turn.text).flatMap { sentence in
                sentence.components(separatedBy: "\u{0964}")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }
    }

    // MARK: - Replies (acceptance and refusal)

    private struct Reply { let turnID: String; let sentence: String }

    static func replies(turns: [AnalysisTurn], pieces: [[String]], turnIndex: Int, sentenceIndex: Int,
                                requestIsQuestion: Bool) -> (refused: Bool, acceptance: SourceEvidence?) {
        for reply in replyWindow(turns: turns, pieces: pieces, turnIndex: turnIndex, sentenceIndex: sentenceIndex) {
            if isRefusal(reply.sentence, requestIsQuestion: requestIsQuestion) { return (true, nil) }
            if isAcceptance(reply.sentence) { return (false, SourceEvidence(turnID: reply.turnID, quote: reply.sentence)) }
        }
        return (false, nil)
    }

    private static func replyWindow(turns: [AnalysisTurn], pieces: [[String]], turnIndex: Int,
                                    sentenceIndex: Int) -> [Reply] {
        var replies: [Reply] = []
        let requester = turns[turnIndex].speaker
        let sameTurn = pieces[turnIndex].dropFirst(sentenceIndex + 1).prefix(2)
        for sentence in sameTurn { replies.append(Reply(turnID: turns[turnIndex].id, sentence: sentence)) }
        var next = turnIndex + 1
        var taken = 0
        while next < turns.count, taken < 2 {
            let candidate = turns[next]
            // A reply from the requester's own voice is not an acceptance.
            if requester == nil || candidate.speaker == nil || candidate.speaker != requester {
                for sentence in pieces[next].prefix(3) { replies.append(Reply(turnID: candidate.id, sentence: sentence)) }
            }
            taken += 1
            next += 1
        }
        return replies
    }

    private static func wordCount(_ sentence: String) -> Int {
        sentence.split(whereSeparator: { $0.isWhitespace }).count
    }

    private static let refusalPhrases: [String] = [
        "can't do", "cant do", "cannot do", "can't take", "can't handle", "won't be able", "not able to do",
        "unable to do", "i won't", "i can't", "i cannot", "no i can't", "sorry i can't", "not possible",
        "nahi ho payega", "nahi ho paega", "nahi ho payegi", "nahi kar paunga", "nahi kar paungi",
        "nahi kar sakta", "nahi kar sakti", "nahi kar sakunga", "nahi kar sakungi", "mujhse nahi",
        "mere se nahi", "nahi ho sakta", "main nahi kar", "mai nahi kar",
        "\u{092E}\u{0941}\u{091D}\u{0938}\u{0947} \u{0928}\u{0939}\u{0940}\u{0902}",
        "\u{0928}\u{0939}\u{0940}\u{0902} \u{0939}\u{094B} \u{092A}\u{093E}\u{090F}\u{0917}\u{093E}",
        "\u{0928}\u{0939}\u{0940}\u{0902} \u{0915}\u{0930} \u{092A}\u{093E}\u{090A}\u{0902}\u{0917}\u{093E}"
    ]
    private static let exactRefusals: Set<String> = Set<String>(["no", "nope", "no sorry", "sorry no", "cant", "can't", "cannot", "nahi", "nahin"])

    static func isRefusal(_ sentence: String, requestIsQuestion: Bool = true) -> Bool {
        guard wordCount(sentence) <= 9 else { return false }
        if HindiText.isRefusal(sentence) { return true }
        let key = MeetingAnalysisReducer.clauseKey(sentence)
        // A bare "No." only declines a question; after a statement it means something else.
        if requestIsQuestion, exactRefusals.contains(key.trimmingCharacters(in: .whitespaces)) { return true }
        return refusalPhrases.contains { key.contains(" " + $0 + " ") }
    }

    private static let acceptancePhrases: [String] = [
        "sure", "okay", "ok", "yes", "yeah", "yep", "will do", "i'll do it", "i will do it", "i'll take care",
        "on it", "done", "got it", "no problem", "absolutely", "definitely", "of course", "i'll handle it",
        "haan", "haanji", "han", "ji", "theek hai", "thik hai", "ho jayega", "kar dunga", "kar dungi",
        "kar deta hoon", "bhej dunga", "bhej dungi", "bana dunga", "bana dungi", "kar lunga", "kar lungi",
        "main kar dunga", "mai kar dunga", "bilkul",
        "\u{0939}\u{093E}\u{0901}", "\u{0939}\u{093E}\u{0902}", "\u{0920}\u{0940}\u{0915} \u{0939}\u{0948}",
        "\u{0915}\u{0930} \u{0926}\u{0942}\u{0902}\u{0917}\u{093E}", "\u{0915}\u{0930} \u{0926}\u{0942}\u{0901}\u{0917}\u{093E}",
        "\u{0939}\u{094B} \u{091C}\u{093E}\u{090F}\u{0917}\u{093E}"
    ]

    static func isAcceptance(_ sentence: String) -> Bool {
        guard wordCount(sentence) <= 8, !isRefusal(sentence, requestIsQuestion: true),
              !MeetingAnalysisReducer.isNonCommittalSentence(sentence) else { return false }
        if HindiText.hasAcceptanceCue(sentence) { return true }
        let key = MeetingAnalysisReducer.clauseKey(sentence)
        return acceptancePhrases.contains { key.contains(" " + $0 + " ") }
    }

    // MARK: - Sentence normalisation

    private static func replace(_ pattern: String, in text: String, with template: String = "",
                                options: NSRegularExpression.Options = [.caseInsensitive]) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    /// Strips conversational lead-ins ("Okay, so", "Hi,", "Action item:") and end punctuation.
    static func core(_ sentence: String) -> String {
        var text = sentence.replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: ".!?\u{0964}\u{2026}\"\u{201C}\u{201D} "))
        text = replace(#"^(?:action\s+items?|action|todo|to-do|task|follow[- ]?up)\s*[:\-]\s*"#, in: text)
        text = replace(#"^(?:(?:okay|ok|so|and|also|alright|right|then|well|now|yeah|yes|sure|great|cool|perfect|actually|haan|haanji|achha|accha|toh|chalo|ji|hi|hey|hello|namaste)[,]?\s+)+"#, in: text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Names

    private static let nameStopwords: Set<String> = Set<String>([
        "i", "i'll", "i'm", "i've", "we'll", "we're", "you'll", "it's", "that's", "there's", "we", "you", "he", "she", "it", "they", "me", "us", "them", "this", "that", "these", "those", "there",
        "here", "the", "a", "an", "and", "or", "but", "so", "also", "then", "now", "well", "okay", "ok", "yes", "no",
        "yeah", "yep", "nope", "sure", "thanks", "thank", "hello", "hi", "hey", "please", "sorry", "right", "great",
        "cool", "fine", "good", "perfect", "alright", "actually", "basically", "finally", "next", "first", "last",
        "can", "could", "would", "will", "should", "shall", "may", "might", "must", "do", "does", "did", "is", "are",
        "was", "were", "has", "have", "had", "be", "let", "lets", "let's", "if", "when", "what", "who", "why", "how",
        "where", "which", "while", "after", "before", "once", "since", "because", "maybe", "perhaps", "someone",
        "anyone", "everyone", "everybody", "somebody", "nobody", "all", "both", "each", "team", "speaker", "speakers",
        "guys", "folks", "sir", "madam", "mam", "ma'am", "boss", "bro", "brother", "dude",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "today", "tomorrow", "tonight",
        "yesterday", "january", "february", "march", "april", "june", "july", "august", "september", "october",
        "november", "december",
        "agenda", "estimate", "estimates", "deck", "budget", "report", "reports", "notes", "note", "minutes",
        "meeting", "meetings", "call", "calls", "email", "emails", "mail", "invoice", "invoices", "contract",
        "contracts", "proposal", "proposals", "document", "documents", "doc", "docs", "file", "files", "sheet",
        "spreadsheet", "slides", "slide", "presentation", "demo", "design", "designs", "plan", "plans", "task",
        "tasks", "ticket", "tickets", "issue", "issues", "bug", "bugs", "feature", "features", "release", "launch",
        "vendor", "vendors", "client", "clients", "customer", "customers", "room", "venue", "schedule", "timeline",
        "quote", "quotes", "payment", "payments", "order", "orders", "update", "updates", "review", "draft", "list",
        "summary", "details", "data", "numbers", "figures", "pricing", "price", "cost", "costs", "sales", "marketing",
        "finance", "legal", "hr", "it", "product", "project", "projects", "sprint", "roadmap", "stage", "phase",
        "approval", "access", "code", "build", "tests", "test", "feedback", "follow", "followup", "reminder",
        "haan", "haanji", "han", "nahi", "nahin", "accha", "achha", "theek", "thik", "kal", "aaj", "parso", "abhi",
        "phir", "fir", "toh", "to", "kya", "kaun", "kab", "kyun", "sab", "koi", "hum", "ham", "main", "mai", "mein",
        "tum", "tu", "aap", "woh", "wo", "vo", "yeh", "ye", "ji", "bhai", "chalo", "bas", "bilkul", "done", "wait",
        "hamara", "humara", "log", "bhi", "aur", "lekin", "par", "magar", "agar", "jab", "tab", "ab",
        "tay", "final", "decide", "hua", "hui", "gaya", "hai", "pehle", "baad", "ek", "sirf", "dekho", "suno", "arre", "matlab", "jaise", "kuch",
        "\u{0939}\u{093E}\u{0901}", "\u{0939}\u{093E}\u{0902}", "\u{091C}\u{0940}", "\u{0920}\u{0940}\u{0915}",
        "\u{0905}\u{091A}\u{094D}\u{091B}\u{093E}", "\u{0938}\u{0941}\u{0928}\u{094B}", "\u{092F}\u{0939}",
        "\u{0935}\u{0939}", "\u{0939}\u{092E}", "\u{092E}\u{0948}\u{0902}", "\u{0924}\u{0941}\u{092E}",
        "\u{0906}\u{092A}", "\u{0915}\u{0932}", "\u{0906}\u{091C}", "\u{092A}\u{0930}\u{0938}\u{094B}\u{0902}",
        "\u{0938}\u{092C}", "\u{0915}\u{094B}\u{0908}", "\u{091F}\u{0940}\u{092E}", "\u{0913}\u{0915}\u{0947}",
        "\u{0928}\u{0939}\u{0940}\u{0902}", "\u{0915}\u{094D}\u{092F}\u{093E}", "\u{0914}\u{0930}",
        "\u{090F}\u{091C}\u{0947}\u{0902}\u{0921}\u{093E}", "\u{0930}\u{093F}\u{092A}\u{094B}\u{0930}\u{094D}\u{091F}",
        "\u{092C}\u{091C}\u{091F}", "\u{092E}\u{0940}\u{091F}\u{093F}\u{0902}\u{0917}", "\u{0921}\u{0947}\u{0915}"
    ])

    private static func isDevanagari(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x0900 && scalar.value <= 0x097F
    }

    private static func isGenericSpeakerLabel(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("speaker ") || lower == "speaker" || lower.hasPrefix("unknown")
    }

    /// Returns the display name for a token that is used as a person, or nil when
    /// the token is not demonstrably a name. Never invents a name.
    static func resolveOwner(_ raw: String, context: ExtractionContext) -> String? {
        let cleaned = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        guard cleaned.count >= 2, !isGenericSpeakerLabel(cleaned) else { return nil }
        let key = cleaned.lowercased()
        let people = context.participants.filter { !isGenericSpeakerLabel($0) }
        if let exact = people.first(where: { $0.lowercased() == key }) { return exact }
        let firstNameMatches = people.filter {
            ($0.split(separator: " ").first.map { String($0).lowercased() } ?? "") == key
        }
        if firstNameMatches.count == 1 { return firstNameMatches[0] }
        for word in cleaned.split(separator: " ") where nameStopwords.contains(String(word).lowercased()) { return nil }
        guard let first = cleaned.unicodeScalars.first else { return nil }
        if isDevanagari(first) { return HindiText.isKnownWord(cleaned) ? nil : cleaned }
        guard CharacterSet.uppercaseLetters.contains(first) else { return nil }
        return cleaned
    }

    // MARK: - Verbs

    private static let actionVerbs: Set<String> = Set<String>([
        "send", "share", "prepare", "create", "update", "review", "approve", "confirm", "schedule", "contact",
        "check", "provide", "complete", "submit", "draft", "follow", "call", "email", "deliver", "finalize",
        "finalise", "investigate", "resolve", "book", "organize", "organise", "arrange", "handle", "make", "write",
        "set", "fix", "order", "buy", "bring", "collect", "compile", "circulate", "post", "upload", "ping", "remind",
        "coordinate", "reach", "talk", "plan", "document", "test", "ship", "publish", "forward", "setup", "prep",
        "get", "find", "build", "design", "run", "pay", "file", "raise", "take", "finish", "work", "look", "reply",
        "respond", "sign", "cancel", "reschedule", "move", "summarize", "summarise", "gather", "track", "clean",
        "add", "remove", "verify", "validate", "prioritize", "assign", "escalate", "negotiate", "present", "demo",
        "record", "print", "dispatch", "install", "register", "apply", "renew", "notify", "inform", "tell", "ask",
        "message", "text", "research", "own", "lead", "drive", "setup", "sync", "walk"
    ])
    private static let leadingAdverbs: Set<String> = Set<String>([
        "also", "then", "just", "please", "kindly", "first", "quickly", "definitely", "personally", "still", "now",
        "soon", "again", "immediately", "go", "ahead"
    ])

    static func startsWithVerb(_ action: String) -> Bool {
        for word in action.split(whereSeparator: { $0.isWhitespace }) {
            let lower = String(word).lowercased().trimmingCharacters(in: .punctuationCharacters)
            if leadingAdverbs.contains(lower) { continue }
            return actionVerbs.contains(lower)
        }
        return false
    }

    static func isVerbWord(_ word: String) -> Bool {
        actionVerbs.contains(word.lowercased().trimmingCharacters(in: .punctuationCharacters))
    }

    // MARK: - Deadlines

    private static let deadlinePattern: String = {
        let days = "monday|tuesday|wednesday|thursday|friday|saturday|sunday"
        let hdays = "somwar|somvar|mangalwar|mangalvar|budhwar|budhvar|guruwar|guruvar|shukrawar|shukravar|shanivar|shaniwar|ravivar|raviwar"
        let months = "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"
        let alternatives: [String] = [
            #"by\s+(?:the\s+)?end\s+of\s+(?:the\s+)?(?:day|week|month|today)"#,
            #"by\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)"#,
            #"by\s+(?:the\s+)?\d{1,2}(?:st|nd|rd|th)(?:\s+(?:of\s+)?(?:\#(months)))?"#,
            #"by\s+(?:the\s+)?\d{1,2}\s+(?:of\s+)?(?:\#(months))"#,
            #"by\s+(?:eod|eow|cob|noon|tomorrow|tonight|today|next\s+(?:week|month)|(?:next\s+)?(?:\#(days)))"#,
            #"(?:on|for)\s+(?:\#(days))"#,
            #"(?:next|this|coming)\s+(?:week|month|weekend|\#(days))"#,
            #"this\s+(?:afternoon|evening|morning)"#,
            #"tomorrow(?:\s+(?:morning|afternoon|evening|night))?"#,
            #"tonight|today|eod|eow|cob"#,
            #"end\s+of\s+(?:the\s+)?(?:day|week|month)"#,
            #"(?:in|within)\s+(?:a|an|\d+|one|two|three|four|five|a\s+couple\s+of|a\s+few)\s+(?:minutes?|hours?|days?|weeks?|months?)"#,
            #"before\s+(?:the\s+)?(?:meeting|weekend|\#(days))"#,
            #"(?:kal|aaj|parso|shaam|subah|raat)\s+tak"#,
            #"(?:agle|agli|is|iss)\s+(?:hafte|haftay|mahine|saal)(?:\s+tak)?"#,
            #"agle\s+(?:\#(hdays)|\#(days))(?:\s+tak)?"#,
            #"(?:\#(hdays)|\#(days))\s+tak"#,
            #"kal|aaj|parso"#,
            "\u{0915}\u{0932}\\s+\u{0924}\u{0915}|\u{0906}\u{091C}\\s+\u{0924}\u{0915}|\u{092A}\u{0930}\u{0938}\u{094B}\u{0902}\\s+\u{0924}\u{0915}|\u{0936}\u{093E}\u{092E}\\s+\u{0924}\u{0915}|\u{0938}\u{0941}\u{092C}\u{0939}\\s+\u{0924}\u{0915}",
            "\u{0905}\u{0917}\u{0932}\u{0947}\\s+\u{0939}\u{092B}\\u093C?\\u094D\u{0924}\u{0947}(?:\\s+\u{0924}\u{0915})?",
            "\u{0915}\u{0932}|\u{0906}\u{091C}|\u{092A}\u{0930}\u{0938}\u{094B}\u{0902}"
        ]
        return #"(?i)(?<![\p{L}\p{M}])(?:"# + alternatives.joined(separator: "|") + #")(?![\p{L}\p{M}'])"#
    }()

    /// Separates the first deadline phrase (verbatim) from the rest of a text.
    static func splitDeadline(_ text: String) -> (text: String, deadline: String?) {
        guard let regex = try? NSRegularExpression(pattern: deadlinePattern) else { return (text, nil) }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let found = Range(match.range, in: text) else { return (text, nil) }
        var rest = text
        rest.removeSubrange(found)
        return (rest, String(text[found]))
    }

    // MARK: - English and mixed request forms

    private enum RuleKind { case ownerAction, actionOwner, ownerObject, objectOwner, selfAction }
    private struct Rule { let regex: NSRegularExpression; let kind: RuleKind }

    private static func englishRules() -> [Rule] {
        let name: String = #"([\p{Lu}][\p{L}'\u2019\-]{1,24}|[\u0900-\u0963\u0966-\u097F]{2,24})"#
        let nameTwo: String = #"([\p{Lu}][\p{L}'\u2019\-]{1,24}(?:\s+[\p{Lu}][\p{L}'\u2019\-]{1,24})?|[\u0900-\u0963\u0966-\u097F]{2,24})"#
        let asks: String = #"(?i:(?:can|could|would|will)\s+you\s+(?:please\s+|kindly\s+)?)"#
        let willForms: String = #"(?i:\s+(?:needs\s+to|has\s+to|have\s+to|must|is\s+supposed\s+to|will|is\s+going\s+to|are\s+going\s+to|agreed\s+to|has\s+agreed\s+to|volunteered\s+to|offered\s+to|promised\s+to|shall)|'ll)"#
        var specs: [(String, RuleKind)] = []
        func add(_ parts: [String], _ kind: RuleKind) { specs.append((parts.joined(), kind)) }
        // "Pawan, can you prepare the agenda?" / "Pawan, please ..." / "Rahul, you'll handle ..."
        add(["^", name, ",?\\s+", asks, "(.+)$"], .ownerAction)
        add(["^", name, #",?\s+(?i:(?:please|kindly)\s+)(.+)$"#], .ownerAction)
        add(["^", name, #",?\s+(?i:you(?:'ll|\s+will|\s+need\s+to|\s+needs\s+to|\s+have\s+to|\s+must|\s+should)\s+)(.+)$"#], .ownerAction)
        add(["^", name, #",?\s+(?i:(?:i|we)\s+(?:need|want|would\s+like|'d\s+like)\s+you\s+to\s+)(.+)$"#], .ownerAction)
        // "Could you send the deck, Maya?" / "Please send the deck, Maya"
        add(["^", asks, #"(.+?),\s*"#, name, "$"], .actionOwner)
        add([#"^(?i:(?:please|kindly)\s+)(.+?),\s*"#, name, "$"], .actionOwner)
        // "Let's have Neha draft the budget"
        add([#"^(?i:let(?:'s|s|\s+us)\s+(?:have|get)\s+)"#, name, #"\s+(?i:to\s+)?(.+)$"#], .ownerAction)
        // "Assign the agenda to Pawan"
        add([#"^(?i:(?:please\s+)?(?:let's\s+|lets\s+)?assign\s+)(.+?)\s+(?i:to)\s+"#, name, "$"], .objectOwner)
        // "Pawan will be responsible for the agenda"
        add(["^", name, #"\s+(?i:(?:will\s+be|is|'ll\s+be|shall\s+be|is\s+going\s+to\s+be|to\s+be)\s+(?:responsible|in\s+charge|the\s+owner)\s+(?:for|of)\s+)(.+)$"#], .ownerObject)
        // "I'll ask Pawan to book the room" / "I need Pawan to ..." / "Ask Pawan to ..."
        add([#"^(?i:(?:i'll|i\s+will|i'm\s+going\s+to|let\s+me|we'll|we\s+will)\s+(?:ask|get|have|tell|request|remind)\s+)"#, name, #"\s+(?i:to\s+)?(.+)$"#], .ownerAction)
        add([#"^(?i:(?:i|we)\s+(?:need|want|would\s+like|'d\s+like)\s+)"#, name, #"\s+(?i:to\s+)(.+)$"#], .ownerAction)
        add([#"^(?i:(?:please\s+)?(?:ask|get|tell|remind)\s+)"#, name, #"\s+(?i:to\s+)(.+)$"#], .ownerAction)
        // "Pawan to share the notes"
        add(["^", name, #"\s+(?i:to)\s+(.+)$"#], .ownerAction)
        // "Rahul will send the estimate tomorrow"
        add(["^", nameTwo, willForms, #"\s+(.+)$"#], .ownerAction)
        // First person: owner only when the speaker label maps to a named person.
        add([#"^(?i:i'll|i\s+will|i'm\s+going\s+to|i\s+am\s+going\s+to|let\s+me)\s+(.+)$"#], .selfAction)
        // "Maya, send the deck by Friday"
        add(["^", name, #",\s+(.+)$"#], .ownerAction)
        var rules: [Rule] = []
        for spec in specs {
            if let regex = try? NSRegularExpression(pattern: spec.0) { rules.append(Rule(regex: regex, kind: spec.1)) }
        }
        return rules
    }

    private static func captures(_ regex: NSRegularExpression, in text: String) -> [String]? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        var values: [String] = []
        for index in 0..<match.numberOfRanges {
            if let found = Range(match.range(at: index), in: text) { values.append(String(text[found])) } else { values.append("") }
        }
        return values
    }

    private static let pronounObjects: Set<String> = Set<String>(["it", "that", "this", "them", "those", "these", "same", "one", "so"])

    private static func extract(_ sentence: String, turn: AnalysisTurn, rules: [Rule],
                                context: ExtractionContext) -> SuggestedTask? {
        let text = core(sentence)
        guard !text.isEmpty else { return nil }
        let evidence = [SourceEvidence(turnID: turn.id, quote: sentence)]
        for rule in rules {
            guard let groups = captures(rule.regex, in: text), groups.count >= 3 || rule.kind == .selfAction else { continue }
            switch rule.kind {
            case .ownerAction, .actionOwner:
                let ownerRaw = rule.kind == .ownerAction ? groups[1] : groups[2]
                let action = rule.kind == .ownerAction ? groups[2] : groups[1]
                guard let owner = resolveOwner(ownerRaw, context: context), startsWithVerb(action),
                      let task = makeTask(action: action, object: nil, owner: owner, evidence: evidence) else { continue }
                return task
            case .ownerObject, .objectOwner:
                let ownerRaw = rule.kind == .ownerObject ? groups[1] : groups[2]
                let object = rule.kind == .ownerObject ? groups[2] : groups[1]
                guard let owner = resolveOwner(ownerRaw, context: context),
                      let task = makeTask(action: nil, object: object, owner: owner, evidence: evidence) else { continue }
                return task
            case .selfAction:
                guard groups.count >= 2, startsWithVerb(groups[1]) else { continue }
                let (rest, _) = splitDeadline(groups[1])
                let words = rest.split(whereSeparator: { $0.isWhitespace }).map { String($0).lowercased() }
                if words.dropFirst().allSatisfy({ pronounObjects.contains($0.trimmingCharacters(in: .punctuationCharacters)) }) { continue }
                let owner = turn.speaker.flatMap { context.speakerNames[$0] }
                guard let task = makeTask(action: groups[1], object: nil, owner: owner, evidence: evidence) else { continue }
                return task
            }
        }
        // A settled outcome ("tay hua, ... karenge") is a decision, not a request.
        guard !DecisionExtractor.isDecision(sentence) else { return nil }
        return hinglishTask(text, evidence: evidence, turn: turn, context: context)
    }

    private static func makeTask(action: String?, object: String?, owner: String?,
                                 evidence: [SourceEvidence]) -> SuggestedTask? {
        let source = action ?? object ?? ""
        let (withoutDeadline, deadline) = splitDeadline(source)
        var body = MeetingAnalysisReducer.polishedTask(withoutDeadline)
        if action == nil { body = body.prefix(1).lowercased() + String(body.dropFirst()) }
        body = replace(#"[,\s]+(?:please|for\s+me|for\s+us|asap|right\s+away|when\s+you\s+can)$"#, in: body)
        body = body.trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
        guard !body.isEmpty else { return nil }
        let title: String
        if action != nil {
            title = MeetingAnalysisReducer.polishedTask(body)
        } else {
            title = MeetingAnalysisReducer.polishedTask("Handle " + body)
        }
        guard MeetingAnalysisReducer.isSubstantive(title) else { return nil }
        return SuggestedTask(title: title, category: MeetingAnalysisReducer.category(for: title), owner: owner,
                             deadlineText: deadline, priority: nil, evidence: evidence)
    }

    // MARK: - Hinglish and Hindi request forms

    private enum Light { case send, create, perform, give, take }
    private enum Person { case first, second, third }
    private struct Tail { let words: [String]; let light: Light; let person: Person }

    private static let tails: [Tail] = {
        var list: [Tail] = []
        func add(_ phrases: [String], _ light: Light, _ person: Person) {
            for phrase in phrases {
                list.append(Tail(words: phrase.split(separator: " ").map(String.init), light: light, person: person))
            }
        }
        // Latin script
        add(["bhej dena", "bhej do", "bhej dijiye", "bhejna", "bhejo", "bhej de", "bhejiye"], .send, .second)
        add(["bana dena", "bana do", "bana lo", "bana lena", "banana", "banao", "bana dijiye", "bana de"], .create, .second)
        add(["kar dena", "kar do", "kar lo", "kar lena", "karna", "karo", "kar dijiye", "kar de", "kariye", "kijiye"], .perform, .second)
        add(["de dena", "de do", "dena", "de dijiye", "dedo"], .give, .second)
        add(["bhej dega", "bhej degi", "bhej denge", "bhejega", "bhejegi", "bhejenge"], .send, .third)
        add(["bana dega", "bana degi", "bana denge", "banayega", "banayegi", "banayenge", "banaega", "banaegi"], .create, .third)
        add(["kar dega", "kar degi", "kar denge", "karega", "karegi", "karenge", "kar lega", "kar legi", "karwayega", "karwayegi"], .perform, .third)
        add(["dega", "degi", "denge"], .give, .third)
        add(["lega", "legi", "lenge", "layega", "layegi"], .take, .third)
        add(["bhej dunga", "bhej dungi", "bhejunga", "bhejungi", "bhej doonga"], .send, .first)
        add(["bana dunga", "bana dungi", "banaunga", "banaungi", "bana doonga"], .create, .first)
        add(["kar dunga", "kar dungi", "karunga", "karungi", "kar lunga", "kar lungi", "kar doonga"], .perform, .first)
        add(["dunga", "dungi", "doonga"], .give, .first)
        // Devanagari
        add(["\u{092D}\u{0947}\u{091C} \u{0926}\u{0947}\u{0928}\u{093E}", "\u{092D}\u{0947}\u{091C} \u{0926}\u{094B}",
             "\u{092D}\u{0947}\u{091C}\u{0928}\u{093E}", "\u{092D}\u{0947}\u{091C}\u{094B}"], .send, .second)
        add(["\u{092C}\u{0928}\u{093E} \u{0926}\u{0947}\u{0928}\u{093E}", "\u{092C}\u{0928}\u{093E} \u{0926}\u{094B}",
             "\u{092C}\u{0928}\u{093E} \u{0932}\u{094B}", "\u{092C}\u{0928}\u{093E}\u{0928}\u{093E}",
             "\u{092C}\u{0928}\u{093E}\u{0913}"], .create, .second)
        add(["\u{0915}\u{0930} \u{0926}\u{0947}\u{0928}\u{093E}", "\u{0915}\u{0930} \u{0926}\u{094B}",
             "\u{0915}\u{0930} \u{0932}\u{094B}", "\u{0915}\u{0930}\u{0928}\u{093E}", "\u{0915}\u{0930}\u{094B}"], .perform, .second)
        add(["\u{092D}\u{0947}\u{091C}\u{0947}\u{0917}\u{093E}", "\u{092D}\u{0947}\u{091C}\u{0947}\u{0917}\u{0940}",
             "\u{092D}\u{0947}\u{091C}\u{0947}\u{0902}\u{0917}\u{0947}", "\u{092D}\u{0947}\u{091C} \u{0926}\u{0947}\u{0917}\u{093E}",
             "\u{092D}\u{0947}\u{091C} \u{0926}\u{0947}\u{0917}\u{0940}"], .send, .third)
        add(["\u{092C}\u{0928}\u{093E}\u{090F}\u{0917}\u{093E}", "\u{092C}\u{0928}\u{093E}\u{090F}\u{0917}\u{0940}",
             "\u{092C}\u{0928}\u{093E}\u{090F}\u{0902}\u{0917}\u{0947}", "\u{092C}\u{0928}\u{093E} \u{0926}\u{0947}\u{0917}\u{093E}",
             "\u{092C}\u{0928}\u{093E} \u{0926}\u{0947}\u{0917}\u{0940}"], .create, .third)
        add(["\u{0915}\u{0930}\u{0947}\u{0917}\u{093E}", "\u{0915}\u{0930}\u{0947}\u{0917}\u{0940}",
             "\u{0915}\u{0930}\u{0947}\u{0902}\u{0917}\u{0947}", "\u{0915}\u{0930} \u{0926}\u{0947}\u{0917}\u{093E}",
             "\u{0915}\u{0930} \u{0926}\u{0947}\u{0917}\u{0940}"], .perform, .third)
        add(["\u{092D}\u{0947}\u{091C} \u{0926}\u{0942}\u{0902}\u{0917}\u{093E}", "\u{092D}\u{0947}\u{091C} \u{0926}\u{0942}\u{0902}\u{0917}\u{0940}"], .send, .first)
        add(["\u{092C}\u{0928}\u{093E} \u{0926}\u{0942}\u{0902}\u{0917}\u{093E}", "\u{092C}\u{0928}\u{093E} \u{0926}\u{0942}\u{0902}\u{0917}\u{0940}"], .create, .first)
        add(["\u{0915}\u{0930} \u{0926}\u{0942}\u{0902}\u{0917}\u{093E}", "\u{0915}\u{0930} \u{0926}\u{0942}\u{0901}\u{0917}\u{093E}",
             "\u{0915}\u{0930} \u{0926}\u{0942}\u{0902}\u{0917}\u{0940}", "\u{0915}\u{0930}\u{0942}\u{0902}\u{0917}\u{093E}",
             "\u{0915}\u{0930}\u{0942}\u{0902}\u{0917}\u{0940}"], .perform, .first)
        return list.sorted { $0.words.count > $1.words.count }
    }()

    private static let tailFillers: Set<String> = Set<String>([
        "hai", "hain", "hoga", "hogi", "honge", "please", "plz", "pls", "na", "ji", "yaar", "bhai", "bro", "zaroor",
        "\u{0939}\u{0948}", "\u{0939}\u{0948}\u{0902}", "\u{0939}\u{094B}\u{0917}\u{093E}", "\u{091C}\u{0940}"
    ])
    private static let questionWords: Set<String> = Set<String>([
        "kya", "kaun", "kab", "kyun", "kyu", "kaise", "kitna", "kahan",
        "\u{0915}\u{094D}\u{092F}\u{093E}", "\u{0915}\u{094C}\u{0928}", "\u{0915}\u{092C}", "\u{0915}\u{094D}\u{092F}\u{094B}\u{0902}"
    ])
    private static let firstPronouns: Set<String> = Set<String>(["main", "mai", "mein", "maine", "hum", "ham", "\u{092E}\u{0948}\u{0902}", "\u{0939}\u{092E}"])
    private static let otherPronouns: Set<String> = Set<String>([
        "tum", "aap", "tu", "tumhe", "woh", "wo", "vo", "voh", "yeh", "ye", "\u{0924}\u{0941}\u{092E}", "\u{0906}\u{092A}",
        "\u{0935}\u{0939}", "\u{0935}\u{094B}", "\u{092F}\u{0939}"
    ])
    private static let spokenFillers: Set<String> = Set<String>([
        "toh", "to", "please", "plz", "zara", "ji", "yaar", "bhai", "aur", "phir", "fir", "bas", "jaldi", "haan", "haanji",
        "han", "ok", "okay", "theek", "thik", "accha", "achha", "sure", "done", "bilkul",
        "\u{0924}\u{094B}", "\u{092C}\u{0938}", "\u{0939}\u{093E}\u{0901}", "\u{0939}\u{093E}\u{0902}", "\u{091C}\u{0940}",
        "\u{0920}\u{0940}\u{0915}", "\u{0905}\u{091A}\u{094D}\u{091B}\u{093E}"
    ])
    /// Words that mark a descriptive sentence ("tay hua", "ho gaya"), not a request.
    private static let descriptiveWords: Set<String> = Set<String>([
        "hua", "hui", "hue", "gaya", "gayi", "gaye", "hai", "hain", "tha", "thi", "the", "raha", "rahi", "rahe",
        "kiya", "liya", "diya", "hoon", "ho"
    ])
    private static let koWords: Set<String> = Set<String>(["ko", "\u{0915}\u{094B}"])

    private static func hinglishTask(_ text: String, evidence: [SourceEvidence], turn: AnalysisTurn,
                                     context: ExtractionContext) -> SuggestedTask? {
        // The deadline may sit anywhere ("kal tak ...", "... bhejna hai agle hafte tak").
        let (withoutDeadline, deadline) = splitDeadline(text)
        let tokens = withoutDeadline.split(whereSeparator: { $0.isWhitespace }).map {
            String($0).trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        }.filter { !$0.isEmpty }
        let lowered = tokens.map { $0.lowercased() }
        guard !lowered.contains(where: { questionWords.contains($0) }) else { return nil }
        var end = lowered.count
        while end > 0, tailFillers.contains(lowered[end - 1]) { end -= 1 }
        guard end > 0 else { return nil }
        var matched: Tail?
        var start = end
        for tail in tails where end >= tail.words.count {
            let from = end - tail.words.count
            if Array(lowered[from..<end]) == tail.words { matched = tail; start = from; break }
        }
        guard let tail = matched, start > 0 else { return nil }
        var words = Array(tokens[0..<start])
        var owner: String?
        switch tail.person {
        case .first:
            owner = turn.speaker.flatMap { context.speakerNames[$0] }
            words.removeAll { firstPronouns.contains($0.lowercased()) }
        case .second:
            if let index = words.firstIndex(where: { koWords.contains($0.lowercased()) }), index >= 1,
               let name = resolveOwner(words[index - 1], context: context) {
                owner = name
                words.removeSubrange((index - 1)...index)
            } else if let first = words.first, let name = resolveOwner(first, context: context) {
                owner = name
                words.removeFirst()
            }
            guard owner != nil else { return nil }
        case .third:
            if let first = words.first, let name = resolveOwner(first, context: context) {
                owner = name
                words.removeFirst()
            } else if words.count >= 2, let last = words.last, let name = resolveOwner(last, context: context) {
                owner = name
                words.removeLast()
            } else if words.contains(where: { koWords.contains($0.lowercased()) }) {
                return nil
            }
        }
        words.removeAll { otherPronouns.contains($0.lowercased()) || spokenFillers.contains($0.lowercased()) }
        guard !words.isEmpty, !words.contains(where: { descriptiveWords.contains($0.lowercased()) }) else { return nil }
        if let first = words.first, nameStopwords.contains(first.lowercased()) { words[0] = first.lowercased() }
        let title: String
        switch tail.light {
        case .send: title = "Send " + words.joined(separator: " ")
        case .create: title = "Create " + words.joined(separator: " ")
        case .give: title = "Provide " + words.joined(separator: " ")
        case .take: title = "Handle " + words.joined(separator: " ")
        case .perform:
            if words.count >= 2, let last = words.last, isVerbWord(last) {
                let verb = last.prefix(1).uppercased() + last.dropFirst().lowercased()
                title = verb + " " + words.dropLast().joined(separator: " ")
            } else if words.count == 1, isVerbWord(words[0]) {
                return nil
            } else if owner != nil {
                title = "Handle " + words.joined(separator: " ")
            } else {
                return nil
            }
        }
        let polished = MeetingAnalysisReducer.polishedTask(title)
        guard MeetingAnalysisReducer.isSubstantive(polished) else { return nil }
        return SuggestedTask(title: polished, category: MeetingAnalysisReducer.category(for: polished), owner: owner,
                             deadlineText: deadline, priority: nil, evidence: evidence)
    }
}

/// Grounded decision detection. A sentence qualifies only when it states a
/// settled outcome; questions, conditionals, negations and undecided phrasing
/// never qualify (those become open issues instead).
enum DecisionExtractor {
    private static let markers: [String] = [
        "let's go with", "lets go with", "we'll go with", "we will go with", "we're going with", "we are going with",
        "i'm going with", "going with", "go ahead with", "going ahead with", "we'll go ahead", "we will go ahead",
        "we decided", "we've decided", "we have decided", "i've decided", "it's decided", "it is decided", "its decided",
        "it's been decided", "has been decided", "is decided", "decided to", "decided on", "final decision",
        "is finalized", "is finalised", "was finalized", "was finalised", "we finalized", "we finalised",
        "have finalized", "have finalised", "has been finalized", "has been finalised", "finally decided",
        "finally agreed", "it's final", "it is final", "is final", "are final",
        "we agreed", "we all agreed", "everyone agreed", "all agreed", "agreed to", "agreed on", "agreed that",
        "is approved", "was approved", "has been approved", "have been approved", "are approved", "were approved",
        "got approved", "we approved", "have approved", "has approved", "officially approved", "finally approved",
        "approved by", "we will launch on", "we'll launch on", "launch is on", "confirmed that", "it's confirmed",
        "is confirmed", "has been confirmed", "was confirmed",
        "we deferred", "was rejected", "is rejected", "decision is", "the decision was",
        "final hai", "final ho gaya", "final ho gaya hai", "tay hua", "tay ho gaya", "tay kiya", "tay kar liya",
        "decide ho gaya", "decide kar liya", "decide kiya", "yahi final", "yehi final", "finalize ho gaya",
        "approve ho gaya", "approve kar diya", "manzoor hai",
        "\u{092B}\u{093E}\u{0907}\u{0928}\u{0932} \u{0939}\u{0948}", "\u{0924}\u{092F} \u{0939}\u{0941}\u{0906}",
        "\u{0924}\u{092F} \u{0939}\u{094B} \u{0917}\u{092F}\u{093E}", "\u{092F}\u{0939}\u{0940} \u{092B}\u{093E}\u{0907}\u{0928}\u{0932}",
        "\u{0921}\u{093F}\u{0938}\u{093E}\u{0907}\u{0921} \u{0939}\u{094B} \u{0917}\u{092F}\u{093E}",
        "\u{092B}\u{093E}\u{0907}\u{0928}\u{0932} \u{0939}\u{094B} \u{0917}\u{092F}\u{093E}"
    ]
    private static let chaloFollowers: [String] = [
        "karte hain", "karte hai", "karenge", "kar lete hain", "kar lete hai", "rakhte hain", "rakhte hai",
        "\u{0915}\u{0930}\u{0924}\u{0947} \u{0939}\u{0948}\u{0902}", "\u{0915}\u{0930}\u{0924}\u{0947} \u{0939}\u{0948}"
    ]
    private static let chaloWords: [String] = ["chalo", "\u{091A}\u{0932}\u{094B}"]
    private static let negations: [String] = [
        "not", "never", "nahi", "nahin", "cannot", "can't", "won't", "haven't", "hasn't", "didn't", "isn't", "wasn't",
        "weren't", "aren't", "nope", "\u{0928}\u{0939}\u{0940}\u{0902}", "\u{0928}\u{0939}\u{0940}"
    ]
    private static let allowedNegatedDecisions: [String] = [
        "decided not to", "agreed not to", "decided against", "agreed against", "decided we will not",
        "decided we won't"
    ]
    private static let exclusions: [String] = [
        "if", "unless", "agar", "should", "could", "would", "can we", "depends", "pending", "awaiting",
        "to be approved", "to be finalized", "to be finalised", "be finalized", "be finalised", "to finalize",
        "need to", "needs to", "yet to", "kya", "for approval", "needs approval", "need approval",
        "\u{0905}\u{0917}\u{0930}", "\u{0915}\u{094D}\u{092F}\u{093E}"
    ]

    static func isDecision(_ sentence: String) -> Bool {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasSuffix("?"), !trimmed.hasSuffix("\u{FF1F}") else { return false }
        guard !MeetingAnalysisReducer.isUndecidedSentence(sentence) else { return false }
        let key = MeetingAnalysisReducer.clauseKey(sentence)
        func has(_ phrase: String) -> Bool { key.contains(" " + phrase + " ") }
        if exclusions.contains(where: has) { return false }
        let allowedNegation = allowedNegatedDecisions.contains(where: has)
        if !allowedNegation, negations.contains(where: has) { return false }
        if markers.contains(where: has) { return true }
        if chaloWords.contains(where: has) && chaloFollowers.contains(where: has) {
            // A Devanagari "chalo ... karte hain" opens or paces a meeting unless it names a date or stresses the choice.
            if HindiText.containsDevanagari(sentence) { return HindiMeetingExtractor.settlesChoice(sentence) }
            return true
        }
        return false
    }

    /// Text used for a minute: the sentence without conversational lead-ins.
    static func minuteText(_ sentence: String) -> String {
        let cleaned = ActionExtractor.core(sentence)
        return cleaned.isEmpty ? sentence : cleaned
    }
}
