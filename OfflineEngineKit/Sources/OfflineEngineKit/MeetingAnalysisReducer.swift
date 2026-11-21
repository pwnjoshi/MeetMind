import Foundation

/// A cleaned, evidence-preserving representation used by the app's minutes,
/// task review, export and Vidur surfaces.
public struct ReducedMeetingAnalysis: Sendable {
    public let executiveSummary: String
    public let discussion: [SupportedPoint]
    public let decisions: [SupportedPoint]
    public let tasks: [SuggestedTask]
    public let checkpoint: MeetingAnalysisCheckpoint
}

/// Converts independent chunk outputs into one coherent meeting record. It does
/// not invent facts: every retained or supplemented item carries an exact quote
/// from a transcript turn and remains subject to user review.
public enum MeetingAnalysisReducer {
    public static func reduce(_ checkpoint: MeetingAnalysisCheckpoint) -> ReducedMeetingAnalysis {
        let generatedDiscussion = checkpoint.analysis.flatMap(\.discussion)
        let generatedDecisions = checkpoint.analysis.flatMap(\.decisions)
        let generatedTasks = checkpoint.analysis.flatMap(\.tasks)

        var decisions = deduplicatePoints(generatedDecisions.compactMap(cleanedPoint))
        decisions = mergePoints(decisions, with: explicitDecisions(in: checkpoint.turns))

        var discussion = deduplicatePoints(generatedDiscussion.compactMap(cleanedPoint))
        discussion = mergePoints(discussion, with: unresolvedOutcomes(in: checkpoint.turns))
        discussion.removeAll { item in decisions.contains { nearDuplicate(item.text, $0.text) } }
        discussion = Array(discussion.prefix(16))
        decisions = Array(decisions.prefix(12))

        var tasks = deduplicateTasks(generatedTasks.compactMap(cleanedTask))
        tasks = mergeTasks(tasks, with: explicitCommitments(in: checkpoint.turns))
        tasks = Array(tasks.prefix(24))

        let executiveSummary = composeExecutiveSummary(discussion: discussion, decisions: decisions)
        let merged = LocalAnalysisResult(discussion: discussion, decisions: decisions, tasks: tasks)
        var normalized = checkpoint
        normalized.analysis = [merged]
        normalized.analyzedChunks = 1
        normalized.chunkTurnIDs = [checkpoint.turns.map(\.id)]
        return ReducedMeetingAnalysis(executiveSummary: executiveSummary, discussion: discussion,
                                      decisions: decisions, tasks: tasks, checkpoint: normalized)
    }

    private static func cleanedPoint(_ point: SupportedPoint) -> SupportedPoint? {
        let text = polished(point.text)
        guard isSubstantive(text), !point.evidence.isEmpty else { return nil }
        return SupportedPoint(text: text, evidence: uniqueEvidence(point.evidence))
    }

    private static func cleanedTask(_ task: SuggestedTask) -> SuggestedTask? {
        let title = polishedTask(task.title)
        guard isSubstantive(title), !task.evidence.isEmpty else { return nil }
        return SuggestedTask(title: title, category: task.category, owner: cleanedOptional(task.owner),
                             deadlineText: cleanedOptional(task.deadlineText), priority: task.priority,
                             evidence: uniqueEvidence(task.evidence))
    }

    private static func composeExecutiveSummary(discussion: [SupportedPoint], decisions: [SupportedPoint]) -> String {
        var sentences: [String] = []
        if let first = discussion.first { sentences.append(first.text) }
        if decisions.isEmpty {
            sentences.append(contentsOf: discussion.dropFirst().prefix(2).map(\.text))
        } else {
            sentences.append(contentsOf: decisions.prefix(2).map(\.text))
        }
        return sentences.isEmpty ? "No substantive meeting outcomes were identified." : sentences.joined(separator: " ")
    }

    private static func deduplicatePoints(_ values: [SupportedPoint]) -> [SupportedPoint] {
        var result: [SupportedPoint] = []
        for value in values {
            if let index = result.firstIndex(where: { nearDuplicate($0.text, value.text) }) {
                let preferred = value.text.count > result[index].text.count ? value.text : result[index].text
                result[index] = SupportedPoint(text: preferred,
                    evidence: uniqueEvidence(result[index].evidence + value.evidence))
            } else {
                result.append(value)
            }
        }
        return result
    }

    private static func mergePoints(_ lhs: [SupportedPoint], with rhs: [SupportedPoint]) -> [SupportedPoint] {
        deduplicatePoints(lhs + rhs)
    }

    private static func deduplicateTasks(_ values: [SuggestedTask]) -> [SuggestedTask] {
        var result: [SuggestedTask] = []
        for task in values {
            if let index = result.firstIndex(where: { sameTask($0, task) }) {
                let current = result[index]
                result[index] = SuggestedTask(
                    title: current.title.count >= task.title.count ? current.title : task.title,
                    category: current.category == "Other" ? task.category : current.category,
                    owner: current.owner ?? task.owner,
                    deadlineText: current.deadlineText ?? task.deadlineText,
                    priority: current.priority ?? task.priority,
                    evidence: uniqueEvidence(current.evidence + task.evidence)
                )
            } else {
                result.append(task)
            }
        }
        return result
    }

    private static func mergeTasks(_ lhs: [SuggestedTask], with rhs: [SuggestedTask]) -> [SuggestedTask] {
        deduplicateTasks(lhs + rhs)
    }

    /// Supplements only explicit, grammatically definite commitments. The result
    /// remains a suggestion that the user must accept before it becomes a task.
    private static func explicitCommitments(in turns: [AnalysisTurn]) -> [SuggestedTask] {
        let name = #"([A-Z][\p{L}'-]+(?:\s+[A-Z][\p{L}'-]+)?)"#
        let deadline = #"(today|tomorrow|by\s+(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)|on\s+(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)|next\s+week)"#
        let pattern = #"(?i)\b"# + name + #"\s+will\s+(?!not\b)(.+?)(?:\s+"# + deadline + #")?[.!?]?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var tasks: [SuggestedTask] = []
        for turn in turns {
            for sentence in sentences(in: turn.text) {
                let lower = sentence.lowercased()
                guard !containsNegatedCommitment(lower) else { continue }
                let range = NSRange(sentence.startIndex..<sentence.endIndex, in: sentence)
                guard let match = regex.firstMatch(in: sentence, range: range), match.numberOfRanges >= 3,
                      let ownerRange = Range(match.range(at: 1), in: sentence),
                      let actionRange = Range(match.range(at: 2), in: sentence) else { continue }
                let owner = String(sentence[ownerRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let nonNames = Set(["i", "we", "you", "they", "he", "she", "it", "team", "the team", "speaker"])
                guard !nonNames.contains(owner.lowercased()) else { continue }
                var action = String(sentence[actionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                var deadlineText: String?
                if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound,
                   let deadlineRange = Range(match.range(at: 3), in: sentence) {
                    deadlineText = String(sentence[deadlineRange])
                    if let deadlineText, action.lowercased().hasSuffix(deadlineText.lowercased()) {
                        action = String(action.dropLast(deadlineText.count)).trimmingCharacters(in: .whitespaces)
                    }
                }
                let title = polishedTask(action)
                guard isSubstantive(title), actionHasVerb(title) else { continue }
                let evidence = SourceEvidence(turnID: turn.id, quote: sentence)
                tasks.append(SuggestedTask(title: title, category: category(for: title), owner: owner,
                                           deadlineText: deadlineText, priority: nil, evidence: [evidence]))
            }
        }
        return tasks
    }

    private static func explicitDecisions(in turns: [AnalysisTurn]) -> [SupportedPoint] {
        let markers = ["we decided", "we agreed", "was approved", "is approved", "was rejected",
                       "is rejected", "we deferred", "decision is", "the decision was"]
        return groundedSentences(in: turns) { sentence in
            let lower = sentence.lowercased()
            return markers.contains(where: lower.contains) && !containsNegation(lower)
        }
    }

    private static func unresolvedOutcomes(in turns: [AnalysisTurn]) -> [SupportedPoint] {
        let markers = ["not decided", "no decision", "remains open", "still open", "pending approval",
                       "not yet agreed", "deferred until", "needs further discussion"]
        return groundedSentences(in: turns) { sentence in
            let lower = sentence.lowercased()
            return markers.contains(where: lower.contains)
        }
    }

    private static func groundedSentences(in turns: [AnalysisTurn], matching predicate: (String) -> Bool) -> [SupportedPoint] {
        turns.flatMap { turn in
            sentences(in: turn.text).compactMap { sentence in
                guard predicate(sentence), isSubstantive(sentence) else { return nil }
                return SupportedPoint(text: polished(sentence),
                                      evidence: [SourceEvidence(turnID: turn.id, quote: sentence)])
            }
        }
    }

    private static func sentences(in text: String) -> [String] {
        var values: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .substringNotRequired]) {
            _, range, _, _ in
            let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { values.append(value) }
        }
        if values.isEmpty {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { values = [value] }
        }
        return values
    }

    private static func polished(_ value: String) -> String {
        var text = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: #"^(?:[-•*]|\d+[.)])\s*"#, with: "", options: .regularExpression)
        guard let last = text.last else { return text }
        if !".!?".contains(last) { text.append(".") }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func polishedTask(_ value: String) -> String {
        var text = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        text = text.replacingOccurrences(of: #"^(?:to|please)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        guard !text.isEmpty else { return text }
        text = text.prefix(1).uppercased() + text.dropFirst()
        return text
    }

    private static func cleanedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func uniqueEvidence(_ values: [SourceEvidence]) -> [SourceEvidence] {
        var seen = Set<String>()
        return values.filter { seen.insert("\($0.turnID)\u{0}\($0.quote)").inserted }
    }

    private static func nearDuplicate(_ lhs: String, _ rhs: String) -> Bool {
        let left = meaningfulTokens(lhs), right = meaningfulTokens(rhs)
        guard !left.isEmpty, !right.isEmpty else { return normalize(lhs) == normalize(rhs) }
        let intersection = left.intersection(right).count
        let union = left.union(right).count
        return Double(intersection) / Double(max(1, union)) >= 0.68
            || (min(left.count, right.count) >= 4 && (left.isSubset(of: right) || right.isSubset(of: left)))
    }

    private static func sameTask(_ lhs: SuggestedTask, _ rhs: SuggestedTask) -> Bool {
        let ownersMatch = normalize(lhs.owner ?? "") == normalize(rhs.owner ?? "")
            || lhs.owner == nil || rhs.owner == nil
        return ownersMatch && nearDuplicate(lhs.title, rhs.title)
    }

    private static func meaningfulTokens(_ text: String) -> Set<String> {
        let stop = Set(["the", "a", "an", "and", "or", "to", "of", "for", "in", "on", "at", "is", "was",
                        "were", "be", "been", "that", "this", "it", "with", "as", "by", "will", "would",
                        "meeting", "team", "discussed", "discussion"])
        return Set(normalize(text).split(separator: " ").map(String.init).filter { $0.count > 1 && !stop.contains($0) })
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func isSubstantive(_ text: String) -> Bool {
        let normalized = normalize(text)
        let emptyPhrases = ["", "okay", "ok", "yes", "no", "thanks", "thank you", "hello", "hi", "good morning"]
        return text.count >= 8 && !emptyPhrases.contains(normalized)
    }

    private static func containsNegation(_ text: String) -> Bool {
        ["not decided", "did not decide", "not agreed", "was not approved", "wasn't approved",
         "not rejected", "no decision"].contains(where: text.contains)
    }

    private static func containsNegatedCommitment(_ text: String) -> Bool {
        [" will not ", " won't ", " do not ", " don't ", " cancelled", " canceled", " already completed"]
            .contains(where: text.contains)
    }

    private static func actionHasVerb(_ text: String) -> Bool {
        let verbs = ["send", "share", "prepare", "create", "update", "review", "approve", "confirm", "schedule",
                     "contact", "research", "check", "provide", "complete", "submit", "draft", "follow", "call",
                     "email", "deliver", "finalize", "investigate", "resolve", "book", "organize", "arrange"]
        let words = meaningfulTokens(text)
        return verbs.contains { verb in words.contains(verb) || words.contains(verb + "s") || words.contains(verb + "ing") }
    }

    private static func category(for title: String) -> String {
        let lower = title.lowercased()
        if ["research", "investigate", "check"].contains(where: lower.contains) { return "Research" }
        if ["review", "approve"].contains(where: lower.contains) { return "Review/Approve" }
        if ["create", "update", "prepare", "draft"].contains(where: lower.contains) { return "Create/Update" }
        if ["schedule", "contact", "call", "email", "organize", "arrange"].contains(where: lower.contains) { return "Coordination" }
        return "Follow-up"
    }
}
