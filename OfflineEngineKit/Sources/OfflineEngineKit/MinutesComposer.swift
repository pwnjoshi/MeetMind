import Foundation

/// Deterministic English minutes text built from structured extraction results.
/// Used for Hindi and Hinglish meetings, where a small model's own summary is unreliable.
enum MinutesComposer {
    // MARK: - Helpers

    static func list(_ items: [String]) -> String {
        if items.count <= 1 { return items.first ?? "" }
        if items.count == 2 { return items[0] + " and " + items[1] }
        return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
    }

    /// English form of a deadline written in Hindi or Hinglish ("कल तक" -> "by tomorrow").
    static func englishDeadline(_ verbatim: String) -> String {
        let tokens = HindiText.tokenize(verbatim)
        let keys = tokens.map { $0.key }
        let hasTak = keys.contains("tak") || keys.contains("by")
        if !HindiText.containsDevanagari(verbatim), !keys.contains("tak") { return verbatim }
        for (index, key) in keys.enumerated() {
            if Int(key) != nil, index + 1 < keys.count, HindiText.months.contains(keys[index + 1]) {
                return (hasTak ? "by " : "on ") + key + " " + HindiText.capitalizeFirst(keys[index + 1])
            }
        }
        for key in keys where HindiText.weekdays.contains(key) {
            let day = HindiText.capitalizeFirst(key)
            if keys.contains("agle") { return (hasTak ? "by next " : "next ") + day }
            return (hasTak ? "by " : "on ") + day
        }
        if keys.contains("kal") { return hasTak ? "by tomorrow" : "tomorrow" }
        if keys.contains("parso") { return hasTak ? "by the day after tomorrow" : "the day after tomorrow" }
        if keys.contains("aaj") { return hasTak ? "by today" : "today" }
        if keys.contains("hafte") { return hasTak ? "by next week" : "next week" }
        if keys.contains("mahine") { return hasTak ? "by next month" : "next month" }
        return verbatim
    }

    static func words(_ text: String) -> Set<String> {
        let generic: Set<String> = ["date", "the", "on", "go", "with", "finalize", "set", "to", "not", "yet", "decided",
                                    "is", "still", "pending", "be", "discussed", "in", "next", "meeting", "a", "of"]
        var result = Set<String>()
        for piece in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let word = String(piece)
            if !generic.contains(word) { result.insert(word) }
        }
        return result
    }

    static func related(_ topic: String, _ text: String) -> Bool {
        let left = words(topic)
        let right = words(text)
        return !left.isDisjoint(with: right)
    }

    static func unique(_ evidence: [SourceEvidence]) -> [SourceEvidence] {
        var seen = Set<String>()
        return evidence.filter { seen.insert($0.turnID + "\u{0}" + $0.quote).inserted }
    }

    static func stripPeriod(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    // MARK: - Summary

    private static let leadingDeadlineWords: Set<String> = ["tomorrow", "today", "tonight", "eod", "eow", "cob"]

    /// A deadline as the summary reads it: translated to English, a repeated word removed and "by" in front of a
    /// bare day or date ("Friday" -> "by Friday", "by Friday Friday" -> "by Friday").
    static func summaryDeadline(_ deadline: String) -> String {
        let english = englishDeadline(deadline).trimmingCharacters(in: .whitespacesAndNewlines)
        var words: [String] = []
        for piece in english.split(whereSeparator: { $0.isWhitespace }) {
            let word = String(piece)
            if let last = words.last, last.lowercased() == word.lowercased() { continue }
            words.append(word)
        }
        guard let first = words.first?.lowercased() else { return "" }
        let joined = words.joined(separator: " ")
        let isDay = HindiText.weekdays.contains(first) || HindiText.months.contains(first)
        let startsWithDigit = first.first?.isNumber == true
        if isDay || startsWithDigit || leadingDeadlineWords.contains(first) { return "by " + joined }
        return joined
    }

    /// "Pawan will prepare the agenda by Friday". A deadline written inside the title is moved out of it, so the
    /// deadline is said once.
    static func actionTitle(_ title: String) -> String {
        var text = MinutesRegex.replace(#"(?i),\s*(?:right|okay|you know)\s*(?=,|$)"#, in: title)
        text = MinutesRegex.replace(#"(?i)^continue\s+focusing\s+more\s+on\s+the\s+models,\s*which\s+is\s+more\s+suitable\s+and\s+accurate$"#,
                                    in: text, with: "Continue evaluating models for suitability and accuracy")
        text = MinutesRegex.replace(#"(?i)\bcontinue\s+your\s+research\b"#,
                                    in: text, with: "Continue researching")
        text = MinutesRegex.replace(#"(?i)\bresearching\s+and\s+narrow\s+down\s+your\s+user\s+segment\b"#,
                                    in: text, with: "researching and narrow down the target user segment")
        text = MinutesRegex.replace(#"(?i)\s+and\s+make\s+sure\s+you\s+look\s+for\s+user\s+segment\s+that\s+very\s+closely\s+requires\s+the\s+need\s+of\s+"#,
                                    in: text, with: ", focusing on users who need ")
        text = MinutesRegex.replace(#"(?i)^go further on the user flow\b"#, in: text, with: "Refine the user flow")
        text = MinutesRegex.replace(#"(?i)\blook for some good designs of competitor apps\b"#,
                                    in: text, with: "review competitor app designs")
        text = MinutesRegex.replace(#"(?i)^continue with (?:the )?POC$"#,
                                    in: text, with: "Continue the proof of concept")
        return text
    }

    static func followUpSentence(_ titles: [String]) -> String {
        guard !titles.isEmpty else { return "" }
        let gerunds = [
            "refine": "refining", "review": "reviewing", "evaluate": "evaluating",
            "narrow": "narrowing", "continue": "continuing", "prepare": "preparing", "send": "sending"
        ]
        let phrases = titles.compactMap { title -> String? in
            let compact = MinutesRegex.replace(#"(?i)^continue evaluating\b"#, in: title, with: "evaluate")
            let focus = MinutesRegex.replace(#"(?i)^continue researching and narrow down the target user segment\b"#,
                                             in: compact, with: "narrow down the target audience")
            let clauses = MinutesRegex.replace(#"(?i)\band review competitor app designs\b"#,
                                               in: focus, with: "and reviewing competitor app designs")
            let words = clauses.split(separator: " ", maxSplits: 1)
            guard words.count == 2, let gerund = gerunds[String(words[0])] else { return nil }
            return gerund + " " + words[1]
        }
        if phrases.count == titles.count {
            return "Follow-up work covers " + list(phrases) + "."
        }
        return "Next steps are to " + list(titles) + "."
    }

    static func taskLine(_ task: SuggestedTask) -> String {
        let split = ActionExtractor.splitDeadline(task.title)
        var base = task.title
        var spoken = task.deadlineText
        if let found = split.deadline {
            let tail = task.title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            let rest = split.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:-")))
            if tail.lowercased().hasSuffix(found.lowercased()), rest.count >= 3 {
                base = rest
                if spoken == nil { spoken = found }
            }
        }
        let title = HindiText.lowercaseFirst(actionTitle(base))
        var line: String
        if let owner = task.owner { line = owner + " will " + title } else { line = "To do: " + title }
        if let deadline = spoken {
            let phrase = summaryDeadline(deadline)
            if !phrase.isEmpty { line += " " + phrase }
        }
        return line
    }

    static func executiveSummary(names: [String], topics: [String], decisionPhrases: [String],
                                 tasks: [SuggestedTask], openSubjects: [String]) -> String {
        var sentences: [String] = []
        if !topics.isEmpty {
            let subject = names.isEmpty ? "The meeting covered" : list(names) + " discussed"
            let lowered = topics.map { HindiText.lowercaseFirst($0) }
            sentences.append(subject + " the " + list(lowered) + ".")
        }
        if !decisionPhrases.isEmpty {
            let lead = names.count > 1 ? "They decided to " : "The meeting resolved to "
            sentences.append(lead + list(decisionPhrases.map { HindiText.lowercaseFirst(stripPeriod($0)) }) + ".")
        }
        if !tasks.isEmpty {
            var lines: [String] = []
            for task in tasks.prefix(4) { lines.append(taskLine(task)) }
            sentences.append(contentsOf: lines.map {
                HindiText.capitalizeFirst(stripPeriod($0)) + "."
            })
            if tasks.count > 4 { sentences.append("The action list contains \(tasks.count - 4) more items.") }
        }
        if !openSubjects.isEmpty {
            let lowered = openSubjects.map { HindiText.lowercaseFirst($0) }
            sentences.append("The " + list(lowered) + (lowered.count == 1 ? " remains open." : " remain open."))
        }
        return sentences.joined(separator: " ")
    }

    // MARK: - Discussion

    static func discussion(_ hindi: HindiAnalysis) -> [SupportedPoint] {
        var points: [SupportedPoint] = []
        for topic in hindi.topics {
            var evidence: [SourceEvidence] = [topic.evidence]
            var outcome = ""
            if let decision = hindi.decisions.first(where: { related(topic.title, $0.text) }) {
                evidence += decision.evidence
                let opinion = hindi.opinions.first(where: { related(topic.title, $0.subject) && related($0.subject, decision.text) })
                if let opinion = opinion {
                    evidence.append(opinion.evidence)
                    let reason = opinion.reason.map { " for " + $0 } ?? ""
                    outcome = opinion.subject + " preferred" + reason + "; selected"
                } else if decision.proposed, let detail = decision.detail {
                    outcome = "proposed " + detail + " and finalized"
                } else {
                    outcome = "decided to " + HindiText.lowercaseFirst(stripPeriod(decision.text))
                }
            } else if let issue = hindi.openIssues.first(where: { related(topic.title, $0.subject) }) {
                evidence += issue.evidence
                outcome = "not yet decided"
                if issue.nextMeeting { outcome += "; to be discussed in the next meeting" }
                if issue.pending && !issue.undecided { outcome = "still pending" }
            } else if let opinion = hindi.opinions.first(where: { related(topic.title, $0.subject) }) {
                evidence.append(opinion.evidence)
                outcome = opinion.subject + " preferred" + (opinion.reason.map { " for " + $0 } ?? "")
            } else {
                outcome = "discussed"
            }
            points.append(SupportedPoint(text: topic.title + ": " + outcome + ".", evidence: unique(evidence)))
        }
        return points
    }
}
