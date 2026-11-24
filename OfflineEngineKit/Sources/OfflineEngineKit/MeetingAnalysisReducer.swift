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
                decisionCandidates.append(englishPoint(point))
            }
        }
        var discussionCandidates: [SupportedPoint] = []
        for point in generatedDiscussion.compactMap(cleanedPoint) {
            if isUndecidedPoint(point, grounding) { openCandidates.append(point) } else { discussionCandidates.append(point) }
        }
        // An explicit "not decided" or "pending" wins over a model claim that the same matter was settled.
        let deterministicOpen = unresolvedOutcomes(in: checkpoint.turns, hindi: hindi) + hindiOpenPoints(hindi)
        let openPool = openCandidates + deterministicOpen
        let openSubjects = openSubjectSets(openPool)
        decisionCandidates = decisionCandidates.filter { !claimsOpenMatterSettled($0, openSubjects, requireClaim: false) }
        discussionCandidates = discussionCandidates.filter { !claimsOpenMatterSettled($0, openSubjects, requireClaim: true) }

        var decisions = deduplicatePoints(decisionCandidates)
        let deterministicDecisions = explicitDecisions(in: checkpoint.turns, hindi: hindi) + hindiDecisionPoints(hindi)
        // In a Devanagari transcript the model's decision and the grammar's decision about the same subject are
        // one decision, written with the grammar's wording.
        decisions = hindi.hasDevanagari
            ? mergeBySubject(model: decisions, deterministic: deterministicDecisions)
            : mergePoints(decisions, with: deterministicDecisions)
        decisions.removeAll { isContentlessDecision($0.text) }

        var openIssues = deduplicateOpenIssues(openPool, grounding)
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
        var turnOrder: [String: Int] = [:]
        for (index, turn) in checkpoint.turns.enumerated() where turnOrder[turn.id] == nil { turnOrder[turn.id] = index }
        // A sentence that settles or defers a matter is a decision or an open issue, never also a task.
        let settledSentences: Set<String> = hindi.hasDevanagari
            ? sentenceKeys(decisions.flatMap { $0.evidence } + openIssues.flatMap { $0.evidence }, grounding)
            : []
        let taskSource = TaskGrounding.source(turns: checkpoint.turns, participants: participants, speakerNames: speakerNames)
        let openMatters = openSubjectSets(openIssues)
        var modelTasks: [SuggestedTask] = []
        for generated in generatedTasks {
            guard let cleaned = cleanedTask(generated) else { continue }
            let resolved = withResolvedOwner(cleaned, speakerLabels: speakerLabels, speakerNames: speakerNames)
            // The owner and the deadline must come from the turns the task cites, not from a neighbouring task.
            let anchored = TaskGrounding.anchored(resolved, taskSource)
            guard isGroundedCommitment(anchored, grounding) else { continue }
            guard !ActionExtractor.isRefusedRequest(evidence: anchored.evidence, in: checkpoint.turns) else { continue }
            guard !overlapsSettled(anchored, settledSentences, grounding) else { continue }
            guard !isNonActionTask(anchored, grounding, openMatters) else { continue }
            guard !contradictsFloor(anchored, floorTasks, taskSource, turnOrder) else { continue }
            modelTasks.append(englishTask(anchored))
        }
        var tasks = deduplicateTasks(modelTasks, order: turnOrder)
        tasks = mergeTasks(tasks, with: floorTasks, order: turnOrder)
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
                             deadlineText: cleanedOptional(plausibleDeadline(task.deadlineText)), priority: task.priority,
                             evidence: uniqueEvidence(task.evidence))
    }

    /// A small model sometimes copies Devanagari words into an English title. Loanwords are restored to
    /// English and any other word is spelled in Latin letters.
    private static func englishTask(_ task: SuggestedTask) -> SuggestedTask {
        guard HindiText.containsDevanagari(task.title) else { return task }
        return SuggestedTask(title: polishedTask(HindiText.englishPhrase(task.title)), category: task.category,
                             owner: task.owner, deadlineText: task.deadlineText, priority: task.priority,
                             evidence: task.evidence)
    }

    private static func englishPoint(_ point: SupportedPoint) -> SupportedPoint {
        guard HindiText.containsDevanagari(point.text) else { return point }
        return SupportedPoint(text: HindiText.englishPhrase(point.text), evidence: point.evidence)
    }

    /// A deadline is a time expression. Words a model copied from an undecided or negated sentence
    /// ("abhi tay nahi hua") are not one and are dropped.
    static func plausibleDeadline(_ value: String?) -> String? {
        guard let value = value else { return nil }
        let keys = HindiText.tokenize(value).map { $0.key }
        guard !keys.isEmpty else { return nil }
        let timeWords: Set<String> = [
            "kal", "parso", "aaj", "tak", "hafte", "mahine", "subah", "shaam", "raat", "tomorrow", "today", "tonight",
            "eod", "eow", "cob", "noon", "week", "month", "day", "days", "hour", "hours", "minutes", "morning",
            "evening", "afternoon", "weekend", "next", "end", "by", "before", "within", "after", "this"
        ]
        let statementWords: Set<String> = [
            "nahi", "nahin", "hua", "hui", "hai", "hain", "tha", "gaya", "tay", "decide", "decided", "pending", "not",
            "yet", "hoga", "karna"
        ]
        let hasTime = value.rangeOfCharacter(from: .decimalDigits) != nil
            || keys.contains { timeWords.contains($0) || HindiText.weekdays.contains($0) || HindiText.months.contains($0) }
        if hasTime { return value }
        return keys.contains { statementWords.contains($0) } ? nil : value
    }

    private static func sentenceKeys(_ evidence: [SourceEvidence], _ grounding: Grounding) -> Set<String> {
        var keys = Set<String>()
        for item in evidence {
            for sentence in grounding.sentences(for: [item]) { keys.insert(item.turnID + "\u{0}" + normalize(sentence)) }
        }
        return keys
    }

    private static func overlapsSettled(_ task: SuggestedTask, _ settled: Set<String>, _ grounding: Grounding) -> Bool {
        guard !settled.isEmpty else { return false }
        return !sentenceKeys(task.evidence, grounding).isDisjoint(with: settled)
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

    private static func deduplicateTasks(_ values: [SuggestedTask], modelCount: Int = Int.max,
                                         order: [String: Int] = [:]) -> [SuggestedTask] {
        var result: [SuggestedTask] = []
        var overridden = Set<Int>()
        for (offset, task) in values.enumerated() {
            if let index = result.firstIndex(where: { sameTask($0, task, order: order) }) {
                let current = result[index]
                // Keep the version that carries more actionable detail (owner,
                // deadline); fill any remaining gaps from the other.
                let preferNew = completeness(task) > completeness(current)
                let primary = preferNew ? task : current
                let secondary = preferNew ? current : task
                let equal = completeness(task) == completeness(current)
                var title = equal && secondary.title.count > primary.title.count ? secondary.title : primary.title
                let other = title == primary.title ? secondary.title : primary.title
                // An English title beats one that still holds Devanagari, and the deterministic title beats
                // the model's when both describe the same Hindi sentence.
                if HindiText.containsDevanagari(title), !HindiText.containsDevanagari(other) { title = other }
                var deadline = primary.deadlineText ?? secondary.deadlineText
                if offset >= modelCount, index < modelCount, !overridden.contains(index), isHindiGrounded(task) {
                    title = task.title
                    overridden.insert(index)
                    // The deterministic deadline keeps the spoken form ("फ्राइडे तक") that the minutes translate.
                    if let spoken = task.deadlineText, let model = deadline, deadlineKey(spoken) == deadlineKey(model) {
                        deadline = spoken
                    }
                }
                result[index] = SuggestedTask(
                    title: title,
                    category: primary.category == "Other" ? secondary.category : primary.category,
                    owner: primary.owner ?? secondary.owner,
                    deadlineText: deadline,
                    priority: primary.priority ?? secondary.priority,
                    evidence: uniqueEvidence(primary.evidence + secondary.evidence)
                )
            } else {
                result.append(task)
            }
        }
        return result
    }

    private static func isHindiGrounded(_ task: SuggestedTask) -> Bool {
        task.evidence.contains { HindiText.containsDevanagari($0.quote) }
    }

    private static func mergeTasks(_ lhs: [SuggestedTask], with rhs: [SuggestedTask],
                                   order: [String: Int] = [:]) -> [SuggestedTask] {
        deduplicateTasks(lhs + rhs, modelCount: lhs.count, order: order)
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

    private static func sameTask(_ lhs: SuggestedTask, _ rhs: SuggestedTask, order: [String: Int] = [:]) -> Bool {
        let ownersMatch = normalize(lhs.owner ?? "") == normalize(rhs.owner ?? "")
            || lhs.owner == nil || rhs.owner == nil
        guard ownersMatch else { return false }
        if nearDuplicate(lhs.title, rhs.title) { return true }
        if sameObjectNearby(lhs, rhs, order: order) { return true }
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

    private static let verbClasses: [String: String] = [
        "prepare": "make", "create": "make", "make": "make", "draft": "make", "write": "make", "build": "make",
        "compile": "make", "send": "send", "share": "send", "forward": "send", "email": "send", "mail": "send",
        "submit": "send", "deliver": "send", "circulate": "send", "provide": "send", "give": "send",
        "review": "review", "check": "review", "verify": "review", "look": "review"
    ]
    private static let objectFiller: Set<String> = [
        "the", "a", "an", "to", "for", "of", "on", "by", "with", "and", "our", "this", "that", "your", "my", "their"
    ]

    /// Verb class and object words of a task title: "Send the presentation to the client" is
    /// ("send", {presentation, client}).
    private static func verbAndObject(_ title: String) -> (verb: String, object: Set<String>) {
        var words: [String] = []
        for piece in HindiText.englishPhrase(title).split(whereSeparator: { $0.isWhitespace }) {
            let word = String(piece).lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters)
            if !word.isEmpty { words.append(word) }
        }
        guard let first = words.first else { return ("", []) }
        var verb = ""
        if let known = verbClasses[first] {
            verb = known
        } else if ActionExtractor.isVerbWord(first) {
            verb = first
        }
        let rest = verb.isEmpty ? words : Array(words.dropFirst())
        let object = Set(rest.filter { !objectFiller.contains($0) }.map(stem))
        return (verb, object)
    }

    private static func deadlineKey(_ value: String) -> String {
        MinutesComposer.englishDeadline(value).lowercased().replacingOccurrences(of: "by ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func turnsNearby(_ lhs: [SourceEvidence], _ rhs: [SourceEvidence], _ order: [String: Int]) -> Bool {
        for left in lhs {
            for right in rhs {
                if left.turnID == right.turnID { return true }
                if let a = order[left.turnID], let b = order[right.turnID], abs(a - b) <= 1 { return true }
            }
        }
        return false
    }

    /// One commitment phrased twice: the same kind of verb, one object contained in the other, compatible
    /// deadlines, and evidence in the same or adjacent turns (a request in one turn, the promise in the next).
    private static func sameObjectNearby(_ lhs: SuggestedTask, _ rhs: SuggestedTask, order: [String: Int]) -> Bool {
        let left = verbAndObject(lhs.title)
        let right = verbAndObject(rhs.title)
        guard !left.object.isEmpty, !right.object.isEmpty else { return false }
        guard left.verb.isEmpty || right.verb.isEmpty || left.verb == right.verb else { return false }
        guard left.object.isSubset(of: right.object) || right.object.isSubset(of: left.object) else { return false }
        if let a = lhs.deadlineText, let b = rhs.deadlineText, deadlineKey(a) != deadlineKey(b) { return false }
        return turnsNearby(lhs.evidence, rhs.evidence, order)
    }

    private static let decisionFiller: Set<String> = [
        "the", "a", "an", "that", "this", "be", "is", "are", "was", "were", "it", "we", "will", "to", "of", "for", "on",
        "at", "in", "by", "with", "and", "as", "held", "set", "fixed", "finalize", "finalized", "finalise", "finalised",
        "go", "going", "adopted", "engaged", "selected", "chosen", "decided", "agreed", "resolved", "approved",
        "confirmed", "date", "proceed", "use", "team", "meeting"
    ]

    private static func decisionTokens(_ text: String) -> Set<String> {
        var tokens = Set<String>()
        for piece in normalize(text).split(separator: " ") {
            var word = String(piece)
            for suffix in ["st", "nd", "rd", "th"] where word.count > 2 && word.hasSuffix(suffix) {
                let digits = String(word.dropLast(2))
                if digits.allSatisfy({ $0.isNumber }) { word = digits }
            }
            if word.count > 1, !decisionFiller.contains(word) { tokens.insert(word) }
        }
        return tokens
    }

    /// Two decision texts about the same subject: they share at least two words, one of them more than a date,
    /// and the shared words cover most of the shorter text ("Launch on 20 November" and
    /// "That the launch be held on November 20th").
    private static func sameDecisionSubject(_ lhs: String, _ rhs: String) -> Bool {
        let left = decisionTokens(lhs)
        let right = decisionTokens(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        let shared = left.intersection(right)
        let content = shared.filter { token in
            !HindiText.months.contains(token) && !token.allSatisfy { $0.isNumber }
        }
        guard shared.count >= 2, !content.isEmpty else { return false }
        return Double(shared.count) / Double(min(left.count, right.count)) >= 0.6
    }

    /// Merges the model's decisions into the deterministic ones. A model decision about the same subject only
    /// contributes its evidence; the deterministic wording is kept.
    private static func mergeBySubject(model: [SupportedPoint], deterministic: [SupportedPoint]) -> [SupportedPoint] {
        func same(_ lhs: SupportedPoint, _ rhs: SupportedPoint) -> Bool {
            nearDuplicate(lhs.text, rhs.text) || sameDecisionSubject(lhs.text, rhs.text)
        }
        var result: [SupportedPoint] = []
        for point in deterministic {
            if let index = result.firstIndex(where: { same($0, point) }) {
                let preferred = point.text.count > result[index].text.count ? point.text : result[index].text
                result[index] = SupportedPoint(text: preferred, evidence: uniqueEvidence(result[index].evidence + point.evidence))
            } else {
                result.append(point)
            }
        }
        for point in model {
            if let index = result.firstIndex(where: { same($0, point) }) {
                result[index] = SupportedPoint(text: result[index].text,
                                               evidence: uniqueEvidence(result[index].evidence + point.evidence))
            } else {
                result.append(point)
            }
        }
        return result
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
        "defer", "deferred", "deferring", "put off the decision", "decision is deferred", "decision deferred",
        "taken up at the next meeting", "taken up in the next meeting",
        "baad mein decide karenge", "agli meeting mein decide karenge",
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

    // MARK: - Open matters

    /// Words that describe the state of a matter ("not yet decided", "pending"), not the matter itself.
    private static let matterStatusWords: Set<String> = [
        "not", "yet", "pending", "still", "open", "undecided", "decision", "decide", "deciding", "discussed",
        "discussion", "reached", "taken", "up", "next", "remain", "remains", "has", "have", "been", "hasn",
        "haven", "tbd", "deferred", "defer", "later", "also", "too", "no", "was", "were", "raised"
    ]

    /// Stemmed content words of a decision, an open issue or a claim, without dates and status words.
    private static func subjectStems(_ text: String) -> Set<String> {
        var result = Set<String>()
        for word in decisionTokens(text) where !matterStatusWords.contains(word) {
            if HindiText.months.contains(word) { continue }
            if word.allSatisfy({ $0.isNumber }) { continue }
            result.insert(stem(word))
        }
        return result
    }

    private static func openSubjectSets(_ points: [SupportedPoint]) -> [Set<String>] {
        var result: [Set<String>] = []
        for point in points {
            let subject = subjectStems(point.text)
            if !subject.isEmpty { result.append(subject) }
        }
        return result
    }

    /// The same matter: identical subjects, or one subject of two or more words inside the other.
    private static func sameMatter(_ lhs: Set<String>, _ rhs: Set<String>) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        if lhs == rhs { return true }
        guard min(lhs.count, rhs.count) >= 2 else { return false }
        return lhs.isSubset(of: rhs) || rhs.isSubset(of: lhs)
    }

    /// A positive statement that something was agreed, decided or adopted.
    private static func assertsOutcome(_ text: String) -> Bool {
        let lower = text.lowercased()
        let negations = ["not ", "no decision", "n't", "undecided", "pending", "yet to", "unresolved", "open"]
        for marker in negations where lower.contains(marker) { return false }
        let claims = ["agreed", "decided", "resolved", "approved", "adopted", "finaliz", "go with", "going with",
                      "selected", "chosen", "settled", "confirmed", "will be"]
        for marker in claims where lower.contains(marker) { return true }
        return false
    }

    /// True when a model decision (or an "agreed" discussion point) is about a matter the meeting left open.
    private static func claimsOpenMatterSettled(_ point: SupportedPoint, _ matters: [Set<String>],
                                                requireClaim: Bool) -> Bool {
        if requireClaim, !assertsOutcome(point.text) { return false }
        let claim = subjectStems(point.text)
        for matter in matters where sameMatter(claim, matter) { return true }
        return false
    }

    private static let discussionVerbs: Set<String> = [
        "discuss", "decide", "determine", "deliberate", "debate", "brainstorm", "consider", "settle"
    ]
    private static let outcomeVerbs: Set<String> = ["handle", "finalize", "finalise", "settle", "resolve", "decide", "set", "fix"]

    private static func titleWords(_ title: String) -> [String] {
        var words: [String] = []
        for piece in title.split(whereSeparator: { $0.isWhitespace }) {
            let word = String(piece).lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters)
            if !word.isEmpty { words.append(word) }
        }
        let lead: Set<String> = ["to", "please", "also", "then"]
        while words.count > 1, let first = words.first, lead.contains(first) { words.removeFirst() }
        return words
    }

    private static func isDiscussionTitle(_ title: String) -> Bool {
        let words = titleWords(title)
        guard let first = words.first else { return false }
        if discussionVerbs.contains(first) { return true }
        return first == "talk" && words.count > 1 && words[1] == "about"
    }

    /// Someone is asked or promises to do it ("can you", "please", "I'll", "needs to").
    private static func hasExplicitRequest(_ sentences: [String]) -> Bool {
        let pattern = #"(?i)\b(?:(?:can|could|would|will)\s+you|please|i'll|i\s+will|you'll|you\s+will|(?:needs?|has|have)\s+to|must|action\s+item)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        for raw in sentences {
            let sentence = raw.replacingOccurrences(of: "\u{2019}", with: "'")
            let range = NSRange(sentence.startIndex..<sentence.endIndex, in: sentence)
            if regex.firstMatch(in: sentence, options: [], range: range) != nil { return true }
        }
        return false
    }

    /// "Discuss X", "talk about X" and "decide X" describe the conversation, not an action, unless someone is
    /// explicitly asked to do it. A task that only restates a matter the meeting left open is not an action either.
    private static func isNonActionTask(_ task: SuggestedTask, _ grounding: Grounding, _ matters: [Set<String>]) -> Bool {
        let parts = verbAndObject(task.title)
        if isDiscussionTitle(task.title) {
            if !hasExplicitRequest(grounding.sentences(for: task.evidence)) { return true }
            for matter in matters where !matter.isDisjoint(with: parts.object) { return true }
            return false
        }
        guard !parts.object.isEmpty else { return false }
        if parts.verb.isEmpty || outcomeVerbs.contains(parts.verb) {
            for matter in matters where parts.object.isSubset(of: matter) { return true }
            return false
        }
        // A concrete task about a matter the meeting left open ("send the design change proposal" when the
        // design change is undecided) needs someone to be asked or to promise it in the cited sentences.
        let touchesOpenMatter = matters.contains { !$0.isDisjoint(with: parts.object) }
        guard touchesOpenMatter else { return false }
        let cited = grounding.sentences(for: task.evidence)
        return !hasExplicitRequest(cited) && !hasHindiRequestOrPromise(cited)
    }

    /// Hindi and Hinglish requests and promises ("kya tum ... kar sakte ho", "main bhej dunga", "bhej do").
    private static func hasHindiRequestOrPromise(_ sentences: [String]) -> Bool {
        let cues = ["\u{0938}\u{0915}\u{0924}\u{0947} \u{0939}\u{094B}", "\u{0938}\u{0915}\u{0924}\u{0940} \u{0939}\u{094B}",
                    "\u{0926}\u{094B}\u{0917}\u{0947}", "\u{0926}\u{094B}\u{0917}\u{0940}",
                    "\u{0926}\u{0942}\u{0902}\u{0917}\u{093E}", "\u{0926}\u{0942}\u{0902}\u{0917}\u{0940}",
                    "\u{0926}\u{0942}\u{0901}\u{0917}\u{093E}", "\u{0926}\u{0942}\u{0901}\u{0917}\u{0940}",
                    "\u{0915}\u{0930}\u{094B}\u{0917}\u{0947}", "\u{0915}\u{0930}\u{094B}\u{0917}\u{0940}",
                    "\u{092D}\u{0947}\u{091C} \u{0926}\u{094B}",
                    "sakte ho", "sakti ho", "doge", "dogi", "dunga", "dungi", "karoge", "karogi", "bhej do", "kar do"]
        for sentence in sentences {
            let lower = sentence.lowercased()
            if cues.contains(where: { lower.contains($0) }) { return true }
        }
        return false
    }

    /// A model task whose owner differs from the owner of the deterministic task for the same object
    /// in the same or an adjacent turn, and whose owner the cited turns never name, is the model's mistake.
    private static func contradictsFloor(_ task: SuggestedTask, _ floor: [SuggestedTask],
                                         _ source: TaskGrounding.Source, _ order: [String: Int]) -> Bool {
        guard let owner = task.owner else { return false }
        for other in floor {
            guard let otherOwner = other.owner else { continue }
            if TaskGrounding.samePerson(owner, otherOwner) { continue }
            guard sameObjectNearby(task, other, order: order) else { continue }
            let text = TaskGrounding.citedText(task.evidence, source)
            if !TaskGrounding.mentions(owner, in: text) { return true }
        }
        return false
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
