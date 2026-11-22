import Foundation

/// A cleaned, evidence-preserving representation used by the app's minutes,
/// task review, export and Vidur surfaces.
public struct ReducedMeetingAnalysis: Sendable {
    public let executiveSummary: String
    public let discussion: [SupportedPoint]
    public let decisions: [SupportedPoint]
    /// Undecided, hypothetical or still-open matters. Never mixed into decisions.
    public let openIssues: [SupportedPoint]
    public let tasks: [SuggestedTask]
    public let checkpoint: MeetingAnalysisCheckpoint
    /// Topics the meeting covered, in order of appearance, derived from agenda statements,
    /// topic shifts and open issues. Short Title-case phrases for an editable agenda.
    public let agendaTopics: [String]
    /// Document-grade minutes: topics with outcomes, formal resolutions, contextual actions,
    /// formal open issues, suggested attendees and an English executive summary.
    public let minutes: MinutesContent
}

/// Converts independent chunk outputs into one coherent meeting record. It does
/// not invent facts: every retained or supplemented item carries an exact quote
/// from a transcript turn and remains subject to user review.
public enum MeetingAnalysisReducer {
    /// - Parameters:
    ///   - participants: Named attendees. Only these names (or a name written in the
    ///     sentence itself) can become a task owner.
    ///   - speakerNames: Maps a transcript speaker label to the attendee the user named,
    ///     so first-person commitments ("I will ...") can receive an owner.
    public static func reduce(_ checkpoint: MeetingAnalysisCheckpoint, participants: [String] = [],
                              speakerNames: [String: String] = [:], meetingDate: Date? = nil,
                              timeZone: TimeZone = TimeZone.current) -> ReducedMeetingAnalysis {
        // A vocative ("Pawan, ...") names the next voice; a self-introduction names the current one.
        let speakerNames = SpeakerNameInference.infer(turns: checkpoint.turns, participants: participants,
                                                      speakerNames: speakerNames)
        let context = ExtractionContext(participants: participants, speakerNames: speakerNames)
        let grounding = Grounding(turns: checkpoint.turns)
        let hindi = HindiMeetingExtractor.analyze(checkpoint.turns, context: context)
        let generatedDiscussion = checkpoint.analysis.flatMap(\.discussion)
        let generatedDecisions = checkpoint.analysis.flatMap(\.decisions)
        let generatedOpenIssues = checkpoint.analysis.flatMap(\.openIssues)
        let generatedTasks = checkpoint.analysis.flatMap(\.tasks)

        // A sentence that says something is undecided can never support a
        // decision. Model output grounded only in such a sentence is demoted.
        var openCandidates = generatedOpenIssues.compactMap(cleanedPoint)
        // Deterministic requests and commitments found in the transcript itself.
        let floorTasks = ActionExtractor.tasks(in: checkpoint.turns, context: context, hindi: hindi)
        let requestSentences = Set(floorTasks.compactMap { $0.evidence.first }.map { normalize($0.quote) })
        var decisionCandidates: [SupportedPoint] = []
        for point in generatedDecisions.compactMap(cleanedPoint) {
            if isUndecidedPoint(point, grounding) {
                openCandidates.append(point)
            } else if isRequestOnly(point, grounding, requestSentences) {
                // A "decision" whose only support is an assignment sentence is a task.
                continue
            } else {
                decisionCandidates.append(point)
            }
        }
        var discussionCandidates: [SupportedPoint] = []
        for point in generatedDiscussion.compactMap(cleanedPoint) {
            if isUndecidedPoint(point, grounding) { openCandidates.append(point) } else { discussionCandidates.append(point) }
        }

        var decisions = deduplicatePoints(decisionCandidates)
        decisions = mergePoints(decisions, with: explicitDecisions(in: checkpoint.turns, hindi: hindi) + hindiDecisionPoints(hindi))
        decisions.removeAll { isContentlessDecision($0.text) }

        var openIssues = deduplicateOpenIssues(openCandidates + unresolvedOutcomes(in: checkpoint.turns, hindi: hindi) + hindiOpenPoints(hindi), grounding)
        decisions.removeAll { decision in
            openIssues.contains { nearDuplicate(decision.text, $0.text) || sharesFocus(decision, $0, grounding) }
        }

        var discussion = deduplicatePoints(discussionCandidates)
        discussion.removeAll { item in
            decisions.contains { nearDuplicate(item.text, $0.text) }
                || openIssues.contains { nearDuplicate(item.text, $0.text) || sharesFocus(item, $0, grounding) }
        }
        discussion = Array(discussion.prefix(16))
        decisions = Array(decisions.prefix(12))
        openIssues = Array(openIssues.prefix(12))

        let speakerLabels = Set(checkpoint.turns.compactMap(\.speaker).map { normalize($0) })
        var tasks = deduplicateTasks(generatedTasks.compactMap(cleanedTask).map {
            withResolvedOwner($0, speakerLabels: speakerLabels, speakerNames: speakerNames)
        }.filter {
            isGroundedCommitment($0, grounding) && !ActionExtractor.isRefusedRequest(evidence: $0.evidence, in: checkpoint.turns)
        })
        tasks = mergeTasks(tasks, with: floorTasks)
        tasks = Array(tasks.prefix(24))

        var executiveSummary = composeExecutiveSummary(discussion: discussion, decisions: decisions)
        let minutes = MinutesBuilder.build(MinutesBuilder.Input(
            turns: checkpoint.turns, hindi: hindi, decisions: decisions, openIssues: openIssues, tasks: tasks,
            participants: participants, speakerNames: speakerNames, meetingDate: meetingDate, timeZone: timeZone))
        // The deterministic path is primary whenever it found structure, for any script. Model discussion
        // that copies the transcript, or is not English, never reaches Discussion or the summary.
        if hindi.isActive {
            let composed = composeMinutes(hindi, minutes: minutes)
            if !minutes.executiveSummary.isEmpty {
                executiveSummary = minutes.executiveSummary
            } else if HindiText.looksHindi(executiveSummary) {
                executiveSummary = hindiFallbackSummary
            }
            var merged = composed
            for point in discussion where !isTranscriptCopy(point, turns: checkpoint.turns) {
                if !merged.contains(where: { nearDuplicate($0.text, point.text) }) { merged.append(point) }
            }
            discussion = Array(merged.prefix(16))
        }
        // The stored checkpoint carries the document-grade wording: contextual action titles, formal
        // resolutions and formal open issues, each with its original evidence.
        var storedTasks: [SuggestedTask] = []
        for (index, task) in tasks.enumerated() {
            guard index < minutes.actions.count else { storedTasks.append(task); continue }
            let action = minutes.actions[index]
            storedTasks.append(SuggestedTask(title: action.title, category: task.category, owner: action.owner ?? task.owner,
                                             deadlineText: action.deadlineText ?? task.deadlineText, priority: task.priority,
                                             evidence: task.evidence))
        }
        var storedDecisions: [SupportedPoint] = []
        for (index, point) in decisions.enumerated() {
            let formal = index < minutes.resolutions.count ? minutes.resolutions[index].text : point.text
            storedDecisions.append(SupportedPoint(text: formal, evidence: point.evidence))
        }
        var storedOpen: [SupportedPoint] = []
        for (index, point) in openIssues.enumerated() {
            let formal = index < minutes.openIssues.count ? minutes.openIssues[index].text : point.text
            storedOpen.append(SupportedPoint(text: formal, evidence: point.evidence))
        }
        let stored = LocalAnalysisResult(discussion: discussion, decisions: storedDecisions, tasks: storedTasks,
                                         openIssues: storedOpen)
        var normalized = checkpoint
        normalized.analysis = [stored]
        normalized.analyzedChunks = 1
        normalized.chunkTurnIDs = [checkpoint.turns.map(\.id)]
        normalized.minutes = minutes
        return ReducedMeetingAnalysis(executiveSummary: executiveSummary, discussion: discussion,
                                      decisions: decisions, openIssues: openIssues, tasks: tasks,
                                      checkpoint: normalized, agendaTopics: hindi.agendaTopics, minutes: minutes)
    }

    private static let hindiFallbackSummary =
        "This meeting was held in Hindi. Review the decisions, tasks and open issues below, or open the transcript, for details."

    /// Discussion points composed from the deterministic findings. Devanagari and romanized Hindi use the
    /// outcome-oriented composer; other meetings use the rephrased topic bullets.
    private static func composeMinutes(_ hindi: HindiAnalysis, minutes: MinutesContent) -> [SupportedPoint] {
        if !hindi.decisions.isEmpty || !hindi.openIssues.isEmpty || !hindi.opinions.isEmpty {
            return MinutesComposer.discussion(hindi)
        }
        var points: [SupportedPoint] = []
        for topic in minutes.topics where !topic.evidence.isEmpty {
            let text = topic.title + ": " + topic.discussion.joined(separator: " ")
            points.append(SupportedPoint(text: text, evidence: topic.evidence))
        }
        return points
    }

    /// A model point that is not English or that nearly repeats a transcript sentence adds nothing to minutes.
    private static func isTranscriptCopy(_ point: SupportedPoint, turns: [AnalysisTurn]) -> Bool {
        if HindiText.looksHindi(point.text) { return true }
        let tokens = meaningfulTokens(point.text)
        guard !tokens.isEmpty else { return false }
        for turn in turns {
            for sentence in sentences(in: turn.text) {
                let other = meaningfulTokens(sentence)
                if other.isEmpty { continue }
                let overlap = Double(tokens.intersection(other).count) / Double(tokens.count)
                if overlap >= 0.7 { return true }
            }
        }
        return false
    }

    /// "That is final." says a decision was settled but not which one.
    private static func isContentlessDecision(_ text: String) -> Bool {
        let filler: Set<String> = ["final", "decided", "agreed", "finalized", "finalised", "approved", "settled", "done",
                                   "confirmed", "okay", "ok", "yes", "fine", "good", "hai", "hain", "ho", "gaya", "hua", "tay",
                                   "yahi", "yehi", "ye", "yeh", "yah"]
        let tokens = meaningfulTokens(text)
        return tokens.isEmpty || tokens.isSubset(of: filler)
    }

    private static func hindiDecisionPoints(_ hindi: HindiAnalysis) -> [SupportedPoint] {
        hindi.decisions.map { SupportedPoint(text: polished($0.text), evidence: uniqueEvidence($0.evidence)) }
    }

    private static func hindiOpenPoints(_ hindi: HindiAnalysis) -> [SupportedPoint] {
        hindi.openIssues.map { SupportedPoint(text: polished($0.text), evidence: uniqueEvidence($0.evidence)) }
    }

    private static func cleanedPoint(_ point: SupportedPoint) -> SupportedPoint? {
        let text = polished(point.text)
        guard isSubstantive(text), !point.evidence.isEmpty else { return nil }
        return SupportedPoint(text: text, evidence: uniqueEvidence(point.evidence))
    }

    /// A diarization label ("S1", "Speaker 2", "SPEAKER_00") is not a person.
    /// Map it to the attendee the user linked it to, otherwise leave the owner empty.
    static func isSpeakerLabel(_ value: String, knownLabels: Set<String>) -> Bool {
        let normalized = normalize(value)
        if knownLabels.contains(normalized) { return true }
        let compact = normalized.replacingOccurrences(of: " ", with: "")
        return compact.range(of: #"^(s|speaker|spk|speaker_)?\d+$"#, options: .regularExpression) != nil
            || compact.range(of: #"^speaker_?\d+$"#, options: .regularExpression) != nil
            || compact.range(of: #"^s\d+$"#, options: .regularExpression) != nil
    }

    private static func withResolvedOwner(_ task: SuggestedTask, speakerLabels: Set<String>,
                                          speakerNames: [String: String]) -> SuggestedTask {
        guard let owner = task.owner, isSpeakerLabel(owner, knownLabels: speakerLabels) else { return task }
        let mapped = speakerNames.first { normalize($0.key) == normalize(owner) }?.value
        return SuggestedTask(title: task.title, category: task.category, owner: mapped,
                             deadlineText: task.deadlineText, priority: task.priority, evidence: task.evidence)
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
                // Keep the version that carries more actionable detail (owner,
                // deadline); fill any remaining gaps from the other.
                let preferNew = completeness(task) > completeness(current)
                let primary = preferNew ? task : current
                let secondary = preferNew ? current : task
                let equal = completeness(task) == completeness(current)
                result[index] = SuggestedTask(
                    title: equal && secondary.title.count > primary.title.count ? secondary.title : primary.title,
                    category: primary.category == "Other" ? secondary.category : primary.category,
                    owner: primary.owner ?? secondary.owner,
                    deadlineText: primary.deadlineText ?? secondary.deadlineText,
                    priority: primary.priority ?? secondary.priority,
                    evidence: uniqueEvidence(primary.evidence + secondary.evidence)
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

    /// Settled outcomes only: see `DecisionExtractor` for the accepted markers and the
    /// question, conditional, negation and undecided exclusions.
    private static func explicitDecisions(in turns: [AnalysisTurn], hindi: HindiAnalysis) -> [SupportedPoint] {
        turns.flatMap { turn in
            sentences(in: turn.text).flatMap { sentence in
                sentence.components(separatedBy: "\u{0964}").compactMap { piece -> SupportedPoint? in
                    let quote = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !quote.isEmpty, !hindi.isClaimed(quote), DecisionExtractor.isDecision(quote) else { return nil }
                    let text = polished(DecisionExtractor.minuteText(quote))
                    guard isSubstantive(text) else { return nil }
                    return SupportedPoint(text: text, evidence: [SourceEvidence(turnID: turn.id, quote: quote)])
                }
            }
        }
    }

    private static func unresolvedOutcomes(in turns: [AnalysisTurn], hindi: HindiAnalysis) -> [SupportedPoint] {
        let markers = ["not decided", "no decision", "remains open", "still open", "pending approval",
                       "not yet agreed", "deferred until", "needs further discussion"]
        return groundedSentences(in: turns) { sentence in
            if hindi.isClaimed(sentence) { return false }
            let lower = sentence.lowercased()
            return markers.contains(where: lower.contains) || isUndecidedSentence(sentence)
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

    static func sentences(in text: String) -> [String] {
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

    static func polishedTask(_ value: String) -> String {
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
        guard ownersMatch else { return false }
        if nearDuplicate(lhs.title, rhs.title) { return true }
        // Tasks that cite the same transcript turn and share their action words
        // are one commitment phrased twice, even when the titles differ.
        let shared = sharedEvidence(lhs.evidence, rhs.evidence)
        guard shared.sameTurn else { return false }
        let left = actionTokens(lhs), right = actionTokens(rhs)
        let common = left.intersection(right).count
        guard common >= 1 else { return false }
        if shared.sameQuote { return true }
        let smaller = min(left.count, right.count)
        return common >= 2 || Double(common) / Double(max(1, smaller)) >= 0.67
    }

    private static func completeness(_ task: SuggestedTask) -> Int {
        (task.owner == nil ? 0 : 1) + (task.deadlineText == nil ? 0 : 1)
    }

    private static func actionTokens(_ task: SuggestedTask) -> Set<String> {
        let ownerTokens = stems(task.owner ?? "")
        return stems(task.title).subtracting(ownerTokens)
    }

    private static func sharedEvidence(_ lhs: [SourceEvidence], _ rhs: [SourceEvidence]) -> (sameTurn: Bool, sameQuote: Bool) {
        var sameTurn = false, sameQuote = false
        for left in lhs {
            for right in rhs where left.turnID == right.turnID {
                sameTurn = true
                let a = normalize(left.quote), b = normalize(right.quote)
                if !a.isEmpty, !b.isEmpty, a == b || a.contains(b) || b.contains(a) { sameQuote = true }
            }
        }
        return (sameTurn, sameQuote)
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

    static func isSubstantive(_ text: String) -> Bool {
        let normalized = normalize(text)
        let emptyPhrases = ["", "okay", "ok", "yes", "no", "thanks", "thank you", "hello", "hi", "good morning"]
        return text.count >= 8 && !emptyPhrases.contains(normalized)
    }

    private static func containsNegation(_ text: String) -> Bool {
        ["not decided", "did not decide", "not agreed", "was not approved", "wasn't approved",
         "not rejected", "no decision"].contains(where: text.contains)
    }

    // MARK: - Certainty of a sentence

    /// Lowercased, punctuation-free form padded with single spaces so a marker
    /// can be matched as whole words. Apostrophes are kept ("haven't").
    static func clauseKey(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        var result = " "
        var previousWasSpace = true
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "'" {
                result.unicodeScalars.append(scalar)
                previousWasSpace = false
            } else if !previousWasSpace {
                result.append(" ")
                previousWasSpace = true
            }
        }
        if !result.hasSuffix(" ") { result.append(" ") }
        return result
    }

    private static let undecidedMarkers: [String] = [
        "not decided", "not yet decided", "haven't decided", "have not decided", "havent decided",
        "hasn't decided", "has not decided", "hasn't been decided", "has not been decided",
        "not been decided", "didn't decide", "did not decide", "yet to decide", "yet to be decided",
        "to be decided", "still deciding", "undecided", "no decision", "tbd", "not finalized",
        "not finalised", "not agreed", "not yet agreed", "haven't agreed", "have not agreed",
        "not sure whether", "not sure if", "unsure", "open question", "remains open", "still open",
        "needs further discussion", "should we", "shall we", "could we", "would we", "what if", "if we",
        "whether", "maybe", "perhaps", "might",
        "decide nahi", "decide nahin", "tay nahi", "tay nahin", "fix nahi", "final nahi", "pata nahi",
        "shayad", "kya hum", "kya humein",
        "\u{0924}\u{092F} \u{0928}\u{0939}\u{0940}\u{0902}", "\u{0924}\u{092F} \u{0928}\u{0939}\u{0940}",
        "\u{0936}\u{093E}\u{092F}\u{0926}"
    ]

    private static let commitmentBlockers: [String] = [
        "won't", "wont", "will not", "not going to", "don't", "do not", "doesn't", "does not", "didn't",
        "cannot", "can't", "never", "no need", "not needed", "not required", "cancelled", "canceled",
        "cancel ho", "cancel kar", "cancel hua", "postponed", "put on hold", "on hold", "dropped",
        "not this week", "not today", "not tomorrow", "not now", "already completed", "already done",
        "already sent", "nahi", "nahin", "mat", "if", "unless", "agar",
        "\u{0928}\u{0939}\u{0940}\u{0902}", "\u{0928}\u{0939}\u{0940}", "\u{0930}\u{0926}\u{094D}\u{0926}"
    ]

    /// Undecided, hypothetical or explicitly open ("not decided", "should we").
    static func isUndecidedSentence(_ sentence: String) -> Bool {
        let key = clauseKey(sentence)
        return undecidedMarkers.contains { key.contains(" " + $0 + " ") }
    }

    /// True when a sentence cannot support a definite future commitment.
    static func isNonCommittalSentence(_ sentence: String) -> Bool {
        if isUndecidedSentence(sentence) { return true }
        let key = clauseKey(sentence)
        return commitmentBlockers.contains { key.contains(" " + $0 + " ") }
    }

    // MARK: - Grounding

    /// Resolves a model quote (often only a fragment such as "change the design")
    /// to the whole transcript sentence that contains it, because the negation
    /// that governs a fragment lives in the surrounding sentence.
    private struct Grounding {
        let turns: [String: AnalysisTurn]

        init(turns: [AnalysisTurn]) {
            self.turns = Dictionary(turns.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }

        func sentences(for evidence: [SourceEvidence]) -> [String] {
            var result: [String] = []
            for item in evidence {
                var expanded: [String] = []
                if let text = turns[item.turnID]?.text, let quoteRange = text.range(of: item.quote) {
                    text.enumerateSubstrings(in: text.startIndex..<text.endIndex,
                                             options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
                        if range.overlaps(quoteRange) {
                            let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !value.isEmpty { expanded.append(value) }
                        }
                    }
                }
                if expanded.isEmpty { expanded = MeetingAnalysisReducer.sentences(in: item.quote) }
                result.append(contentsOf: expanded)
            }
            return result
        }
    }

    private struct Focus {
        /// Sentences that best support the claim.
        let sentences: [String]
        /// False when no sentence shares a word with the claim.
        let matched: Bool
        /// Every sentence cited by the claim.
        let all: [String]
    }

    private static func focus(for text: String, evidence: [SourceEvidence], _ grounding: Grounding) -> Focus {
        let target = stems(text)
        let all = grounding.sentences(for: evidence)
        let scores: [Int] = all.map { target.intersection(stems($0)).count }
        let best = scores.max() ?? 0
        guard best > 0 else { return Focus(sentences: all, matched: false, all: all) }
        var supporting: [String] = []
        for (index, sentence) in all.enumerated() where scores[index] == best { supporting.append(sentence) }
        return Focus(sentences: supporting, matched: true, all: all)
    }

    private static func isUndecidedPoint(_ point: SupportedPoint, _ grounding: Grounding) -> Bool {
        let found = focus(for: point.text, evidence: point.evidence, grounding)
        guard !found.sentences.isEmpty else { return false }
        return found.sentences.allSatisfy(isUndecidedSentence)
    }

    private static func isRequestOnly(_ point: SupportedPoint, _ grounding: Grounding,
                                      _ requestSentences: Set<String>) -> Bool {
        let found = focus(for: point.text, evidence: point.evidence, grounding)
        guard !found.all.isEmpty else { return false }
        return found.all.allSatisfy { requestSentences.contains(normalize($0)) && !DecisionExtractor.isDecision($0) }
    }

    private static func focusKeys(_ point: SupportedPoint, _ grounding: Grounding) -> Set<String> {
        let found = focus(for: point.text, evidence: point.evidence, grounding)
        // A claim that cites exactly one sentence is about that sentence, even
        // when the model paraphrased it with different words.
        guard found.matched || found.all.count == 1 else { return [] }
        return Set(found.sentences.map(normalize))
    }

    private static func sharesFocus(_ lhs: SupportedPoint, _ rhs: SupportedPoint, _ grounding: Grounding) -> Bool {
        !focusKeys(lhs, grounding).isDisjoint(with: focusKeys(rhs, grounding))
    }

    private static func deduplicateOpenIssues(_ values: [SupportedPoint], _ grounding: Grounding) -> [SupportedPoint] {
        var result: [SupportedPoint] = []
        for value in values {
            if let index = result.firstIndex(where: { nearDuplicate($0.text, value.text) || sharesFocus($0, value, grounding) }) {
                let preferred = value.text.count > result[index].text.count ? value.text : result[index].text
                result[index] = SupportedPoint(text: preferred,
                    evidence: uniqueEvidence(result[index].evidence + value.evidence))
            } else {
                result.append(value)
            }
        }
        return result
    }

    /// A task needs a definite commitment behind it. It is rejected when the
    /// sentence that best supports it is negated, undecided, hypothetical or
    /// cancelled, and a "decide ..." task is never created from an undecided point.
    private static func isGroundedCommitment(_ task: SuggestedTask, _ grounding: Grounding) -> Bool {
        let found = focus(for: task.title, evidence: task.evidence, grounding)
        guard !found.all.isEmpty else { return false }
        if found.matched {
            if found.sentences.allSatisfy(isNonCommittalSentence) { return false }
        } else if found.all.count > 1, found.all.contains(where: isNonCommittalSentence) {
            // The title matches none of several cited sentences, one of which is
            // non-committal: it is more likely invented from that sentence.
            return false
        }
        let first = normalize(task.title).split(separator: " ").first.map(String.init) ?? ""
        let decideVerbs = Set(["decide", "determine", "choose", "settle", "resolve", "tay"])
        if decideVerbs.contains(first) {
            if !found.matched || found.all.contains(where: isUndecidedSentence) { return false }
        }
        return true
    }

    private static func stems(_ text: String) -> Set<String> {
        Set(meaningfulTokens(text).map(stem))
    }

    private static func stem(_ word: String) -> String {
        for suffix in ["ing", "ed", "es", "s", "e"] where word.count - suffix.count >= 3 && word.hasSuffix(suffix) {
            return String(word.dropLast(suffix.count))
        }
        return word
    }

    private static func actionHasVerb(_ text: String) -> Bool {
        let verbs = ["send", "share", "prepare", "create", "update", "review", "approve", "confirm", "schedule",
                     "contact", "research", "check", "provide", "complete", "submit", "draft", "follow", "call",
                     "email", "deliver", "finalize", "investigate", "resolve", "book", "organize", "arrange"]
        let words = meaningfulTokens(text)
        return verbs.contains { verb in words.contains(verb) || words.contains(verb + "s") || words.contains(verb + "ing") }
    }

    static func category(for title: String) -> String {
        let lower = title.lowercased()
        if ["research", "investigate", "check"].contains(where: lower.contains) { return "Research" }
        if ["review", "approve"].contains(where: lower.contains) { return "Review/Approve" }
        if ["create", "update", "prepare", "draft"].contains(where: lower.contains) { return "Create/Update" }
        if ["schedule", "contact", "call", "email", "organize", "arrange"].contains(where: lower.contains) { return "Coordination" }
        return "Follow-up"
    }
}
