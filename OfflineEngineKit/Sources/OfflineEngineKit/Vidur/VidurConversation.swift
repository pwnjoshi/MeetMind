import Foundation

// MARK: - What Vidur knows about the user's day

/// A meeting named in a greeting or a suggestion.
public struct VidurMeetingBrief: Sendable, Equatable {
    public var title: String
    public var start: Date

    public init(title: String, start: Date) {
        self.title = title
        self.start = start
    }
}

/// A small snapshot of the user's real data. Suggestions and small talk are built only from this,
/// so Vidur never invents a meeting, a task or a name.
public struct VidurAssistantContext: Sendable, Equatable {
    public var userName: String?
    /// Scheduled meetings that have not started yet today, earliest first.
    public var upcomingToday: [VidurMeetingBrief]
    /// The next scheduled meeting on any day.
    public var nextMeeting: VidurMeetingBrief?
    /// True when `nextMeeting` has an earlier meeting of the same title with saved minutes.
    public var nextMeetingHasHistory: Bool
    public var overdueActionCount: Int
    public var openActionCount: Int
    /// Actions Vidur suggested from a recording that the user has not accepted or dismissed.
    public var unreviewedSuggestionCount: Int
    public var lastMeetingTitle: String?
    public var lastMeetingHasMinutes: Bool
    public var isRecording: Bool
    public var hasAnyMeetings: Bool

    public init(userName: String? = nil, upcomingToday: [VidurMeetingBrief] = [], nextMeeting: VidurMeetingBrief? = nil,
                nextMeetingHasHistory: Bool = false, overdueActionCount: Int = 0, openActionCount: Int = 0,
                unreviewedSuggestionCount: Int = 0, lastMeetingTitle: String? = nil, lastMeetingHasMinutes: Bool = false,
                isRecording: Bool = false, hasAnyMeetings: Bool = false) {
        self.userName = userName
        self.upcomingToday = upcomingToday
        self.nextMeeting = nextMeeting
        self.nextMeetingHasHistory = nextMeetingHasHistory
        self.overdueActionCount = overdueActionCount
        self.openActionCount = openActionCount
        self.unreviewedSuggestionCount = unreviewedSuggestionCount
        self.lastMeetingTitle = lastMeetingTitle
        self.lastMeetingHasMinutes = lastMeetingHasMinutes
        self.isRecording = isRecording
        self.hasAnyMeetings = hasAnyMeetings
    }

    /// "Arjun" for "Arjun Mehta". Nil when the name is the generic placeholder or empty.
    public var firstName: String? {
        guard let userName else { return nil }
        let honorifics: Set<String> = ["dr", "dr.", "mr", "mr.", "mrs", "mrs.", "ms", "ms.", "prof", "prof."]
        let words = userName.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            .filter { !honorifics.contains($0.lowercased()) }
        guard let first = words.first, first.count > 1 else { return nil }
        let generic: Set<String> = ["you", "user", "me", "local", "guest", "unknown"]
        return generic.contains(first.lowercased()) ? nil : first
    }
}

// MARK: - Suggestions

public enum VidurProactive {
    /// Short question or request for a time like "4:00 PM".
    public static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// "today", "tomorrow" or "Friday".
    public static func dayName(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        if days == 0 { return "today" }
        if days == 1 { return "tomorrow" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = days > 0 && days < 7 ? "EEEE" : "d MMM"
        return formatter.string(from: date)
    }

    /// Up to `limit` things worth asking or doing next, built from real data. Questions the instant tier
    /// can answer come first, then one example of something Vidur can do for the user.
    public static func suggestions(for context: VidurAssistantContext, limit: Int = 3,
                                   now: Date = Date(), calendar: Calendar = .current) -> [String] {
        var list: [String] = []
        if context.isRecording { return ["What did we decide?", "Which tasks are still open?"] }
        if let next = context.upcomingToday.first ?? context.nextMeeting {
            if context.nextMeetingHasHistory && next.title.count <= 40 {
                list.append("What did we decide in the last \(next.title)?")
            } else if next.title.count <= 40 {
                list.append("Remind me to prepare for \(next.title)")
            }
        }
        if context.overdueActionCount > 0 { list.append("What is overdue for me?") }
        if context.unreviewedSuggestionCount > 0 { list.append("Which tasks did Vidur suggest?") }
        if context.lastMeetingHasMinutes, context.lastMeetingTitle != nil {
            list.append("Summarize the last meeting")
        }
        if context.hasAnyMeetings {
            list.append("What did we decide?")
            list.append("Which tasks are still open?")
        }
        list.append("Schedule a meeting tomorrow at 10")
        var seen = Set<String>()
        var unique: [String] = []
        for item in list where seen.insert(item.lowercased()).inserted { unique.append(item) }
        return Array(unique.prefix(max(1, limit)))
    }

    /// Follow-up questions after an answer about `intent`, skipping the question that was just asked.
    public static func followUps(after intent: VidurQuickIntent?, asked: String = "", context: VidurAssistantContext,
                                 limit: Int = 3) -> [String] {
        var list: [String]
        switch intent {
        case .some(.tasks):
            list = ["What did we decide?", "What is still unresolved?"]
        case .some(.decisions):
            list = ["Which tasks came out of it?", "What is still unresolved?"]
        case .some(.openIssues):
            list = ["Which tasks are still open?", "What did we decide?"]
        case .some(.summary):
            list = ["What did we decide?", "Which tasks are still open?"]
        case .some(.attendees), .some(.absent):
            list = ["Who has open tasks?", "Summarize the last meeting"]
        case .some(.agenda), .some(.duration), .some(.date), .some(.nextMeeting), .some(.meetingList):
            list = ["Summarize the last meeting", "Which tasks are still open?"]
        case .some(.topic), .none:
            list = ["What did we decide?", "Which tasks are still open?"]
        }
        if context.overdueActionCount > 0, intent != .some(.tasks) { list.append("What is overdue for me?") }
        let askedKey = asked.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        var result: [String] = []
        for item in list where item.lowercased() != askedKey && seen.insert(item.lowercased()).inserted {
            result.append(item)
        }
        return Array(result.prefix(max(1, limit)))
    }
}

// MARK: - Routing

public enum VidurRoute: Sendable, Equatable {
    case smallTalk(VidurSmallTalkReply)
    case command(VidurCommand)
    /// A request Vidur cannot carry out, or needs more detail for. The text is the reply.
    case reply(String)
    /// A question about the user's meetings.
    case question(String)
}

/// Decides what a message is: small talk, a command, or a question for the meetings.
public enum VidurConversationRouter {
    public static func route(_ text: String, context: VidurAssistantContext, seed: Int = 0,
                             now: Date = Date(), calendar: Calendar = .current) -> VidurRoute {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .question(trimmed) }
        if let reply = VidurSmallTalk.reply(to: trimmed, context: context, seed: seed, now: now, calendar: calendar) {
            return .smallTalk(reply)
        }
        switch VidurCommandParser.parse(trimmed, now: now, calendar: calendar) {
        case .command(let command): return .command(command)
        case .reply(let text): return .reply(text)
        case .none: break
        }
        let stripped = VidurWakeWord.stripLeading(trimmed)
        return .question(stripped.isEmpty ? trimmed : stripped)
    }
}

// MARK: - Spoken text

/// Turns an answer into something that sounds natural when read aloud: no bullets, symbols or
/// timecodes, and at most a few sentences.
public enum VidurSpokenText {
    public static func make(from text: String, maxCharacters: Int = 420) -> String {
        var spoken = text
        for symbol in ["**", "__", "`", "#"] { spoken = spoken.replacingOccurrences(of: symbol, with: "") }
        spoken = VidurRx.replacing(#"(?m)^\s*(?:[\x{2022}\x{25CF}\x{2013}\x{2014}*-]|\d+[.)])\s+"#, in: spoken, with: "")
        spoken = VidurRx.replacing(#"\(?\b\d{1,2}:\d{2}(?::\d{2})?\b\)?"#, in: spoken, with: " ")
        spoken = VidurRx.replacing(#"\s*\n+\s*"#, in: spoken, with: ". ")
        spoken = spoken.replacingOccurrences(of: "\u{2026}", with: ".")
        spoken = VidurRx.replacing(#"([.!?])(?:\s*\.)+"#, in: spoken, with: "$1")
        spoken = VidurRx.replacing(#"\s+"#, in: spoken, with: " ")
        spoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard spoken.count > maxCharacters else { return spoken }
        var kept = ""
        var sentence = ""
        for character in spoken {
            sentence.append(character)
            if ".!?".contains(character) {
                if kept.count + sentence.count > maxCharacters { break }
                kept += sentence
                sentence = ""
            }
        }
        if kept.isEmpty {
            kept = String(spoken.prefix(maxCharacters))
            if let space = kept.lastIndex(of: " ") { kept = String(kept[kept.startIndex..<space]) }
            kept += "."
        }
        return kept.trimmingCharacters(in: .whitespaces) + " The rest is on screen."
    }
}

// MARK: - Yes and no

/// Understands "yes", "confirm", "haan", "no", "cancel" and "nahi" when Vidur is waiting for a decision.
public enum VidurConfirmation {
    private static let yes: Set<String> = [
        "yes", "yeah", "yep", "yup", "sure", "ok", "okay", "confirm", "confirmed", "do it", "go ahead", "schedule it",
        "add it", "save it", "correct", "right", "haan", "han", "ha", "kar do", "kardo", "theek hai", "thik hai",
        "yes please", "please do", "sounds good", "looks good", "that is right", "thats right"
    ]
    private static let no: Set<String> = [
        "no", "nope", "nah", "cancel", "stop", "nahi", "nahin", "mat karo", "dont", "do not", "never mind",
        "nevermind", "leave it", "forget it", "no thanks", "no thank you"
    ]

    /// True for yes, false for no, nil when the text is neither.
    public static func answer(to text: String) -> Bool? {
        let normalised = VidurSmallTalk.normalise(text)
        let words = normalised.split(separator: " ").map(String.init)
        guard !words.isEmpty, words.count <= 5 else { return nil }
        if yes.contains(normalised) { return true }
        if no.contains(normalised) { return false }
        guard words.count <= 4, let first = words.first else { return nil }
        if ["yes", "yeah", "yep", "yup", "haan", "confirm"].contains(first) { return true }
        if ["no", "nope", "nahi", "nahin", "cancel"].contains(first) { return false }
        return nil
    }
}