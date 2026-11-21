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

    private static func words(_ text: String) -> Set<String> {
        let generic: Set<String> = ["date", "the", "on", "go", "with", "finalize", "set", "to", "not", "yet", "decided",
                                    "is", "still", "pending", "be", "discussed", "in", "next", "meeting", "a", "of"]
        var result = Set<String>()
        for piece in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let word = String(piece)
            if !generic.contains(word) { result.insert(word) }
        }
        return result
    }

    private static func related(_ topic: String, _ text: String) -> Bool {
        let left = words(topic)
        let right = words(text)
        return !left.isDisjoint(with: right)
    }

    private static func unique(_ evidence: [SourceEvidence]) -> [SourceEvidence] {
        var seen = Set<String>()
        return evidence.filter { seen.insert($0.turnID + "\u{0}" + $0.quote).inserted }
    }

    private static func stripPeriod(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    // MARK: - Summary

    static func executiveSummary(names: [String], topics: [String], decisionPhrases: [String],
                                 tasks: [SuggestedTask], openSubjects: [String]) -> String {
        var sentences: [String] = []
        if !topics.isEmpty {
            let subject = names.isEmpty ? "The meeting covered" : list(names) + " discussed"
            let lowered = topics.map { HindiText.lowercaseFirst($0) }
            sentences.append(subject + " the " + list(lowered) + ".")
        }
        if !decisionPhrases.isEmpty {
            sentences.append("Decided to " + list(decisionPhrases.map { HindiText.lowercaseFirst(stripPeriod($0)) }) + ".")
        }
        if !tasks.isEmpty {
            var lines: [String] = []
            for task in tasks.prefix(4) {
                var line: String
                let title = HindiText.lowercaseFirst(task.title)
                if let owner = task.owner { line = owner + " will " + title } else { line = "To do: " + title }
                if let deadline = task.deadlineText { line += " " + englishDeadline(deadline) }
                lines.append(line)
            }
            var text = lines.joined(separator: "; ")
            if tasks.count > 4 { text += "; and \(tasks.count - 4) more" }
            sentences.append(HindiText.capitalizeFirst(text) + ".")
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
