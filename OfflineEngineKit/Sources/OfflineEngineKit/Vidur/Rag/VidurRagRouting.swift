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
