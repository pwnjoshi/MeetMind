import Foundation

/// Checks the owner and deadline of a model-proposed task against the transcript turns it cites.
/// A small model often copies the owner or the deadline of a neighbouring task ("Pawan", "Friday")
/// onto a task whose own turn names somebody else or another day. Such a value is dropped, so the
/// deterministic task for the same sentence supplies the right one.
enum TaskGrounding {
    struct Source {
        let turns: [String: AnalysisTurn]
        /// Named attendees: the participant list plus the names given to voices. Never generic labels.
        let persons: [String]
    }

    static func source(turns: [AnalysisTurn], participants: [String], speakerNames: [String: String]) -> Source {
        var byID: [String: AnalysisTurn] = [:]
        for turn in turns where byID[turn.id] == nil { byID[turn.id] = turn }
        var candidates: [String] = participants
        candidates.append(contentsOf: speakerNames.values.sorted())
        var persons: [String] = []
        for name in candidates {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || SpeakerNameInference.isGenericLabel(trimmed) { continue }
            let lowered = trimmed.lowercased()
            if persons.contains(where: { $0.lowercased() == lowered }) { continue }
            persons.append(trimmed)
        }
        return Source(turns: byID, persons: persons)
    }

    /// The full text of every turn the evidence cites (a quote stands in for an unknown turn).
    static func citedText(_ evidence: [SourceEvidence], _ source: Source) -> String {
        var parts: [String] = []
        var seen = Set<String>()
        for item in evidence {
            if let turn = source.turns[item.turnID] {
                if seen.insert(turn.id).inserted { parts.append(turn.text) }
            } else {
                parts.append(item.quote)
            }
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Owner

    private static func nameWords(_ name: String) -> [String] {
        name.lowercased().split(whereSeparator: { $0.isWhitespace }).map { String($0) }
    }

    private static func isName(_ item: HindiToken, _ name: String) -> Bool {
        if item.isDevanagari {
            if item.isKnown { return false }
            return HindiText.matchParticipant(item.raw, participants: [name]) != nil
        }
        let word = item.raw.lowercased()
        guard word.count >= 2 else { return false }
        return nameWords(name).contains(word)
    }

    /// True when the text says the name, in Latin or Devanagari spelling.
    static func mentions(_ name: String, in text: String) -> Bool {
        for item in HindiText.tokenize(text) where isName(item, name) { return true }
        return false
    }

    static func mentionedPersons(in text: String, persons: [String]) -> [String] {
        let tokens = HindiText.tokenize(text)
        var found: [String] = []
        for person in persons {
            for item in tokens where isName(item, person) {
                found.append(person)
                break
            }
        }
        return found
    }

    static func samePerson(_ lhs: String, _ rhs: String) -> Bool {
        if lhs.lowercased() == rhs.lowercased() { return true }
        if HindiText.namesMatch(lhs, rhs) { return true }
        return !Set(nameWords(lhs)).isDisjoint(with: Set(nameWords(rhs)))
    }

    /// The owner when the cited turns do not point at somebody else. A turn that names another attendee
    /// and never names the owner is a request to that other attendee, so the owner is dropped.
    static func groundedOwner(_ owner: String?, evidence: [SourceEvidence], source: Source) -> String? {
        guard let owner = owner else { return nil }
        let text = citedText(evidence, source)
        if mentions(owner, in: text) { return owner }
        let mentioned = mentionedPersons(in: text, persons: source.persons)
        for person in mentioned where !samePerson(person, owner) { return nil }
        return owner
    }

    // MARK: - Deadline

    private static let hindiWeekdaySpellings: [(String, String)] = [
        ("somwar", "monday"), ("somvar", "monday"), ("mangalwar", "tuesday"), ("mangalvar", "tuesday"),
        ("budhwar", "wednesday"), ("budhvar", "wednesday"), ("guruwar", "thursday"), ("guruvar", "thursday"),
        ("brihaspatiwar", "thursday"), ("shukrawar", "friday"), ("shukravar", "friday"), ("shaniwar", "saturday"),
        ("shanivar", "saturday"), ("raviwar", "sunday"), ("ravivar", "sunday")
    ]

    private static func hindiWeekday(_ item: HindiToken) -> String? {
        if item.isDevanagari && item.isKnown { return nil }
        let candidate = item.isDevanagari ? HindiText.transliterate(item.raw) : item.raw
        guard candidate.count >= 5 else { return nil }
        let shape = HindiText.skeleton(candidate)
        guard !shape.isEmpty else { return nil }
        for entry in hindiWeekdaySpellings where HindiText.skeleton(entry.0) == shape { return entry.1 }
        return nil
    }

    private static func dayNumber(_ key: String) -> String? {
        if Int(key) != nil { return key }
        for suffix in ["st", "nd", "rd", "th"] where key.hasSuffix(suffix) {
            let head = String(key.dropLast(2))
            if !head.isEmpty, Int(head) != nil { return head }
        }
        return nil
    }

    /// The days and dates a text names: weekdays, "tomorrow" (kal), "today" (aaj), months and, next to a
    /// month, day numbers. Loanword spellings are resolved first ("फ्राइडे" is Friday, "कल" is tomorrow).
    static func timeIdentity(_ text: String) -> Set<String> {
        var days = Set<String>()
        var months = Set<String>()
        var numbers = Set<String>()
        for item in HindiText.tokenize(text) {
            let key = item.key
            if HindiText.weekdays.contains(key) {
                days.insert(key)
            } else if HindiText.months.contains(key) {
                months.insert(key)
            } else if let number = dayNumber(key) {
                numbers.insert(number)
            } else if key == "kal" || key == "tomorrow" {
                days.insert("tomorrow")
            } else if key == "aaj" || key == "today" {
                days.insert("today")
            } else if key == "parso" {
                days.insert("parso")
            } else if key == "tonight" {
                days.insert("tonight")
            } else if let weekday = hindiWeekday(item) {
                days.insert(weekday)
            }
        }
        var result = days.union(months)
        if !months.isEmpty { result.formUnion(numbers) }
        return result
    }

    /// The deadline when the cited turns name the same day or date. A deadline that names no day (for
    /// example "ASAP") cannot be checked and is kept.
    static func groundedDeadline(_ deadline: String?, evidence: [SourceEvidence], source: Source) -> String? {
        guard let deadline = deadline else { return nil }
        let wanted = timeIdentity(deadline)
        if wanted.isEmpty { return deadline }
        let available = timeIdentity(citedText(evidence, source))
        return wanted.isSubset(of: available) ? deadline : nil
    }

    static func anchored(_ task: SuggestedTask, _ source: Source) -> SuggestedTask {
        let owner = groundedOwner(task.owner, evidence: task.evidence, source: source)
        let deadline = groundedDeadline(task.deadlineText, evidence: task.evidence, source: source)
        if owner == task.owner && deadline == task.deadlineText { return task }
        return SuggestedTask(title: task.title, category: task.category, owner: owner, deadlineText: deadline,
                             priority: task.priority, evidence: task.evidence)
    }
}
