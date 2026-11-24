import Foundation

// MARK: - Commands

/// How often a meeting that Vidur schedules repeats.
public enum VidurRepeat: String, Sendable, Equatable {
    case daily, weekly, biweekly, monthly

    public var title: String {
        switch self {
        case .daily: return "every day"
        case .weekly: return "every week"
        case .biweekly: return "every 2 weeks"
        case .monthly: return "every month"
        }
    }
}

/// A meeting Vidur understood from a sentence such as "schedule a design review tomorrow at 4 with Maya".
public struct VidurScheduleDraft: Sendable, Equatable {
    public var title: String
    public var start: Date
    public var durationMinutes: Int
    public var people: [String]
    public var repeatRule: VidurRepeat?
    /// True when the user gave no time and Vidur picked one, so the card should say so.
    public var timeAssumed: Bool

    public init(title: String, start: Date, durationMinutes: Int = 30, people: [String] = [],
                repeatRule: VidurRepeat? = nil, timeAssumed: Bool = false) {
        self.title = title
        self.start = start
        self.durationMinutes = durationMinutes
        self.people = people
        self.repeatRule = repeatRule
        self.timeAssumed = timeAssumed
    }

    public var end: Date { start.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
}

/// An action item Vidur understood from "remind Pawan to send the deck by Friday".
public struct VidurActionDraft: Sendable, Equatable {
    public var title: String
    /// Nil means the user themself.
    public var assignee: String?
    public var due: Date?

    public init(title: String, assignee: String? = nil, due: Date? = nil) {
        self.title = title
        self.assignee = assignee
        self.due = due
    }
}

/// Screens Vidur can open.
public enum VidurScreen: String, Sendable, Equatable {
    case home, actions, search, settings

    public var title: String {
        switch self {
        case .home: return "Meetings"
        case .actions: return "Actions"
        case .search: return "Search"
        case .settings: return "Settings"
        }
    }
}

public enum VidurCommand: Sendable, Equatable {
    case scheduleMeeting(VidurScheduleDraft)
    case addAction(VidurActionDraft)
    /// `query` words name the action. They are matched against open actions.
    case completeAction(query: String)
    /// An empty `query` means the meeting Vidur was opened from (or the last one with `preferLast`).
    case openMeeting(query: String, preferLast: Bool)
    case startRecording
    case setImportant(query: String, preferLast: Bool, important: Bool)
    case openScreen(VidurScreen)
}

public enum VidurCommandOutcome: Sendable, Equatable {
    case command(VidurCommand)
    /// Looks like a request, but Vidur cannot do it (or needs more detail). The text is the reply.
    case reply(String)
    case none
}

public enum VidurCapabilities {
    public static let summary = "I can schedule meetings, add and finish actions, open a meeting, start a recording and star a meeting."

    public static func cannot(_ verb: String) -> String {
        "I can\u{2019}t \(verb) things yet, so I won\u{2019}t pretend to. " + summary
            + " For this one, open the meeting and use its menu."
    }
}

// MARK: - Parser

/// Turns English and Hinglish requests into commands. Pure text parsing, no model.
/// Questions ("what did we decide?") are never commands.
public enum VidurCommandParser {
    public static func parse(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> VidurCommandOutcome {
        var text = VidurRx.tidy(raw)
        guard !text.isEmpty, text.count <= 300 else { return .none }
        text = stripFiller(text)
        guard !text.isEmpty else { return .none }
        if VidurRx.matches(questionStart, text) { return .none }

        if isStartRecording(text) { return .command(.startRecording) }
        if let query = completeQuery(text) { return .command(.completeAction(query: query)) }
        if let important = importantRequest(text) {
            return .command(.setImportant(query: important.query, preferLast: important.preferLast,
                                          important: important.important))
        }
        if let open = openRequest(text) { return .command(open) }
        if isSchedule(text) {
            if let draft = scheduleDraft(text, now: now, calendar: calendar) {
                return .command(.scheduleMeeting(draft))
            }
        }
        if let action = actionRequest(text, now: now, calendar: calendar) { return action }
        if let unsupported = VidurRx.captures(unsupportedVerbs, in: text) {
            return .reply(VidurCapabilities.cannot(unsupported[1].lowercased()))
        }
        return .none
    }

    // MARK: Shared patterns

    private static let questionStart = #"^(?:what|whats|what's|when|who|whom|whose|why|how|which|where|is|are|was|were|do|does|did|can i|have|has|kya|kab|kaun|kitne|kitna|kyun|kaise|kahan|tell me|show me what|give me)\b"#
    private static let unsupportedVerbs = #"^(delete|remove|erase|cancel|reschedule|postpone|move|rename|share|export|email|archive|merge|translate|print)\b"#
    private static let meetingNoun = #"\b(?:meeting|meet|call|sync|review|stand-?up|catch-?up|session|discussion|interview|demo|retro(?:spective)?|kick-?off|workshop|planning|1:1|one-on-one|huddle|brainstorm|check-?in)\b"#
    private static let actionNoun = #"\b(?:action|actions|task|tasks|to-?do|reminder)\b"#

    static func stripFiller(_ text: String) -> String {
        let pattern = #"^(?:hey|hi|hello|ok|okay|so|please|pls|kindly|vidur|can you|could you|would you|will you|can u|could u|i want to|i would like to|i'd like to|i need to|i wanna|let's|lets|let us|mujhe|zara|ek)\b[,\s]*"#
        var result = text
        for _ in 0..<4 {
            let next = VidurRx.tidy(VidurRx.replacing(pattern, in: result, with: ""))
            if next == result { break }
            result = next
        }
        return result
    }

    // MARK: Recording

    private static func isStartRecording(_ text: String) -> Bool {
        let patterns = [
            #"^(?:start|begin|launch|open)\s+(?:a\s+|an\s+|the\s+|new\s+)*(?:quick\s*)?(?:recording|record|quick\s*meet(?:ing)?)\b"#,
            #"^(?:start|begin)\s+(?:a\s+|the\s+|new\s+)*meeting\s+(?:now|right now|recording)\s*$"#,
            #"^record\b"#,
            #"^recording\s*$"#,
            #"\brecording\s+(?:shuru|chalu|start)\b"#,
            #"^quick\s*meet(?:ing)?\s*(?:start|shuru)?\s*$"#
        ]
        return patterns.contains { VidurRx.matches($0, text) }
    }

    // MARK: Complete an action

    private static func completeQuery(_ text: String) -> String? {
        let patterns = [
            #"^(?:mark|set)\s+(.+?)\s+(?:as\s+)?(?:done|complete|completed|finished)$"#,
            #"^(?:complete|finish|tick\s+off|check\s+off)\s+(.+)$"#,
            #"^close\s+(?:the\s+|my\s+)?(?:task|action|action\s+item|to-?do)\s+(.+)$"#,
            #"^(.+?)\s+(?:done\s+ho\s+gaya|ho\s+gaya|hogaya|complete\s+ho\s+gaya|ho\s+gayi|kar\s+diya|kardiya)$"#,
            #"^(.+?)\s+(?:done|complete)\s+(?:mark\s+)?(?:karo|kar\s+do|kardo)$"#
        ]
        for pattern in patterns {
            guard let captures = VidurRx.captures(pattern, in: text) else { continue }
            let cleaned = VidurRx.tidy(VidurRx.replacing(
                #"\b(?:the|my|that|this|task|tasks|action|actions|item|items|as|to-?do|ko)\b"#, in: captures[1]))
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    // MARK: Important

    private static func importantRequest(_ text: String) -> (query: String, preferLast: Bool, important: Bool)? {
        let off = [
            #"^(?:unstar|unfavou?rite|unflag)\s+(.+)$"#,
            #"^(?:mark|make|set)\s+(.+?)\s+(?:as\s+)?(?:not\s+important|unimportant)$"#,
            #"^remove\s+(.+?)\s+from\s+(?:my\s+)?(?:important|favou?rites?|starred)$"#
        ]
        let on = [
            #"^(?:star|favou?rite|flag|bookmark|pin)\s+(.+)$"#,
            #"^(?:mark|make|set)\s+(.+?)\s+(?:as\s+)?(?:important|a\s+favou?rite|favou?rite|starred|priority)$"#,
            #"^(.+?)\s+(?:ko\s+)?(?:important|favou?rite|star)\s+(?:mark\s+)?(?:karo|kar\s+do|kardo)$"#,
            #"^add\s+(.+?)\s+to\s+(?:my\s+)?(?:important|favou?rites?|starred)$"#
        ]
        for pattern in off {
            if let captures = VidurRx.captures(pattern, in: text) {
                let parsed = meetingQuery(captures[1])
                return (parsed.query, parsed.preferLast, false)
            }
        }
        for pattern in on {
            if let captures = VidurRx.captures(pattern, in: text) {
                let parsed = meetingQuery(captures[1])
                return (parsed.query, parsed.preferLast, true)
            }
        }
        return nil
    }

    /// Splits "the last design review meeting" into the words to search for and a "last" flag.
    static func meetingQuery(_ raw: String) -> (query: String, preferLast: Bool) {
        var query = raw
        let lastPattern = #"\b(?:last|latest|recent|previous|most\s+recent|pichl[ai]|pichhl[ai]|aakhri|akhri)\b"#
        let preferLast = VidurRx.matches(lastPattern, query)
        if preferLast { query = VidurRx.replacing(lastPattern, in: query) }
        query = VidurRx.replacing(
            #"\b(?:the|my|that|this|our|a|an|meeting|meetings|call|please|as|ko|wali|wala|vali|vala|one|ka|ki)\b"#, in: query)
        return (VidurRx.tidy(query), preferLast)
    }

    // MARK: Open

    private static func openRequest(_ text: String) -> VidurCommand? {
        var target: String?
        if let captures = VidurRx.captures(#"^(?:open|go\s+to|goto|take\s+me\s+to|pull\s+up|switch\s+to)\s+(.+)$"#, in: text) {
            target = captures[1]
        } else if let captures = VidurRx.captures(#"^show\s+(?:me\s+)?(.+)$"#, in: text),
                  VidurRx.matches(#"\b(?:meeting|call|minutes|notes|recording|transcript)\b"#, captures[1]) {
            target = captures[1]
        } else if let captures = VidurRx.captures(#"^(.+?)\s+(?:kholo|khol\s+do|dikhao|dikha\s+do|open\s+karo|open\s+kar\s+do)$"#, in: text) {
            target = captures[1]
        }
        guard let target else { return nil }
        let lowered = VidurRx.tidy(VidurRx.replacing(#"\b(?:the|my|page|screen|tab)\b"#, in: target.lowercased()))
        switch lowered {
        case "settings", "setting", "preferences": return .openScreen(.settings)
        case "actions", "action items", "tasks", "my tasks", "my actions", "to-dos", "todos": return .openScreen(.actions)
        case "search": return .openScreen(.search)
        case "home", "meetings", "all meetings": return .openScreen(.home)
        default: break
        }
        let parsed = meetingQuery(target)
        // "open the last meeting" has no words left but is still a clear request.
        if parsed.query.isEmpty && !parsed.preferLast && !VidurRx.matches(#"\bmeeting\b"#, target) { return nil }
        return .openMeeting(query: parsed.query, preferLast: parsed.preferLast)
    }

    // MARK: Schedule

    private static func isSchedule(_ text: String) -> Bool {
        let hasNoun = VidurRx.matches(meetingNoun, text)
        let hasCue = VidurRx.matches(#"\b(?:tomorrow|today|tonight|next|at\s+\d|\d\s*(?:am|pm)|with|kal|aaj|parso)\b"#, text)
        let isAction = VidurRx.matches(actionNoun, text)
        if VidurRx.matches(#"^(?:schedule|set\s*up|book|arrange|organi[sz]e|fix)\b"#, text) { return hasNoun || hasCue }
        if VidurRx.matches(#"^(?:plan|create|add|put|make|new)\b"#, text) { return hasNoun && !isAction }
        let hinglishVerb = #"\b(?:karo|kar\s+do|kardo|rakho|rakh\s+do|rakhdo|lagao|banao|bana\s+do)\b"#
        if VidurRx.matches(hinglishVerb, text) && !isAction { return hasNoun || VidurRx.matches(#"\bschedule\b"#, text) }
        return false
    }

    static func scheduleDraft(_ input: String, now: Date, calendar: Calendar) -> VidurScheduleDraft? {
        var text = input
        text = VidurRx.replacing(#"^(?:schedule|set\s*up|book|arrange|organi[sz]e|fix|plan|create|add|put|make|new)\b\s*(?:me\s+)?(?:up\s+)?"#, in: text, with: "")
        text = VidurRx.replacing(#"\b(?:schedule\s+)?(?:karo|kar\s+do|kardo|kijiye|rakho|rakh\s+do|rakhdo|lagao|banao|bana\s+do)\b"#, in: text)
        text = VidurRx.replacing(#"\b(?:please|pls)\b"#, in: text)

        let repeatRule = VidurWhenParser.takeRepeat(from: &text)
        let minutes = VidurWhenParser.takeDuration(from: &text)
        let when = VidurWhenParser.extract(from: &text, now: now, calendar: calendar)
        let people = takePeople(from: &text)

        text = VidurRx.replacing(#"\b(?:ke\s+saath|ke\s+liye)\b"#, in: text)
        var title = cleanTitle(text)
        let generic = ["meeting", "a meeting", "meet", "call", "a call", "meetings"]
        if title.isEmpty || generic.contains(title.lowercased()) { title = "Meeting" }

        let resolved = VidurWhenParser.resolveStart(when, now: now, calendar: calendar)
        return VidurScheduleDraft(title: title, start: resolved.date, durationMinutes: minutes ?? 30, people: people,
                                  repeatRule: repeatRule, timeAssumed: resolved.assumed)
    }

    private static func takePeople(from text: inout String) -> [String] {
        let stop = #"(?=\s+(?:about|regarding|to\s+discuss|for|on|at|by|every|daily|weekly|monthly|over|in|and\s+then)\b|$)"#
        var raw: String?
        if let captures = VidurRx.take(#"\b(?:with|w/|invite|inviting)\s+(.+?)"# + stop, from: &text) {
            raw = captures[1]
        } else if let captures = VidurRx.take(#"\b((?-i:[A-Z][\w'.-]*)(?:\s*(?:,|and|aur|&)\s*(?-i:[A-Z][\w'.-]*))*)\s+ke\s+saath\b"#, from: &text) {
            raw = captures[1]
        }
        guard let raw else { return [] }
        return splitNames(raw)
    }

    static func splitNames(_ raw: String) -> [String] {
        let separated = VidurRx.replacing(#"\s*(?:,|&|\band\b|\baur\b|\bplus\b)\s*"#, in: raw, with: "|")
        var names: [String] = []
        let pronouns: Set<String> = ["me", "us", "myself", "everyone", "everybody", "them", "him", "her", "the team", "team"]
        for piece in separated.split(separator: "|") {
            let words = piece.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard !words.isEmpty, words.count <= 3 else { continue }
            let joined = words.joined(separator: " ")
            if pronouns.contains(joined.lowercased()) { continue }
            if joined.contains(where: { $0.isNumber }) { continue }
            let capitalised = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            if !names.contains(capitalised), names.count < 8 { names.append(capitalised) }
        }
        return names
    }

    static func cleanTitle(_ raw: String) -> String {
        var title = VidurRx.tidy(raw)
        for _ in 0..<3 {
            title = VidurRx.tidy(VidurRx.replacing(#"^(?:a|an|the|one|my|our|new|for|to\s+discuss|about|regarding|on|at|by|in|with|from)\b"#, in: title, with: ""))
            title = VidurRx.tidy(VidurRx.replacing(#"\b(?:at|on|by|for|with|from|in|to|and|of)$"#, in: title, with: ""))
        }
        guard let first = title.first else { return "" }
        return String(first).uppercased() + title.dropFirst()
    }

    // MARK: Actions

    private static func actionRequest(_ input: String, now: Date, calendar: Calendar) -> VidurCommandOutcome? {
        let isRemind = VidurRx.matches(#"^remind\b"#, input)
        let isAssign = VidurRx.matches(#"^assign\b"#, input)
        let isAdd = VidurRx.matches(#"^(?:add|create|new|make|log|note|put)\b"#, input)
            && VidurRx.matches(actionNoun, input)
        let isHinglish = VidurRx.matches(#"\s(?:yaad\s+dilao|yaad\s+dila\s+do|remind\s+karo|remind\s+kar\s+do)$"#, input)
        guard isRemind || isAssign || isAdd || isHinglish else { return nil }

        var text = input
        let when = VidurWhenParser.extract(from: &text, now: now, calendar: calendar)
        text = VidurRx.tidy(text)

        var assignee: String?
        var body = ""
        if let captures = VidurRx.captures(#"^remind\s+me\b\s*(.*)$"#, in: text) {
            body = captures[1]
        } else if let captures = VidurRx.captures(#"^remind\s+(.+?)\s+(?:to|about|that)\s+(.+)$"#, in: text) {
            assignee = captures[1]
            body = captures[2]
        } else if let captures = VidurRx.captures(#"^assign\s+(.+?)\s+to\s+(.+)$"#, in: text) {
            body = captures[1]
            assignee = captures[2]
        } else if let captures = VidurRx.captures(#"^(.+?)\s+ko\s+(.+?)\s+(?:yaad\s+dilao|yaad\s+dila\s+do|remind\s+karo|remind\s+kar\s+do)$"#, in: text) {
            assignee = captures[1]
            body = captures[2]
        } else if let captures = VidurRx.captures(#"^(?:add|create|new|make|log|note|put)\s+(?:a\s+|an\s+|new\s+)*(?:action\s*items?|actions?|tasks?|to-?do|reminder)\b\s*(.*)$"#, in: text) {
            body = captures[1]
            if let forPerson = VidurRx.captures(#"^for\s+(.+?)\s*(?::|-|\bto\b)\s*(.+)$"#, in: body) {
                assignee = forPerson[1]
                body = forPerson[2]
            } else {
                body = VidurRx.replacing(#"^(?:to|that|called|named|:|-)\s*"#, in: body, with: "")
            }
        } else if let captures = VidurRx.captures(#"^(?:add|put)\s+(.+?)\s+(?:to|in|on)\s+(?:my\s+|the\s+)?(?:actions?|tasks?|to-?do(?:\s+list)?)\b.*$"#, in: text) {
            body = captures[1]
        } else {
            return nil
        }

        body = VidurRx.tidy(VidurRx.replacing(#"^(?:to|about|that)\b"#, in: VidurRx.tidy(body), with: ""))
        if assignee == nil,
           let trailing = VidurRx.captures(#"^(.+?)\s+(?:assigned\s+to|for)\s+((?-i:[A-Z][\w'.-]*(?:\s+(?-i:[A-Z][\w'.-]*))?))\s*$"#, in: body) {
            body = trailing[1]
            assignee = trailing[2]
        }
        body = stripTrailingConnector(body)
        if var name = assignee {
            name = stripTrailingConnector(VidurRx.tidy(name))
            let lowered = name.lowercased()
            if lowered == "me" || lowered == "myself" || lowered == "mujhe" || name.isEmpty {
                assignee = nil
            } else {
                assignee = name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            }
        }
        guard body.count >= 2 else {
            return .reply("What should the task say? For example: \u{201C}remind Pawan to send the deck by Friday\u{201D}.")
        }
        let title = body.prefix(1).uppercased() + body.dropFirst()
        let due = VidurWhenParser.resolveDue(when, now: now, calendar: calendar)
        return .command(.addAction(VidurActionDraft(title: title, assignee: assignee, due: due)))
    }

    private static func stripTrailingConnector(_ text: String) -> String {
        VidurRx.tidy(VidurRx.replacing(#"\b(?:by|before|due|on|until|till|at|for|to|the)$"#, in: VidurRx.tidy(text), with: ""))
    }
}

// MARK: - Regex helpers

enum VidurRx {
    static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// Captures of the first match. Index 0 is the whole match. Unmatched groups are empty strings.
    static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let expression = regex(pattern) else { return nil }
        let ns = text as NSString
        guard let match = expression.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        var result: [String] = []
        for index in 0..<match.numberOfRanges {
            let range = match.range(at: index)
            result.append(range.location == NSNotFound ? "" : ns.substring(with: range))
        }
        return result
    }

    static func matches(_ pattern: String, _ text: String) -> Bool { captures(pattern, in: text) != nil }

    /// Removes the first match from `text` and returns its captures.
    static func take(_ pattern: String, from text: inout String) -> [String]? {
        guard let expression = regex(pattern) else { return nil }
        let ns = text as NSString
        guard let match = expression.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        var result: [String] = []
        for index in 0..<match.numberOfRanges {
            let range = match.range(at: index)
            result.append(range.location == NSNotFound ? "" : ns.substring(with: range))
        }
        text = ns.replacingCharacters(in: match.range, with: " ")
        return result
    }

    /// Replaces every match.
    static func replacing(_ pattern: String, in text: String, with template: String = " ") -> String {
        guard let expression = regex(pattern) else { return text }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return expression.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    /// Collapses spaces and trims spaces and punctuation from both ends.
    static func tidy(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!?-\u{2013}\u{2014}"))
    }
}

// MARK: - Dates, times, durations, repeats

struct VidurWhen {
    var day: Date?
    var hour: Int?
    var minute = 0
    /// Set for "in 2 hours" style requests.
    var absolute: Date?
}

enum VidurWhenParser {
    static let weekdays: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
        "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6,
        "somvar": 2, "somwar": 2, "mangalvar": 3, "mangalwar": 3, "budhvar": 4, "budhwar": 4,
        "guruvar": 5, "guruwar": 5, "brihaspativar": 5, "shukravar": 6, "shukrawar": 6,
        "shanivar": 7, "shaniwar": 7, "ravivar": 1, "raviwar": 1
    ]
    static let months: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7, "august": 8,
        "september": 9, "october": 10, "november": 11, "december": 12,
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9,
        "oct": 10, "nov": 11, "dec": 12
    ]

    private static var weekdayAlternation: String {
        weekdays.keys.sorted { $0.count > $1.count }.joined(separator: "|")
    }
    private static var monthAlternation: String {
        months.keys.sorted { $0.count > $1.count }.joined(separator: "|")
    }

    // MARK: Repeat and duration

    static func takeRepeat(from text: inout String) -> VidurRepeat? {
        if VidurRx.take(#"\b(?:every\s+other\s+week|every\s+(?:2|two)\s+weeks|fortnightly|bi-?weekly)\b"#, from: &text) != nil {
            return .biweekly
        }
        if VidurRx.take(#"\b(?:every\s+(?:single\s+)?day|daily|everyday|har\s+din|har\s+roz|roz)\b"#, from: &text) != nil {
            return .daily
        }
        if VidurRx.take(#"\b(?:every\s+week|weekly|har\s+(?:hafte|hafta|week))\b"#, from: &text) != nil {
            return .weekly
        }
        if VidurRx.take(#"\b(?:every\s+month|monthly|har\s+(?:mahine|month))\b"#, from: &text) != nil {
            return .monthly
        }
        if let captures = VidurRx.take(#"\bevery\s+("# + weekdayAlternation + #")\b"#, from: &text) {
            text += " " + captures[1]
            return .weekly
        }
        return nil
    }

    /// Minutes, from "for 45 minutes", "an hour long", "1 hour meeting" and "30 min call".
    static func takeDuration(from text: inout String) -> Int? {
        if VidurRx.take(#"\b(?:for\s+)?half\s+an?\s+hour\b"#, from: &text) != nil { return 30 }
        if VidurRx.take(#"\bfor\s+(?:an?|one)\s+hour\b"#, from: &text) != nil { return 60 }
        if let captures = VidurRx.take(#"\bfor\s+(?:about\s+)?(\d{1,3}(?:\.\d)?)\s*(hours?|hrs?|h|minutes?|mins?|m)\b"#, from: &text) {
            return minutes(value: captures[1], unit: captures[2])
        }
        if let captures = VidurRx.take(#"\b(\d{1,3}(?:\.\d)?)[\s-]*(hours?|hrs?|minutes?|mins?)[\s-]*(?:long\s+)?(?=meeting|call|sync|session|catch|review|stand)"#, from: &text) {
            return minutes(value: captures[1], unit: captures[2])
        }
        if let captures = VidurRx.take(#"\b(\d{1,3}(?:\.\d)?)\s*(minutes?|mins?|ghante|ghanta|hours?)\s*(?:ke\s+liye|ka|tak)\b"#, from: &text) {
            return minutes(value: captures[1], unit: captures[2])
        }
        return nil
    }

    private static func minutes(value: String, unit: String) -> Int? {
        guard let number = Double(value), number > 0 else { return nil }
        let lowered = unit.lowercased()
        let isHours = lowered.hasPrefix("h") || lowered.hasPrefix("ghant")
        let total = Int((isHours ? number * 60 : number).rounded())
        return max(5, min(total, 12 * 60))
    }

    // MARK: Date and time

    static func extract(from text: inout String, now: Date, calendar: Calendar) -> VidurWhen {
        var when = VidurWhen()
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }

        // Period of day first, so "5 baje" after "shaam" becomes 17:00.
        var period: String?
        if let captures = VidurRx.take(#"\b(?:in\s+the\s+|this\s+)?(morning|subah|afternoon|dopahar|evening|shaam|night|raat|tonight)\b"#, from: &text) {
            period = captures[1].lowercased()
            if period == "tonight" { when.day = today }
        }

        extractTime(from: &text, period: period, into: &when)
        if when.hour == nil, let period {
            switch period {
            case "morning", "subah": when.hour = 9
            case "afternoon", "dopahar": when.hour = 14
            case "evening", "shaam": when.hour = 18
            default: when.hour = 20
            }
        }

        if let captures = VidurRx.take(#"\bin\s+(\d{1,3})\s*(minutes?|mins?|hours?|hrs?|days?|weeks?)\b"#, from: &text) {
            let value = Int(captures[1]) ?? 0
            let unit = captures[2].lowercased()
            if unit.hasPrefix("min") {
                when.absolute = now.addingTimeInterval(TimeInterval(value * 60))
            } else if unit.hasPrefix("h") {
                when.absolute = now.addingTimeInterval(TimeInterval(value * 3600))
            } else if unit.hasPrefix("d") {
                when.day = day(value)
            } else {
                when.day = day(value * 7)
            }
            return when
        }
        if VidurRx.take(#"\b(?:day\s+after\s+tomorrow|parso|parson|parsoon)\b"#, from: &text) != nil {
            when.day = day(2)
        } else if VidurRx.take(#"\b(?:tomorrow|tmrw|tmr|kal)\b"#, from: &text) != nil {
            when.day = day(1)
        } else if VidurRx.take(#"\b(?:today|aaj)\b"#, from: &text) != nil {
            when.day = day(0)
        } else if let captures = VidurRx.take(#"\b(?:on\s+)?(?:(this|next|coming)\s+)?("# + weekdayAlternation + #")\b"#, from: &text),
                  let target = weekdays[captures[2].lowercased()] {
            when.day = nextWeekday(target, qualifier: captures[1].lowercased(), today: today, calendar: calendar)
        } else if let captures = VidurRx.take(#"\b(?:on\s+)?(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?("# + monthAlternation + #")\b"#, from: &text),
                  let date = monthDay(month: captures[2], day: captures[1], today: today, calendar: calendar) {
            when.day = date
        } else if let captures = VidurRx.take(#"\b(?:on\s+)?("# + monthAlternation + #")\s+(\d{1,2})(?:st|nd|rd|th)?\b"#, from: &text),
                  let date = monthDay(month: captures[1], day: captures[2], today: today, calendar: calendar) {
            when.day = date
        } else if let captures = VidurRx.take(#"\bon\s+(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)\b"#, from: &text),
                  let dayNumber = Int(captures[1]), (1...31).contains(dayNumber) {
            var components = calendar.dateComponents([.year, .month], from: today)
            components.day = dayNumber
            if let date = calendar.date(from: components) {
                if date < today, let later = calendar.date(byAdding: .month, value: 1, to: date) {
                    when.day = later
                } else {
                    when.day = date
                }
            }
        } else if VidurRx.take(#"\bnext\s+week\b"#, from: &text) != nil {
            when.day = nextWeekday(2, qualifier: "", today: today, calendar: calendar)
        } else if VidurRx.take(#"\b(?:end\s+of\s+(?:the\s+)?day|eod)\b"#, from: &text) != nil {
            when.day = day(0)
            if when.hour == nil { when.hour = 18 }
        } else if VidurRx.take(#"\b(?:end\s+of\s+(?:the\s+)?week|eow)\b"#, from: &text) != nil {
            when.day = nextWeekday(6, qualifier: "this", today: today, calendar: calendar)
        }
        return when
    }

    private static func extractTime(from text: inout String, period: String?, into when: inout VidurWhen) {
        if let captures = VidurRx.take(#"(?:\b(?:at|@|by|around|from)\s+)?\b(\d{1,2})(?:[:.](\d{2}))?\s*([ap])\.?m\b\.?"#, from: &text),
           let hour = Int(captures[1]) {
            let meridiem = captures[3].lowercased().first
            if let resolved = resolveHour(hour, meridiem: meridiem, period: period) {
                when.hour = resolved
                when.minute = min(59, Int(captures[2]) ?? 0)
            }
            return
        }
        if let captures = VidurRx.take(#"(?:\b(?:at|@|by|around|from)\s+)?\b(\d{1,2}):(\d{2})\b"#, from: &text),
           let hour = Int(captures[1]), let minute = Int(captures[2]), minute < 60 {
            if let resolved = resolveHour(hour, meridiem: nil, period: period) {
                when.hour = resolved
                when.minute = minute
            }
            return
        }
        if let captures = VidurRx.take(#"\b(?:at|@|around)\s+(\d{1,2})(?![\d:])(?!\s*(?:minutes?|mins?|hours?|hrs?|days?|weeks?|%))(?:\s*o'?clock)?\b"#, from: &text),
           let hour = Int(captures[1]) {
            if let resolved = resolveHour(hour, meridiem: nil, period: period) { when.hour = resolved }
            return
        }
        if let captures = VidurRx.take(#"\b(\d{1,2})\s*baje\b"#, from: &text), let hour = Int(captures[1]) {
            if let resolved = resolveHour(hour, meridiem: nil, period: period) { when.hour = resolved }
            return
        }
        if VidurRx.take(#"\b(?:noon|midday)\b"#, from: &text) != nil { when.hour = 12; return }
        if VidurRx.take(#"\bmidnight\b"#, from: &text) != nil { when.hour = 0 }
    }

    /// "4" means 4 PM, "9" means 9 AM, unless AM/PM or a time of day says otherwise.
    static func resolveHour(_ hour: Int, meridiem: Character?, period: String?) -> Int? {
        if let meridiem {
            guard (1...12).contains(hour) else { return hour < 24 ? hour : nil }
            if meridiem == "a" { return hour == 12 ? 0 : hour }
            return hour == 12 ? 12 : hour + 12
        }
        guard hour >= 0, hour <= 23 else { return nil }
        if hour == 0 || hour >= 13 { return hour }
        switch period ?? "" {
        case "morning", "subah":
            return hour == 12 ? 0 : hour
        case "afternoon", "dopahar", "evening", "shaam", "night", "raat", "tonight":
            return hour == 12 ? 12 : hour + 12
        default:
            break
        }
        if hour >= 8 && hour <= 11 { return hour }
        return hour == 12 ? 12 : hour + 12
    }

    private static func nextWeekday(_ target: Int, qualifier: String, today: Date, calendar: Calendar) -> Date {
        let current = calendar.component(.weekday, from: today)
        var delta = (target - current + 7) % 7
        if delta == 0 { delta = qualifier == "this" ? 0 : 7 }
        var date = calendar.date(byAdding: .day, value: delta, to: today) ?? today
        if qualifier == "next", calendar.isDate(date, equalTo: today, toGranularity: .weekOfYear) {
            date = calendar.date(byAdding: .day, value: 7, to: date) ?? date
        }
        return date
    }

    private static func monthDay(month: String, day: String, today: Date, calendar: Calendar) -> Date? {
        guard let monthNumber = months[month.lowercased()], let dayNumber = Int(day), (1...31).contains(dayNumber) else {
            return nil
        }
        var components = DateComponents()
        components.year = calendar.component(.year, from: today)
        components.month = monthNumber
        components.day = dayNumber
        guard var date = calendar.date(from: components) else { return nil }
        if date < today, let next = calendar.date(byAdding: .year, value: 1, to: date) { date = next }
        return date
    }

    // MARK: Resolving

    /// The start of a meeting. Without a time the user hears the assumption on the card.
    static func resolveStart(_ when: VidurWhen, now: Date, calendar: Calendar) -> (date: Date, assumed: Bool) {
        if let absolute = when.absolute { return (absolute, false) }
        var hour = when.hour
        var minute = when.minute
        var assumed = false
        if hour == nil {
            if when.day == nil {
                let parts = calendar.dateComponents([.year, .month, .day, .hour], from: now)
                let floor = calendar.date(from: parts) ?? now
                return (calendar.date(byAdding: .hour, value: 1, to: floor) ?? now.addingTimeInterval(3600), true)
            }
            hour = 10
            minute = 0
            assumed = true
        }
        let base = when.day ?? calendar.startOfDay(for: now)
        var result = calendar.date(bySettingHour: hour ?? 10, minute: minute, second: 0, of: base) ?? base
        if when.day == nil, result <= now {
            result = calendar.date(byAdding: .day, value: 1, to: result) ?? result
        }
        return (result, assumed)
    }

    /// A due date for an action. Nil when the user named no day or time.
    static func resolveDue(_ when: VidurWhen, now: Date, calendar: Calendar) -> Date? {
        if let absolute = when.absolute { return absolute }
        guard when.day != nil || when.hour != nil else { return nil }
        let base = when.day ?? calendar.startOfDay(for: now)
        var result = calendar.date(bySettingHour: when.hour ?? 18, minute: when.hour == nil ? 0 : when.minute,
                                   second: 0, of: base) ?? base
        if when.day == nil, result <= now {
            result = calendar.date(byAdding: .day, value: 1, to: result) ?? result
        }
        return result
    }
}

// MARK: - Matching names to saved items

public struct VidurNamedItem: Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let date: Date

    public init(id: UUID, title: String, date: Date) {
        self.id = id
        self.title = title
        self.date = date
    }
}

public enum VidurTitleMatcher {
    private static let stopWords: Set<String> = ["the", "a", "an", "of", "for", "to", "and", "my", "our", "on", "in", "with"]

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }

    private static func wordsMatch(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        guard min(lhs.count, rhs.count) >= 3 else { return false }
        return lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)
    }

    /// The item whose title best fits `query`. Ties go to the most recent item that is not in the future
    /// when `preferLast` is set, otherwise to the item closest to `now`. Nil when nothing fits well enough.
    public static func best(query: String, in items: [VidurNamedItem], preferLast: Bool = false,
                            now: Date = Date()) -> VidurNamedItem? {
        guard !items.isEmpty else { return nil }
        let queryWords = words(query)
        var candidates = items
        if !queryWords.isEmpty {
            var scored: [(item: VidurNamedItem, score: Double)] = []
            for item in items {
                let titleWords = words(item.title)
                let hits = queryWords.filter { word in titleWords.contains { wordsMatch($0, word) } }.count
                let score = Double(hits) / Double(queryWords.count)
                if score >= 0.5 { scored.append((item, score)) }
            }
            guard let top = scored.map({ $0.score }).max() else { return nil }
            candidates = scored.filter { $0.score == top }.map { $0.item }
        }
        if preferLast {
            let past = candidates.filter { $0.date <= now }
            let pool = past.isEmpty ? candidates : past
            return pool.max { $0.date < $1.date }
        }
        return candidates.min { abs($0.date.timeIntervalSince(now)) < abs($1.date.timeIntervalSince(now)) }
    }
}

// MARK: - Typed greeting

public enum VidurAddressPrefix {
    /// Removes a leading "hey Vidur" from typed text, so "hey vidur what did we decide" is just the question.
    public static func stripLeading(_ text: String) -> String {
        let pattern = #"^\s*(?:(?:hey|hi|hay|hello|ok|okay)\s+)?vi+d+h?(?:u|oo|a|o|e)+r\b[,\s]*"#
        return VidurRx.replacing(pattern, in: text, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}