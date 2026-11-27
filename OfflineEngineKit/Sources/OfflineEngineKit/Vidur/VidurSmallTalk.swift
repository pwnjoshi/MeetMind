import Foundation

public enum VidurSmallTalkIntent: String, Sendable, Equatable {
    case greeting, howAreYou, thanks, whoAreYou, capabilities, goodbye, acknowledge, compliment, apology, presence
}

public struct VidurSmallTalkReply: Sendable, Equatable {
    public let intent: VidurSmallTalkIntent
    public let text: String
    /// Two or three relevant things to ask or do next, from the user's real data.
    public let suggestions: [String]

    public init(intent: VidurSmallTalkIntent, text: String, suggestions: [String]) {
        self.intent = intent
        self.text = text
        self.suggestions = suggestions
    }
}

/// Warm, short, instant replies to "hi", "thanks", "who are you" and similar. No model is involved,
/// so they are never slow and never invent anything. `seed` picks between wordings so Vidur does not
/// repeat itself; the same seed always gives the same reply.
public enum VidurSmallTalk {
    private static let namePattern = #"\bvi+d+h?(?:u|oo|a|o|e)+r\b"#

    static func normalise(_ text: String) -> String {
        var lowered = text.lowercased()
        lowered = lowered.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
        lowered = VidurRx.replacing(#"[^\p{L}\p{M}\p{N}\s]"#, in: lowered, with: " ")
        return lowered.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    public static func intent(of text: String) -> VidurSmallTalkIntent? {
        let normalised = normalise(text)
        guard !normalised.isEmpty, normalised.split(separator: " ").count <= 8 else { return nil }
        // "hey vidur" and "hi there" are greetings once the name and filler words are gone.
        let core = VidurRx.tidy(VidurRx.replacing(namePattern + #"|\b(?:there|buddy|friend|yaar|dost|bro|please|pls)\b"#,
                                                  in: normalised))
        let words = normalised.split(separator: " ").count

        if VidurRx.matches(#"\b(?:how\s+are\s+(?:you|u)|how\s+r\s+u|how\s+is\s+it\s+going|hows\s+it\s+going|how\s+you\s+doing|how\s+do\s+you\s+do|kaise\s+ho|kaise\s+hain|kya\s+haal|kya\s+hal|whats\s+up|wassup)\b"#, normalised)
            || core == "sup" {
            return .howAreYou
        }
        if words <= 6, VidurRx.matches(#"\b(?:thanks|thank\s+you|thank\s+u|thx|tysm|ty|shukriya|dhanyavaad|dhanyawad|dhanyavad|much\s+appreciated|appreciate\s+it|cheers)\b"#, normalised) {
            return .thanks
        }
        if VidurRx.matches(#"\b(?:who\s+are\s+(?:you|u)|who\s+r\s+u|what\s+are\s+you|who\s+is\s+vidur|what\s+is\s+vidur|whats\s+your\s+name|what\s+is\s+your\s+name|your\s+name|introduce\s+yourself|tell\s+me\s+about\s+yourself|tum\s+kaun\s+ho|aap\s+kaun\s+(?:hain|ho)|tumhara\s+naam|apna\s+naam|who\s+made\s+you)\b"#, normalised) {
            return .whoAreYou
        }
        if VidurRx.matches(#"\b(?:what\s+can\s+(?:you|u)\s+do|what\s+do\s+(?:you|u)\s+do|how\s+can\s+(?:you|u)\s+help|how\s+do\s+you\s+work|how\s+does\s+this\s+work|what\s+can\s+i\s+ask|what\s+can\s+i\s+say|what\s+can\s+i\s+do|your\s+(?:features|capabilities)|what\s+are\s+your\s+(?:features|capabilities)|kya\s+kar\s+sakte\s+ho|kya\s+kar\s+sakta\s+hai|tum\s+kya\s+kar|aap\s+kya\s+kar)\b"#, normalised)
            || VidurRx.matches(#"^(?:help|help\s+me|can\s+you\s+help(?:\s+me)?|i\s+need\s+help|how\s+to\s+use)$"#, core) {
            return .capabilities
        }
        if words <= 4,
           VidurRx.matches(#"^(?:bye+|good\s*bye|good\s*night|see\s+(?:you|ya)|cya|talk\s+later|later|alvida|ok\s+bye|okay\s+bye|chalo\s+bye|tata|take\s+care)(?:\s+\w+)?$"#, core) {
            return .goodbye
        }
        if VidurRx.matches(#"^(?:h+i+|hey+|hello+|hallo|hiya|heya|yo|hola|namaste|namaskar|howdy|good\s+(?:morning|afternoon|evening|day)|gm|ram\s+ram|sat\s+sri\s+akal|salaam|salam)$"#, core) {
            return .greeting
        }
        if VidurRx.matches(#"^(?:ok|okay|k|kk|cool|great|nice|got\s+it|alright|sure|fine|perfect|awesome|good|sounds\s+good|theek\s+hai|thik\s+hai|accha|achha|acha|hmm+|i\s+see|understood)$"#, core) {
            return .acknowledge
        }
        if VidurRx.matches(#"\b(?:good\s+job|well\s+done|nice\s+work|great\s+job|love\s+it|you\s+are\s+(?:great|awesome|amazing|smart|good|the\s+best)|youre\s+(?:great|awesome|amazing|smart|good|the\s+best)|shabash|bahut\s+accha)\b"#, normalised) {
            return .compliment
        }
        if VidurRx.matches(#"^(?:sorry|my\s+bad|oops|sorry\s+about\s+that)$"#, core) { return .apology }
        if VidurRx.matches(#"^(?:are\s+you\s+there|you\s+there|can\s+you\s+hear\s+me|test|testing|anyone\s+there|r\s+u\s+there|hear\s+me)$"#, core) {
            return .presence
        }
        return nil
    }

    public static func reply(to text: String, context: VidurAssistantContext, seed: Int = 0,
                             now: Date = Date(), calendar: Calendar = .current) -> VidurSmallTalkReply? {
        guard let intent = intent(of: text) else { return nil }
        let normalised = normalise(text)
        let hinglish = VidurRx.matches(#"\b(?:namaste|namaskar|kaise|kya|shukriya|dhanyavaad|dhanyawad|dhanyavad|kaun|theek|thik|accha|achha|acha|alvida|aap|tum|bahut|shabash|haal|hal)\b"#, normalised)
        let suggestions = VidurProactive.suggestions(for: context, limit: 3, now: now, calendar: calendar)
        let name = context.firstName

        func pick(_ options: [String]) -> String { options[abs(seed) % options.count] }

        switch intent {
        case .greeting:
            var opener = pick(["Hi", "Hello", "Hey"])
            if hinglish { opener = "Namaste" }
            if let range = normalised.range(of: "good (morning|afternoon|evening)", options: .regularExpression) {
                opener = String(normalised[range]).prefix(1).uppercased() + String(normalised[range]).dropFirst()
            }
            let greeting = name.map { "\(opener), \($0)!" } ?? "\(opener)!"
            return VidurSmallTalkReply(intent: intent, text: greeting + " " + statusLine(context, now: now, calendar: calendar, seed: seed),
                                       suggestions: suggestions)
        case .howAreYou:
            let fine = hinglish
                ? pick(["Main theek hoon, shukriya!", "Sab badhiya, aap batao!"])
                : pick(["I\u{2019}m doing well, thanks for asking.", "All good here, thanks!", "Doing great, thank you."])
            return VidurSmallTalkReply(intent: intent,
                                       text: fine + " " + statusLine(context, now: now, calendar: calendar, seed: seed),
                                       suggestions: suggestions)
        case .thanks:
            let text = hinglish
                ? pick(["Koi baat nahi! Aur kuch?", "Bilkul, kabhi bhi puchiye."])
                : pick(["Anytime. Anything else?", "Happy to help.", "You\u{2019}re welcome. Want to look at anything else?", "Glad that helped."])
            return VidurSmallTalkReply(intent: intent, text: text, suggestions: Array(suggestions.prefix(2)))
        case .whoAreYou:
            let intro = hinglish ? "Main Vidur hoon, Manent ka meeting assistant." : "I\u{2019}m Vidur, the assistant inside Manent."
            let text = intro + " I answer from your saved meetings, and I can schedule meetings, add actions or start a recording for you. "
                + "I run on this iPhone, so your audio and notes stay private. I\u{2019}m a small on-device model, so I stick to what is in your meetings."
            return VidurSmallTalkReply(intent: intent, text: text, suggestions: capabilityChips(context, now: now, calendar: calendar))
        case .capabilities:
            let text = "Ask me about your meetings, like what was decided, who owns a task or what is overdue. "
                + "I can also schedule a meeting, add an action, mark one done, open a meeting, star one or start a recording. "
                + "Just say it in English or Hinglish. I\u{2019}ll show you what I understood and confirm before I change anything."
            return VidurSmallTalkReply(intent: intent, text: text, suggestions: capabilityChips(context, now: now, calendar: calendar))
        case .goodbye:
            let text = hinglish ? "Phir milte hain! Zaroorat ho to bulaiye." : pick(["Bye! I\u{2019}m here whenever you need me.", "See you soon.", "Take care. I\u{2019}m here when you need me."])
            return VidurSmallTalkReply(intent: intent, text: text, suggestions: [])
        case .acknowledge:
            let text = pick(["Okay. Ask me whenever you\u{2019}re ready.", "Sure. What would you like to look at next?", "Got it."])
            return VidurSmallTalkReply(intent: intent, text: text, suggestions: Array(suggestions.prefix(2)))
        case .compliment:
            let text = pick(["Thank you, that\u{2019}s kind. What shall we look at next?", "Thanks! Happy to help."])
            return VidurSmallTalkReply(intent: intent, text: text, suggestions: Array(suggestions.prefix(2)))
        case .apology:
            return VidurSmallTalkReply(intent: intent, text: "No problem at all.", suggestions: [])
        case .presence:
            return VidurSmallTalkReply(intent: intent, text: pick(["I\u{2019}m here. Go ahead.", "Yes, I can hear you. What do you need?"]),
                                       suggestions: [])
        }
    }

    /// One or two sentences about the user's day, using only real data.
    static func statusLine(_ context: VidurAssistantContext, now: Date, calendar: Calendar, seed: Int) -> String {
        if context.isRecording {
            return "I\u{2019}ll stay quiet while you record. Ask me anything once it\u{2019}s done."
        }
        var parts: [String] = []
        var closing: String?
        if let first = context.upcomingToday.first {
            let time = VidurProactive.clock(first.start, calendar: calendar)
            if context.upcomingToday.count == 1 {
                parts.append("You have one meeting left today: \(first.title) at \(time).")
            } else {
                parts.append("You have \(context.upcomingToday.count) meetings left today. Next is \(first.title) at \(time).")
            }
            if context.nextMeetingHasHistory, first.title.count <= 40 {
                closing = "Want a quick recap of the last \(first.title)?"
            }
        } else if let next = context.nextMeeting {
            let day = VidurProactive.dayName(next.start, now: now, calendar: calendar)
            parts.append("Your next meeting is \(next.title) \(day) at \(VidurProactive.clock(next.start, calendar: calendar)).")
            if context.nextMeetingHasHistory, next.title.count <= 40 {
                closing = "Want a quick recap of the last \(next.title)?"
            }
        }
        if context.overdueActionCount > 0 {
            let count = context.overdueActionCount
            let noun = count == 1 ? "action" : "actions"
            parts.append(parts.isEmpty ? "You have \(count) overdue \(noun)." : "You also have \(count) overdue \(noun).")
        } else if context.unreviewedSuggestionCount > 0, parts.isEmpty {
            let count = context.unreviewedSuggestionCount
            parts.append("I found \(count) suggested \(count == 1 ? "action" : "actions") from your recordings that need a look.")
        }
        if parts.isEmpty {
            if context.lastMeetingHasMinutes, let last = context.lastMeetingTitle, last.count <= 40 {
                return "Want a recap of \(last)?"
            }
            if !context.hasAnyMeetings {
                return "Once you record or schedule a meeting, I can answer questions about it. You can also tell me to schedule one."
            }
            return "What would you like to know?"
        }
        if let closing { parts.append(closing) }
        return parts.prefix(3).joined(separator: " ")
    }

    private static func capabilityChips(_ context: VidurAssistantContext, now: Date, calendar: Calendar) -> [String] {
        let data = VidurProactive.suggestions(for: context, limit: 4, now: now, calendar: calendar)
            .first { !$0.hasPrefix("Schedule") }
        var chips: [String] = []
        if let data { chips.append(data) }
        chips.append("Schedule a meeting tomorrow at 4")
        chips.append("Remind me to send the deck by Friday")
        return chips
    }
}
