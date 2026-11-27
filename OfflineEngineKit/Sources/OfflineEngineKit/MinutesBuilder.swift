import Foundation

/// Turns the reduced decisions, open issues and tasks into document-grade minutes: topics with rephrased
/// English discussion, formal resolutions, contextual actions, suggested attendees and a polished summary.
/// Script independent: its input is already English (the Hindi grammar and the English rules both produce
/// English phrases), so one builder serves Devanagari, romanized Hinglish and English transcripts.
enum MinutesBuilder {
    struct Input {
        let turns: [AnalysisTurn]
        let hindi: HindiAnalysis
        let decisions: [SupportedPoint]
        let discussion: [SupportedPoint]
        let rankedDiscussion: [SupportedPoint]
        let openIssues: [SupportedPoint]
        let tasks: [SuggestedTask]
        let participants: [String]
        let speakerNames: [String: String]
        let meetingDate: Date?
        let timeZone: TimeZone
    }

    static func build(_ input: Input) -> MinutesContent {
        Assembler(input).run()
    }

    // MARK: - Phrase helpers

    /// A decision without conversational lead-ins: "We agreed to launch on 20 November." -> "launch on 20 November".
    static func shortPhrase(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "\u{2019}", with: "'")
        value = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
        value = MinutesRegex.replace(#"(?i)^(?:okay|ok|yes|yeah|so|and|well|then|great)[, ]+"#, in: value)
        value = MinutesRegex.replace(
            #"(?i)^(?:we|they|everyone|all\s+of\s+us)\s+(?:all\s+)?(?:have\s+|'ve\s+)?(?:finally\s+)?(?:agreed|decided|finalized|finalised|resolved)\s+(?:to\s+|on\s+|that\s+)?"#,
            in: value)
        value = MinutesRegex.replace(
            #"(?i)^it(?:'s|\s+is|\s+was)\s+(?:been\s+)?(?:decided|agreed|finalized|finalised)\s+(?:to\s+|that\s+)?"#, in: value)
        value = MinutesRegex.replace(#"(?i)^let's\s+"#, in: value)
        value = MinutesRegex.replace(#"(?i)^(?:going|go)\s+ahead\s+with\s+"#, in: value, with: "go with ")
        value = MinutesRegex.replace(#"(?i)^going\s+with\s+"#, in: value, with: "go with ")
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return HindiText.lowercaseFirst(value)
    }

    /// "go with Stripe because the fees are lower" -> ("go with Stripe", "because the fees are lower").
    /// The reason belongs in the rationale, not in the name of the thing that was chosen.
    static func splitReason(_ short: String) -> (head: String, reason: String?) {
        let pattern = #"(?i)^(.+?)(?:,\s*|\s+)(because|since|due\s+to)\s+(.+)$"#
        guard let head = MinutesRegex.firstMatch(pattern, in: short, group: 1),
              let marker = MinutesRegex.firstMatch(pattern, in: short, group: 2),
              let tail = MinutesRegex.firstMatch(pattern, in: short, group: 3) else { return (short, nil) }
        let cleanedHead = head.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",")))
        let cleanedTail = tail.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ".!?")))
        guard cleanedHead.split(separator: " ").count >= 2, cleanedTail.split(separator: " ").count >= 2,
              !HindiText.looksRomanizedHindi(cleanedTail) else { return (short, nil) }
        let word = marker.lowercased().replacingOccurrences(of: "  ", with: " ")
        return (cleanedHead, word + " " + HindiText.lowercaseFirst(cleanedTail))
    }

    private static func firstDate(in text: String) -> String? {
        MinutesRegex.firstMatch(DueDateResolver.datePhrasePattern, in: text)
    }

    private static func hasDeterminer(_ text: String) -> Bool {
        let first = text.split(separator: " ").first.map { String($0).lowercased() } ?? ""
        if ["the", "a", "an", "our", "this", "that", "their", "its", "his", "her"].contains(first) { return true }
        if let character = first.first, character.isNumber { return true }
        return false
    }

    private static func isVendorLike(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["vendor", "supplier", "contractor", "agency", "consultant", "provider"].contains { lower.contains($0) }
    }

    /// Title for a topic created from a decision.
    static func topicTitle(fromShort short: String) -> String {
        var value = short
        if let range = value.range(of: "go with ", options: .caseInsensitive) {
            value = String(value[range.upperBound...])
        }
        value = MinutesRegex.replace(#"(?i)^(?:the|a|an|our)\s+"#, in: value)
        for cut in [" on ", " set to ", " by ", " for ", " at ", " to be "] {
            if let range = value.range(of: cut, options: .caseInsensitive) { value = String(value[..<range.lowerBound]) }
        }
        let words = value.split(separator: " ").prefix(3).map(String.init)
        return HindiText.capitalizeFirst(words.joined(separator: " "))
    }

    /// "launch on 20 November" -> "That the launch be held on 20 November."
    static func formalResolution(short: String, original: String, rationale: String?, hasLaunchContext: Bool) -> String {
        let lower = short.lowercased()
        if lower.hasPrefix("go with ") {
            let object = String(short.dropFirst("go with ".count)).trimmingCharacters(in: .whitespaces)
            if !object.isEmpty {
                let vendor = isVendorLike(object)
                var text = "That " + (hasDeterminer(object) ? "" : "the ") + object + " be " + (vendor ? "engaged" : "adopted")
                if vendor && hasLaunchContext { text += " for the launch" }
                if let rationale = rationale {
                    text += " (" + (rationale.hasPrefix("lower ") ? "preferred for " + rationale : rationale) + ")"
                }
                return text + "."
            }
        }
        let date = firstDate(in: short)
        if let date = date {
            if lower.contains("launch") || lower.contains("release") {
                let noun = lower.contains("launch") ? "launch" : "release"
                return "That the " + noun + " be held on " + date + rationaleSuffix(rationale) + "."
            }
            if lower.hasPrefix("finalize ") || lower.hasPrefix("finalise ") {
                return "That the date be fixed as " + date + rationaleSuffix(rationale) + "."
            }
            var base = short
            if let range = base.range(of: date, options: .caseInsensitive) { base.removeSubrange(range) }
            base = MinutesRegex.replace(#"(?i)\s+(?:on|for|by|set\s+to)\s*$"#, in: base)
            base = base.trimmingCharacters(in: .whitespaces)
            if !base.isEmpty {
                let article = hasDeterminer(base) ? "" : "the "
                return "That " + article + HindiText.lowercaseFirst(base) + " be scheduled for " + date + rationaleSuffix(rationale) + "."
            }
        }
        if lower.hasPrefix("finalize ") || lower.hasPrefix("finalise ") {
            let object = String(short.dropFirst("finalize ".count)).trimmingCharacters(in: .whitespaces)
            if !object.isEmpty {
                return "That " + (hasDeterminer(object) ? "" : "the ") + object + " be finalized" + rationaleSuffix(rationale) + "."
            }
        }
        if ActionExtractor.startsWithVerb(short) {
            return "It was resolved to " + HindiText.lowercaseFirst(short) + rationaleSuffix(rationale) + "."
        }
        return "Resolved: " + HindiText.capitalizeFirst(short) + rationaleSuffix(rationale) + "."
    }

    private static func rationaleSuffix(_ rationale: String?) -> String {
        guard let rationale = rationale else { return "" }
        return " (" + rationale + ")"
    }

    /// The clause that follows "RESOLVED THAT" in the document.
    static func resolvedClause(_ formal: String) -> String {
        if formal.hasPrefix("That ") { return String(formal.dropFirst("That ".count)) }
        return formal
    }

    /// Subject of an English "X is not decided" sentence, or nil.
    static func englishSubject(_ text: String) -> String? {
        var value = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        value = MinutesRegex.replace(#"(?i)^(?:okay|ok|yes|yeah|so|and|well|also|but|right)[, ]+"#, in: value)
        value = MinutesRegex.replace(#"(?i)^(?:the|our|this|that)\s+"#, in: value)
        guard let found = MinutesRegex.firstMatch(
            #"(?i)^(.+?)\s+(?:is|are|was|were|has|have|hasn't|haven't|isn't|aren't|remains?|still|not|yet)\b"#,
            in: value, group: 1) else { return nil }
        var subject = MinutesRegex.replace(#"(?i)\s+(?:also|still|again|too)$"#, in: found).trimmingCharacters(in: .whitespaces)
        let words = subject.split(separator: " ").map(String.init)
        guard !words.isEmpty, words.count <= 5 else { return nil }
        let pronouns: Set<String> = ["we", "i", "they", "it", "that", "this", "there", "you", "he", "she", "what", "which"]
        if pronouns.contains(words[0].lowercased()) { return nil }
        subject = HindiText.capitalizeFirst(subject)
        return subject
    }

    static func openIssueText(subject: String, undecided: Bool, pending: Bool, nextMeeting: Bool) -> String {
        var text = subject + " \u{2014} "
        if undecided {
            text += "not yet decided"
            if nextMeeting { text += "; to be taken up at the next meeting" }
        } else if pending {
            text += "decision pending"
            if nextMeeting { text += "; to be taken up at the next meeting" }
        } else {
            text += "to be taken up at the next meeting"
        }
        return text + "."
    }

    // MARK: - Rationale

    private static let priceWords: [String] = ["price", "cost", "rate", "pricing"]
    private static let lowWords: Set<String> = ["kam", "sasta", "cheap", "cheaper", "low", "lower", "less", "affordable", "reasonable"]

    static func priceReason(_ keys: [String]) -> String? {
        guard let price = priceWords.first(where: { keys.contains($0) }) else { return nil }
        guard keys.contains(where: { lowWords.contains($0) }) else { return nil }
        if keys.contains("nahi") || keys.contains("not") || keys.contains("nahin") { return nil }
        return "lower " + (price == "pricing" ? "price" : price)
    }

    static func becauseReason(_ tokens: [HindiToken]) -> String? {
        guard let index = tokens.firstIndex(where: { $0.key == "because" || $0.key == "kyonki" }) else { return nil }
        let tail = tokens[(index + 1)...].prefix(8)
        var words: [String] = []
        for token in tail {
            if token.isDevanagari && !token.isKnown { return nil }
            words.append(token.isDevanagari ? token.display.lowercased() : token.raw.lowercased())
        }
        guard words.count >= 2 else { return nil }
        let joined = words.joined(separator: " ")
        if HindiText.looksRomanizedHindi(joined) { return nil }
        return "because " + joined
    }

    static func findRationale(decisionText: String, evidence: [SourceEvidence], turns: [AnalysisTurn],
                              indexByID: [String: Int], pieces: [[String]]) -> (text: String, source: SourceEvidence)? {
        let subject = wordsForRationale(decisionText)
        guard !subject.isEmpty else { return nil }

        // Prefer a reason actually stated in the decision's own sentence.
        for item in evidence {
            let tokens = HindiText.tokenize(item.quote)
            if let reason = priceReason(tokens.map(\.key)) ?? becauseReason(tokens) {
                return (reason, item)
            }
        }

        // A prior comparison can explain a preference if it names the same
        // subject. Preserve its quote so readers can distinguish the source.
        guard let first = evidence.compactMap({ indexByID[$0.turnID] }).min(), first > 0 else { return nil }
        for index in stride(from: first - 1, through: max(0, first - 4), by: -1) {
            for piece in pieces[index] {
                guard turns[index].text.contains(piece),
                      subject.isSubset(of: wordsForRationale(piece)),
                      let preference = priceReason(HindiText.tokenize(piece).map(\.key)) else { continue }
                return (preference, SourceEvidence(turnID: turns[index].id, quote: piece))
            }
        }
        return nil
    }

    private static func wordsForRationale(_ text: String) -> Set<String> {
        let normalized = HindiText.tokenize(text).map(\.display).joined(separator: " ")
        return MinutesComposer.words(normalized).subtracting(["go", "with", "choose", "select", "adopt", "use", "the"])
    }

    // MARK: - Assembler

    private struct TopicDraft {
        var title: String
        var ownEvidence: SourceEvidence?
        var ownTurn: Int
        var firstSeen: Int
        var outcome: MinutesOutcome?
        var outcomeEvidence: [SourceEvidence] = []
        var otherTurns: [Int] = []
        var preferenceBullets: [String] = []
        var agreedBullets: [String] = []
        var issueBullets: [String] = []

        var sortKey: Int { otherTurns.min() ?? ownTurn }
    }

    private final class Assembler {
        let input: Input
        let pieces: [[String]]
        var indexByID: [String: Int] = [:]
        var drafts: [TopicDraft] = []

        init(_ input: Input) {
            self.input = input
            self.pieces = ActionExtractor.sentencePieces(input.turns)
            for (index, turn) in input.turns.enumerated() { indexByID[turn.id] = index }
        }

        // MARK: Lookups

        func firstTurn(_ evidence: [SourceEvidence]) -> AnalysisTurn? {
            let indices = evidence.compactMap { indexByID[$0.turnID] }
            guard let first = indices.min() else { return nil }
            return input.turns[first]
        }

        func speakerName(_ turn: AnalysisTurn?) -> String? {
            guard let label = turn?.speaker else { return nil }
            if let mapped = input.speakerNames[label] { return mapped }
            if SpeakerNameInference.isGenericLabel(label) { return nil }
            return label
        }

        func turnIndices(_ evidence: [SourceEvidence]) -> [Int] {
            evidence.compactMap { indexByID[$0.turnID] }
        }

        func topicIndex(related text: String) -> Int? {
            for (index, draft) in drafts.enumerated() where MinutesComposer.related(draft.title, text) { return index }
            return nil
        }

        func ensureTopic(text: String, title: String, evidence: [SourceEvidence]) -> Int {
            if let existing = topicIndex(related: text) { return existing }
            let turn = turnIndices(evidence).min() ?? 0
            drafts.append(TopicDraft(title: title, ownEvidence: evidence.first, ownTurn: turn, firstSeen: drafts.count))
            return drafts.count - 1
        }

        /// A next-meeting deferral in the same turn after the evidence sentence, or in the first sentence of the next turn.
        func hasDeferral(_ evidence: [SourceEvidence]) -> Bool {
            for item in evidence {
                guard let turnIndex = indexByID[item.turnID] else { continue }
                let turnPieces = pieces[turnIndex]
                var start = 0
                if let found = turnPieces.firstIndex(where: { $0.contains(item.quote) || item.quote.contains($0) }) { start = found }
                for piece in turnPieces[start...] {
                    if NextMeetingFinder.isNextMeetingReference(HindiText.tokenize(piece).map { $0.key }) { return true }
                }
                if turnIndex + 1 < pieces.count, let first = pieces[turnIndex + 1].first {
                    if NextMeetingFinder.isNextMeetingReference(HindiText.tokenize(first).map { $0.key }) { return true }
                }
            }
            return false
        }

        func normalizedKey(_ text: String) -> String {
            text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        }

        // MARK: Run

        func run() -> MinutesContent {
            for topic in input.hindi.topics {
                let turn = indexByID[topic.evidence.turnID] ?? 0
                drafts.append(TopicDraft(title: topic.title, ownEvidence: topic.evidence, ownTurn: turn, firstSeen: drafts.count))
            }
            let resolutions = buildResolutions()
            let issues = buildOpenIssues()
            addOpinionBullets()
            let actions = input.tasks.map { buildAction($0) }
            let topics = finalizeTopics()
            let attendees = AttendeeSuggester.suggest(turns: input.turns, tasks: input.tasks,
                                                     participants: input.participants, speakerNames: input.speakerNames)
            let next = NextMeetingFinder.find(turns: input.turns, meetingDate: input.meetingDate, timeZone: input.timeZone)
            let summary = buildSummary(topics: topics, issues: issues)
            return MinutesContent(executiveSummary: summary, topics: topics, resolutions: resolutions, actions: actions,
                                  openIssues: issues, suggestedAttendees: attendees, nextMeeting: next)
        }

        // MARK: Resolutions

        func buildResolutions() -> [MinutesResolution] {
            var result: [MinutesResolution] = []
            for decision in input.decisions {
                let turn = firstTurn(decision.evidence)
                let hasScript = HindiText.containsDevanagari(decision.text) || HindiText.looksRomanizedHindi(decision.text)
                if hasScript {
                    result.append(MinutesResolution(text: decision.text, rationale: nil, topic: nil, evidence: decision.evidence,
                                                    timestamp: turn?.start, speaker: speakerName(turn)))
                    continue
                }
                let spoken = MinutesBuilder.shortPhrase(decision.text)
                let split = MinutesBuilder.splitReason(spoken)
                let short = split.head
                let explanation = MinutesBuilder.findRationale(decisionText: short, evidence: decision.evidence,
                    turns: input.turns, indexByID: indexByID, pieces: pieces)
                let rationale = explanation?.text
                let evidence = MinutesComposer.unique(decision.evidence + [explanation?.source].compactMap { $0 })
                let mentionsLaunch = decision.evidence.contains { MinutesComposer.words($0.quote).contains("launch") }
                let formal = MinutesBuilder.formalResolution(short: short, original: decision.text, rationale: rationale,
                                                             hasLaunchContext: mentionsLaunch)
                let topic = ensureTopic(text: short, title: MinutesBuilder.topicTitle(fromShort: short), evidence: decision.evidence)
                drafts[topic].otherTurns.append(contentsOf: turnIndices(decision.evidence))
                if drafts[topic].outcome == nil {
                    drafts[topic].outcome = MinutesOutcome.resolved(MinutesBuilder.resolvedClause(formal))
                    drafts[topic].outcomeEvidence = evidence
                }
                addDecisionBullets(topic: topic, short: short, formal: formal, rationale: rationale, decision: decision)
                result.append(MinutesResolution(text: formal, rationale: rationale, topic: drafts[topic].title,
                                                evidence: evidence, timestamp: turn?.start, speaker: speakerName(turn)))
            }
            return result
        }

        func addDecisionBullets(topic: Int, short: String, formal: String, rationale: String?, decision: SupportedPoint) {
            let key = normalizedKey(decision.text)
            let proposed = input.hindi.decisions.contains { normalizedKey($0.text) == key && $0.proposed }
            let lower = short.lowercased()
            if lower.hasPrefix("go with "), let rationale = rationale {
                let object = String(short.dropFirst("go with ".count)).trimmingCharacters(in: .whitespaces)
                let subject = HindiText.capitalizeFirst((hasDeterminerPublic(object) ? "" : "the ") + object)
                let why = rationale.hasPrefix("lower ") ? " for its " + rationale : " " + rationale
                drafts[topic].preferenceBullets.append(subject + " was preferred" + why + ".")
            }
            if proposed {
                drafts[topic].agreedBullets.append("A proposal to " + short + " was put forward and agreed.")
            } else {
                drafts[topic].agreedBullets.append("It was agreed to " + short + ".")
            }
        }

        func hasDeterminerPublic(_ text: String) -> Bool {
            let first = text.split(separator: " ").first.map { String($0).lowercased() } ?? ""
            return ["the", "a", "an", "our", "this", "that", "their"].contains(first)
        }

        // MARK: Open issues

        func buildOpenIssues() -> [MinutesOpenIssue] {
            var result: [MinutesOpenIssue] = []
            for point in input.openIssues {
                let turn = firstTurn(point.evidence)
                let known = input.hindi.openIssues.first { issue in
                    issue.evidence.contains { item in
                        point.evidence.contains { $0.turnID == item.turnID && $0.quote == item.quote }
                    }
                }
                var subject: String?
                var undecided = true
                var pending = false
                var next = false
                if let issue = known {
                    subject = issue.subject
                    undecided = issue.undecided
                    pending = issue.pending
                    next = issue.nextMeeting
                } else {
                    subject = MinutesBuilder.englishSubject(point.text)
                }
                if !next { next = hasDeferral(point.evidence) }
                guard let title = subject, !HindiText.looksHindi(title) || known != nil else {
                    result.append(MinutesOpenIssue(text: point.text, subject: point.text, topic: nil, nextMeeting: next,
                                                   evidence: point.evidence, timestamp: turn?.start, speaker: speakerName(turn)))
                    continue
                }
                let text = MinutesBuilder.openIssueText(subject: title, undecided: undecided, pending: pending, nextMeeting: next)
                let topic = ensureTopic(text: title, title: title, evidence: point.evidence)
                drafts[topic].otherTurns.append(contentsOf: turnIndices(point.evidence))
                if drafts[topic].outcome == nil {
                    drafts[topic].outcomeEvidence = point.evidence
                    if pending && !undecided {
                        drafts[topic].outcome = next
                            ? MinutesOutcome.deferred("Decision pending; to be taken up at the next meeting.")
                            : MinutesOutcome.open("Decision pending.")
                    } else if undecided {
                        drafts[topic].outcome = next
                            ? MinutesOutcome.deferred("Not yet decided; to be taken up at the next meeting.")
                            : MinutesOutcome.open("Not yet decided.")
                    } else {
                        drafts[topic].outcome = MinutesOutcome.deferred("To be taken up at the next meeting.")
                    }
                }
                var bullet = title + (pending && !undecided ? " is pending." : " was discussed; no decision was reached.")
                if next { bullet += " It will be taken up at the next meeting." }
                drafts[topic].issueBullets.append(bullet)
                result.append(MinutesOpenIssue(text: text, subject: title, topic: drafts[topic].title, nextMeeting: next,
                                               evidence: point.evidence, timestamp: turn?.start, speaker: speakerName(turn)))
            }
            return result
        }

        func addOpinionBullets() {
            for opinion in input.hindi.opinions {
                guard let topic = topicIndex(related: opinion.subject) else { continue }
                let reason = opinion.reason.map { " for its " + $0 } ?? ""
                let subject = HindiText.capitalizeFirst((hasDeterminerPublic(opinion.subject) ? "" : "the ") + opinion.subject)
                let bullet = subject + " was preferred" + reason + "."
                let exists = drafts[topic].preferenceBullets.contains { $0.lowercased() == bullet.lowercased() }
                if !exists { drafts[topic].preferenceBullets.append(bullet) }
                if let index = indexByID[opinion.evidence.turnID] { drafts[topic].otherTurns.append(index) }
            }
        }

        // MARK: Actions

        func canonicalOwner(_ owner: String?) -> String? {
            guard var name = owner?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            if SpeakerNameInference.isGenericLabel(name) { return nil }
            if HindiText.containsDevanagari(name) { name = HindiText.transliterate(name) }
            let people = input.participants.filter { !SpeakerNameInference.isGenericLabel($0) }
            return HindiText.matchParticipant(name, participants: people) ?? name
        }

        func buildAction(_ task: SuggestedTask) -> MinutesAction {
            let turn = firstTurn(task.evidence)
            let owner = canonicalOwner(task.owner)
            var deadline = task.deadlineText
            var baseTitle = task.title
            // A deadline phrase left inside a model-written title belongs in the deadline, not the title.
            let split = ActionExtractor.splitDeadline(baseTitle)
            if let found = split.deadline {
                let cleaned = MeetingAnalysisReducer.polishedTask(split.text)
                if MeetingAnalysisReducer.isSubstantive(cleaned) {
                    baseTitle = cleaned
                    if deadline == nil {
                        deadline = TaskGrounding.verifiedDeadline(found, in: task.evidence.map(\.quote))
                    }
                }
            }
            var due: String?
            if let deadline = deadline {
                due = DueDateResolver.resolve(deadline, meetingDate: input.meetingDate, timeZone: input.timeZone)
            }
            let topic = topicIndex(related: task.title).map { drafts[$0].title }
            // The minutes are written in English, so a Devanagari deadline ("फ्राइडे तक") reads "by Friday".
            let shownDeadline = deadline.map { HindiText.containsDevanagari($0) ? MinutesComposer.englishDeadline($0) : $0 }
            return MinutesAction(title: baseTitle, owner: owner, deadlineText: shownDeadline, dueDate: due, topic: topic,
                                 evidence: task.evidence, timestamp: turn?.start, speaker: speakerName(turn))
        }

        // MARK: Topics and summary

        func finalizeTopics() -> [MinutesTopic] {
            let ordered = drafts.sorted { lhs, rhs in
                if lhs.sortKey != rhs.sortKey { return lhs.sortKey < rhs.sortKey }
                return lhs.firstSeen < rhs.firstSeen
            }
            var topics: [MinutesTopic] = []
            for draft in ordered {
                var bullets: [String] = []
                var seen = Set<String>()
                for bullet in draft.preferenceBullets + draft.agreedBullets + draft.issueBullets where seen.insert(bullet.lowercased()).inserted {
                    bullets.append(bullet)
                }
                if bullets.isEmpty { bullets = [draft.title + " was discussed."] }
                var evidence = draft.outcomeEvidence
                if evidence.isEmpty, let own = draft.ownEvidence { evidence = [own] }
                let turn = firstTurn(evidence)
                topics.append(MinutesTopic(title: draft.title, discussion: bullets, outcome: draft.outcome, evidence: evidence,
                                           timestamp: turn?.start, speaker: speakerName(turn)))
            }
            return topics
        }

        func summaryNames() -> [String] {
            var names: [String] = []
            for name in input.participants where !SpeakerNameInference.isGenericLabel(name) && !names.contains(name) {
                names.append(name)
            }
            if names.isEmpty {
                for name in input.speakerNames.values.sorted() where !names.contains(name) { names.append(name) }
            }
            if names.isEmpty {
                for task in input.tasks {
                    if let owner = canonicalOwner(task.owner), !names.contains(owner) { names.append(owner) }
                }
            }
            return names
        }

        func buildSummary(topics: [MinutesTopic], issues: [MinutesOpenIssue]) -> String {
            let titles = topics.prefix(5).map { $0.title }
            var phrases: [String] = []
            for decision in input.decisions where !HindiText.looksHindi(decision.text) {
                phrases.append(MinutesBuilder.shortPhrase(decision.text))
            }
            var subjects: [String] = []
            for issue in issues where issue.topic != nil && !HindiText.looksHindi(issue.subject) && issue.subject.count <= 60 {
                subjects.append(issue.subject)
            }
            var overview = MinutesComposer.executiveSummary(names: summaryNames(), topics: Array(titles),
                decisionPhrases: phrases, tasks: input.tasks, openSubjects: subjects)
            if issues.contains(where: { $0.topic == nil }) {
                if !overview.isEmpty { overview += " " }
                overview += "Review the open questions for details that still need clarification."
            }
            guard titles.isEmpty || !input.rankedDiscussion.isEmpty else { return overview }
            let outcomeTurns = Set((input.decisions.flatMap(\.evidence) + input.openIssues.flatMap(\.evidence)
                + input.tasks.flatMap(\.evidence)).map(\.turnID))
            var selectedText = Set<String>()
            let context = (input.rankedDiscussion + input.discussion).filter { point in
                !HindiText.looksHindi(point.text) && !point.evidence.isEmpty
                    && MeetingAnalysisReducer.isSummaryContext(point.text)
                    && point.evidence.contains { !outcomeTurns.contains($0.turnID) }
                    && selectedText.insert(MeetingAnalysisReducer.clauseKey(point.text)).inserted
            }.prefix(2).map { point in
                let text = point.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.last.map { ".!?".contains($0) } == true ? text : text + "."
            }
            return (Array(context) + [overview]).filter { !$0.isEmpty }.joined(separator: " ")
        }
    }
}
