import Foundation

/// Decides which questions go to the model and which are answered from the saved minutes.
public enum VidurRagRouting {
    private static let openEndedPatterns: [String] = [
        #"^\s*(?:and\s+)?how\s+(?:did|was|were|is|are|do|does|has|have|come)\b"#,
        #"\b(?:main|key|biggest|top|major)\s+(?:concerns?|points?|issues?|topics?|takeaways?|risks?|themes?|objections?)\b"#,
        #"\b(?:concerns?|opinions?|thoughts?|feedback|sentiment|mood|vibe|pros and cons|trade ?offs?)\b"#,
        #"\b(?:tell|walk|take)\s+me\s+(?:about|through|more)\b"#,
        #"\bwhat\s+(?:happened|went|was\s+discussed|did\s+(?:they|everyone|people)\s+(?:say|think|feel))\b"#,
        #"\b(?:talk(?:ed)?|discuss(?:ed)?|spoke|said)\s+about\b"#,
        #"\b(?:kya\s+baat|kya\s+charcha|kaisa\s+raha|kaisi\s+rahi|kaise\s+gayi|kaise\s+gaya)\b"#,
        #"\bsummar(?:y|ise|ize)\s+(?:the\s+)?(?:discussion|debate|conversation)\b"#
    ]

    /// True for questions whose answer is an explanation or an impression, not a single saved fact.
    public static func isOpenEnded(_ question: String) -> Bool {
        let text = question.lowercased()
        return openEndedPatterns.contains { VidurRx.matches($0, text) }
    }

    private static let ownerPatterns: [String] = [
        #"\bwho\s+(?:owns?|owned)\b"#,
        #"\bwho(?:\s+is|\s+are)?\s+(?:responsible|handling|in\s+charge|incharge|accountable|taking\s+care)\b"#,
        #"\bwhos\s+(?:responsible|handling|in\s+charge|incharge|accountable)\b"#,
        #"\bwhose\s+(?:task|job|responsibility|action|duty|work)\b"#,
        #"\bwho\s+(?:will|would|is\s+going\s+to)\s+(?:do|handle|take|own|be\s+(?:doing|handling|responsible))\b"#,
        #"\bwho\s+(?:has|have|needs?|must)\s+to\b"#,
        #"\bkaun\s+(?:karega|karegi|karenge)\b"#
    ]

    /// "Who owns the presentation?", "and who is responsible for it?", "whose task is the agenda?", "who will do the
    /// quote?", "who has to send it?". Answered from saved actions and from requests in the transcript before any model.
    public static func isOwnerQuestion(_ question: String) -> Bool {
        let text = question.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "'", with: "")
        return ownerPatterns.contains { VidurRx.matches($0, text) }
    }

    private static let outcomePatterns: [String] = [
        #"^\s*(?:and\s+|so\s+)?how\s+(?:did|was|were|is|has|have)\b"#,
        #"\bwhat\s+(?:happened|became)\b"#,
        #"\bwhat\s+(?:is|was)\s+the\s+(?:outcome|status|result)\b"#,
        #"\bwhat\s+went\s+(?:on|down)\b"#,
        #"\b(?:kya\s+hua|kaisa\s+raha|kaisi\s+rahi)\b"#
    ]

    private static let acrossPatterns: [String] = [
        #"\bmeetings\b"#,
        #"\b(?:all|every|each|any)\s+(?:of\s+)?(?:the\s+|my\s+|our\s+)?meeting\b"#,
        #"\b(?:over\s+time|so\s+far|overall|across|history|timeline|evolve|evolved|changed|trend)\b"#,
        #"\b(?:sab|sabhi)\s+meetings?\b"#
    ]

    /// "How did the budget discussion go?", "what happened with the vendor?": one meeting's story, not a blend.
    public static func isOutcomeQuestion(_ question: String) -> Bool {
        let text = question.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        return outcomePatterns.contains { VidurRx.matches($0, text) }
    }

    /// True when the user asks about several meetings at once ("across all meetings", "over time", "in the meetings").
    public static func asksAcrossMeetings(_ question: String) -> Bool {
        let text = question.lowercased()
        return acrossPatterns.contains { VidurRx.matches($0, text) }
    }

    /// A reply is rewritten only when it is short enough for the model to keep every fact. Long lists stay
    /// as the saved minutes wrote them.
    public static func canRephrase(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline).count
        return !text.isEmpty && text.count <= 380 && lines <= 5
    }
}

extension VidurRagGuard {
    /// True when a rewritten reply still holds every date or number above ten, and every name, of the
    /// verified answer it was written from.
    public static func keepsFacts(answer: String, verified: String) -> Bool {
        let wanted = unsupportedTerms(in: verified, evidence: [answer])
        return wanted.isEmpty
    }
}
