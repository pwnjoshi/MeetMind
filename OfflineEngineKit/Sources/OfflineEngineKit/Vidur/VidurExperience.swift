import Foundation

// Small, pure pieces of Vidur's chat experience: the time-aware greeting, the one-line insight shown when the
// sheet opens, suggestions built from real data, how long an answer should be, honest "not found" wording, how
// an answer splits into native rows, and the content-free latency log line. No model and no UI, so all of it is
// unit tested.

// MARK: - Greeting

public enum VidurDayPart: Sendable, Equatable {
    case morning, afternoon, evening, night
}

public enum VidurGreeting {
    public static func dayPart(at now: Date, calendar: Calendar = .current) -> VidurDayPart {
        switch calendar.component(.hour, from: now) {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<22: return .evening
        default: return .night
        }
    }

    /// "Good morning, Arjun" or "Good morning" when the name is unknown. Late at night it is a plain "Hello".
    public static func title(for context: VidurAssistantContext, now: Date = Date(),
                             calendar: Calendar = .current) -> String {
        let base: String
        switch dayPart(at: now, calendar: calendar) {
        case .morning: base = "Good morning"
        case .afternoon: base = "Good afternoon"
        case .evening: base = "Good evening"
        case .night: base = "Hello"
        }
        if let name = context.firstName { return "\(base), \(name)" }
        return base
    }
}

// MARK: - One-line insight

public enum VidurInsight {
    /// One short sentence about what needs attention, from real data only. Nil when nothing does.
    public static func line(for context: VidurAssistantContext, now: Date = Date(),
                            calendar: Calendar = .current) -> String? {
        if context.isRecording { return nil }
        func actions(_ count: Int) -> String { count == 1 ? "1 action" : "\(count) actions" }
        let dueToday = context.dueTodayActionCount
        let overdue = context.overdueActionCount
        if dueToday > 0 {
            let verb = dueToday == 1 ? "is" : "are"
            var text = "\(actions(dueToday)) \(verb) due today"
            if overdue > 0 { text += " and \(overdue) \(overdue == 1 ? "is" : "are") overdue" }
            return text + "."
        }
        if overdue > 0 {
            return "\(actions(overdue)) \(overdue == 1 ? "is" : "are") overdue."
        }
        if let next = context.upcomingToday.first, next.start > now, next.start.timeIntervalSince(now) <= 3 * 3_600,
           next.title.count <= 40 {
            return "\(next.title) starts at \(VidurProactive.clock(next.start, calendar: calendar))."
        }
        if context.unreviewedSuggestionCount > 0 {
            let count = context.unreviewedSuggestionCount
            return "\(count) suggested \(count == 1 ? "action needs" : "actions need") a look."
        }
        return nil
    }
}

// MARK: - Smart suggestions

public struct VidurSmartSuggestion: Sendable, Equatable, Identifiable {
    public let text: String
    /// An SF Symbol name.
    public let symbol: String
    public var id: String { text }

    public init(text: String, symbol: String) {
        self.text = text
        self.symbol = symbol
    }
}

extension VidurProactive {
    /// Up to `limit` suggestions for the empty chat, from real data: today's meeting, what is overdue or due,
    /// the last meeting, then general questions. Every text is a question Vidur can answer or a command it runs.
    public static func smartSuggestions(for context: VidurAssistantContext, limit: Int = 4,
                                        now: Date = Date(), calendar: Calendar = .current) -> [VidurSmartSuggestion] {
        var list: [VidurSmartSuggestion] = []
        func add(_ text: String, _ symbol: String) {
            guard !list.contains(where: { $0.text.lowercased() == text.lowercased() }) else { return }
            list.append(VidurSmartSuggestion(text: text, symbol: symbol))
        }
        if context.isRecording {
            add("What did we decide?", "checkmark.seal")
            add("Which tasks are still open?", "checklist")
            return Array(list.prefix(max(1, limit)))
        }
        if let next = context.upcomingToday.first ?? context.nextMeeting, next.title.count <= 40 {
            if context.nextMeetingHasHistory {
                add("What did we decide in the last \(next.title)?", "calendar")
            } else {
                add("Remind me to prepare for \(next.title)", "bell")
            }
        }
        if context.overdueActionCount > 0 { add("What is overdue for me?", "exclamationmark.circle") }
        if context.dueTodayActionCount > 0 { add("What is due today?", "clock") }
        if context.unreviewedSuggestionCount > 0 { add("Which tasks did Vidur suggest?", "sparkles") }
        if context.lastMeetingHasMinutes, context.lastMeetingTitle != nil {
            add("Summarize the last meeting", "text.alignleft")
        }
        if context.hasAnyMeetings {
            add("What did we decide?", "checkmark.seal")
            add("Which tasks are still open?", "checklist")
        }
        if list.isEmpty { add("Schedule a meeting tomorrow at 10", "calendar.badge.plus") }
        return Array(list.prefix(max(1, limit)))
    }
}

// MARK: - Answer length

/// How long an answer should be. A fact is one sentence. An overview ("how did it go", a summary) is a few.
public enum VidurAnswerShape: Sendable, Equatable {
    case fact, overview

    public static func of(_ question: String) -> VidurAnswerShape {
        if VidurRagRouting.isOpenEnded(question) { return .overview }
        let lower = question.lowercased()
        let cues = ["summarize", "summarise", "summary", "recap", "overview", "walk me through", "saransh"]
        return cues.contains { lower.contains($0) } ? .overview : .fact
    }

    /// The sentence-length rule placed in the system prompt.
    var promptRule: String {
        switch self {
        case .fact: return "One short sentence for a plain fact, up to 3 when needed."
        case .overview: return "3 to 4 short sentences for an overview or a how-did-it-go question."
        }
    }
}

// MARK: - Honest fallback

public enum VidurFallback {
    public static let englishMiss = "I couldn\u{2019}t find that in your meetings."

    /// True for the wording Vidur uses when a search found nothing.
    public static func isSearchMiss(_ text: String) -> Bool {
        let flat = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if [VidurGroundedPrompt.notDiscussedEnglish, VidurGroundedPrompt.notDiscussedHindi,
            VidurGroundedPrompt.notDiscussedHinglish].contains(flat) { return true }
        return flat.lowercased().contains("couldn't find")
    }

    /// The not-found sentence plus one or two questions that Vidur can answer, in the language of the question.
    /// Text that is not a search miss, or already offers something to try, is returned unchanged.
    public static func notFound(base: String, suggestions: [String], language: VidurAnswerLanguage) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSearchMiss(trimmed) else { return base }
        let lower = trimmed.lowercased()
        if lower.contains("try ") || lower.contains("puch sakte") || trimmed.contains("\u{092A}\u{0942}\u{091B}") {
            return trimmed
        }
        let picks = suggestions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.prefix(2).map { "\u{201C}\($0)\u{201D}" }
        var head = trimmed
        if trimmed == VidurGroundedPrompt.notDiscussedEnglish { head = englishMiss }
        guard !picks.isEmpty else { return head }
        switch language {
        case .english:
            return head + " Try asking " + picks.joined(separator: " or ") + "."
        case .hinglish:
            return head + " Aap yeh puch sakte hain: " + picks.joined(separator: " ya ") + "."
        case .hindi:
            let lead = "\u{0906}\u{092A} \u{092F}\u{0939} \u{092A}\u{0942}\u{091B} \u{0938}\u{0915}\u{0924}\u{0947} \u{0939}\u{0948}\u{0902}: "
            return head + " " + lead + picks.joined(separator: " \u{092F}\u{093E} ") + "\u{0964}"
        }
    }
}

// MARK: - Answer layout

/// An answer split into a lead-in, bullet rows and a closing line, so a list renders as native rows.
public struct VidurAnswerLayout: Sendable, Equatable {
    public var intro: String
    public var bullets: [String]
    public var outro: String

    /// Lines that start with a bullet become rows when there are at least two. Anything else stays text.
    public static func parse(_ text: String) -> VidurAnswerLayout {
        var intro: [String] = []
        var bullets: [String] = []
        var outro: [String] = []
        for raw in text.split(whereSeparator: { $0.isNewline }) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("\u{2022}"), outro.isEmpty {
                let body = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !body.isEmpty { bullets.append(body) }
            } else if bullets.isEmpty {
                intro.append(line)
            } else {
                outro.append(line)
            }
        }
        guard bullets.count >= 2 else { return VidurAnswerLayout(intro: text, bullets: [], outro: "") }
        return VidurAnswerLayout(intro: intro.joined(separator: "\n"), bullets: bullets,
                                 outro: outro.joined(separator: "\n"))
    }
}

// MARK: - Latency

public enum VidurLatency {
    /// The content-free log line: the tier and two durations, never a question or an answer.
    public static func line(tier: String, firstTokenMs: Int?, totalMs: Int) -> String {
        "Vidur answer tier=\(tier) first_token_ms=\(firstTokenMs ?? -1) total_ms=\(totalMs)"
    }
}
