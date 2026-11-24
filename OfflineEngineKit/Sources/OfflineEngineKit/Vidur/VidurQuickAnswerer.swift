import Foundation

/// Vidur's instant tiers (0 and 1): answers from the saved minutes, tasks and transcripts of any number
/// of meetings, without a model. Everything is in memory, so it returns in milliseconds.
///
/// - Understands English, Hinglish and Devanagari questions (intent words, names, dates).
/// - Matches names and topic words across scripts ("Pawan" finds the Devanagari spelling).
/// - Writes a short English answer and attaches the minutes item or transcript turn it came from.
public enum VidurQuickAnswerer {
    public static let defaultSuggestions = [
        "What did we decide?", "Which tasks are still open?", "Summarize the last meeting"
    ]

    public static func answer(question rawQuestion: String, records: [VidurMeetingRecord],
                              history: [VidurChatTurn] = [], selfNames: [String] = [],
                              now: Date = Date(), calendar: Calendar = .current,
                              currentMeetingID: UUID? = nil) -> VidurQuickAnswer {
        let found = resolve(question: rawQuestion, records: records, history: history, selfNames: selfNames,
                            now: now, calendar: calendar, currentMeetingID: currentMeetingID)
        return naturalized(found, calendar: calendar)
    }

    /// ISO timestamps never reach the screen: "2026-11-23T12:59:41Z" is shown as "Mon 23 Nov at 12:59 PM".
    private static func naturalized(_ answer: VidurQuickAnswer, calendar: Calendar) -> VidurQuickAnswer {
        func natural(_ text: String) -> String { VidurNaturalDates.rewrite(text, calendar: calendar) }
        var copy = answer
        let text = natural(answer.text)
        let changedSources = answer.sources.contains { natural($0.quote) != $0.quote }
        let changedTasks = answer.tasks.contains { natural($0.title) != $0.title }
        guard text != answer.text || changedSources || changedTasks else { return answer }
        let sources = answer.sources.map { source in
            VidurQuickSource(meetingID: source.meetingID, meetingTitle: source.meetingTitle, meetingDate: source.meetingDate,
                             label: source.label, timestamp: source.timestamp, quote: natural(source.quote),
                             speaker: source.speaker)
        }
        let tasks = answer.tasks.map { task in
            VidurQuickTask(title: natural(task.title), owner: task.owner, dueDate: task.dueDate, dueText: task.dueText,
                           isCompleted: task.isCompleted, meetingID: task.meetingID, meetingTitle: task.meetingTitle)
        }
        copy = VidurQuickAnswer(text: text, sources: sources, people: answer.people, tasks: tasks,
                                confidence: answer.confidence, intent: answer.intent, suggestions: answer.suggestions,
                                meetingTitles: answer.meetingTitles, wantsReasoning: answer.wantsReasoning,
                                foundNothing: answer.foundNothing)
        return copy
    }

    private static func resolve(question rawQuestion: String, records: [VidurMeetingRecord],
                                history: [VidurChatTurn], selfNames: [String], now: Date, calendar: Calendar,
                                currentMeetingID: UUID?) -> VidurQuickAnswer {
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = answerOnce(question: question, records: records, history: history, selfNames: selfNames,
                               now: now, calendar: calendar, currentMeetingID: currentMeetingID)
        if first.confidence == .complete, !first.foundNothing { return first }

        // A typo ("thevpresentation", "pawans") can make a good question look empty. Try the repaired
        // question, and keep it only when it finds more than the question as typed.
        let usable = records.filter(\.hasContent)
        let repaired = VidurQuestionNormalizer.normalize(question, records: usable, names: selfNames)
        guard repaired != question else { return first }
        var repairedHistory: [VidurChatTurn] = []
        for turn in history {
            let fixed = VidurQuestionNormalizer.normalize(turn.question, records: usable, names: selfNames)
            repairedHistory.append(VidurChatTurn(question: fixed, answer: turn.answer))
        }
        let second = answerOnce(question: repaired, records: records, history: repairedHistory, selfNames: selfNames,
                                now: now, calendar: calendar, currentMeetingID: currentMeetingID)
        return strength(second) > strength(first) ? second : first
    }

    private static func strength(_ answer: VidurQuickAnswer) -> Int {
        if answer.foundNothing { return 0 }
        switch answer.confidence {
        case .complete: return 3
        case .partial: return 2
        case .notFound: return 0
        }
    }

    private static func answerOnce(question: String, records: [VidurMeetingRecord], history: [VidurChatTurn],
                                   selfNames: [String], now: Date, calendar: Calendar,
                                   currentMeetingID: UUID?) -> VidurQuickAnswer {
        let usable = records.filter(\.hasContent).sorted { $0.date < $1.date }

        var names: [String] = selfNames
        var seen = Set<String>()
        func add(_ name: String?) {
            guard let name, !name.isEmpty, seen.insert(name).inserted else { return }
            names.append(name)
        }
        for record in usable {
            record.attendees.forEach { add($0) }
            record.absent.forEach { add($0) }
            record.tasks.forEach { add($0.owner) }
            record.decisions.forEach { add($0.speaker) }
            record.openIssues.forEach { add($0.speaker) }
            record.turns.forEach { add($0.speaker) }
        }
        let index = VidurPersonIndex(names: names)
        let selfPerson = selfNames.lazy.compactMap { index.person(forRaw: $0) }.first

        var titles: [String] = []
        for record in usable where !titles.contains(record.title) { titles.append(record.title) }
        var parsed = VidurQuestionParser.parse(question, index: index, titles: titles, now: now, calendar: calendar)
        if let previous = history.last?.question, isFollowUp(parsed) {
            let before = VidurQuestionParser.parse(previous, index: index, titles: titles, now: now, calendar: calendar)
            parsed = merge(parsed, with: before)
        }

        guard !usable.isEmpty else {
            return finish(sections: [], parsed: parsed, usable: usable, suggestions: [],
                          fallback: "You have no saved meetings with minutes or a transcript yet.",
                          confidence: .complete, intent: .topic)
        }

        // Scope: the meetings the question is about.
        var scoped = usable
        if !parsed.matchedTitles.isEmpty { scoped = scoped.filter { parsed.matchedTitles.contains($0.title) } }
        if let range = parsed.meetingRange { scoped = scoped.filter { range.contains($0.date) } }
        if parsed.lastMeeting, let last = scoped.last { scoped = [last] }
        guard !scoped.isEmpty else {
            let label = parsed.rangeLabel ?? "in that period"
            return finish(sections: [], parsed: parsed, usable: usable, suggestions: [],
                          fallback: "I couldn\u{2019}t find any meetings \(label).", confidence: .complete,
                          intent: parsed.intents.first ?? .topic)
        }

        if parsed.intents.contains(.attendees) { parsed.intents.removeAll { $0 == .absent } }
        var context = VidurQuickContext(records: scoped, parsed: parsed, index: index, selfPerson: selfPerson,
                                        now: now, calendar: calendar)
        context.currentMeetingID = currentMeetingID
        var sections: [VidurSection] = []
        var missing: [String] = []
        var missingIsFinal = parsed.residual.isEmpty
        let dataIntents: Set<VidurQuickIntent> = [.tasks, .attendees, .absent, .agenda, .duration, .date, .meetingList, .nextMeeting]
        for intent in parsed.intents {
            guard let section = VidurQuickSections.render(intent, context, allRecords: usable) else { continue }
            if section.isEmpty {
                missing.append(section.text)
                if !dataIntents.contains(intent) { missingIsFinal = false }
            } else {
                sections.append(section)
            }
        }

        // Nothing structured to show: search the topic words (and the person) in minutes and transcripts.
        if sections.isEmpty, !parsed.residual.isEmpty || parsed.intents.contains(.topic) {
            if let found = VidurTopicSearch.search(context, original: parsed) { sections.append(found) }
        }

        return finish(sections: sections, parsed: parsed, usable: scoped, suggestions: suggestions(index: index, parsed: parsed),
                      fallback: missing.first, confidence: (missingIsFinal && sections.isEmpty && !missing.isEmpty) ? VidurQuickConfidence.complete : nil,
                      intent: parsed.intents.first ?? .topic)
    }

    // MARK: Follow-ups

    static func isFollowUp(_ parsed: VidurParsedQuestion) -> Bool {
        guard parsed.wordCount <= 8 else { return false }
        if parsed.intents == [.topic] {
            return parsed.followUpCue || (!parsed.people.isEmpty && parsed.residual.isEmpty)
        }
        return parsed.pronounCue
    }

    /// A short follow-up ("and Neha?", "what about pricing?") borrows what it leaves out from the previous question.
    static func merge(_ current: VidurParsedQuestion, with previous: VidurParsedQuestion) -> VidurParsedQuestion {
        var result = current
        let currentIsOpen = current.intents == [.topic]
        let carriesTopic: Set<VidurQuickIntent> = [.tasks, .decisions, .openIssues, .topic]
        if currentIsOpen { result.intents = previous.intents }
        if result.people.isEmpty { result.people = previous.people }
        if result.residual.isEmpty, result.intents.contains(where: { carriesTopic.contains($0) }) {
            result.residual = previous.residual
        }
        if result.meetingRange == nil, result.dueRange == nil {
            result.meetingRange = previous.meetingRange
            result.dueRange = previous.dueRange
            result.rangeLabel = previous.rangeLabel
        }
        if !result.lastMeeting { result.lastMeeting = previous.lastMeeting }
        if result.matchedTitles.isEmpty { result.matchedTitles = previous.matchedTitles }
        if result.taskFilter == .all { result.taskFilter = previous.taskFilter }
        if previous.asksForSelf, current.people.isEmpty { result.asksForSelf = true }
        return result
    }

    // MARK: Assembly

    private static func suggestions(index: VidurPersonIndex, parsed: VidurParsedQuestion) -> [String] {
        var list = defaultSuggestions
        if let person = parsed.people.first ?? index.people.first {
            list.append("What is \(person.canonical) working on?")
        }
        return list
    }

    private static func finish(sections: [VidurSection], parsed: VidurParsedQuestion, usable: [VidurMeetingRecord],
                               suggestions: [String], fallback: String?, confidence forced: VidurQuickConfidence?,
                               intent: VidurQuickIntent) -> VidurQuickAnswer {
        let reasoning = parsed.wantsReasoning
        guard !sections.isEmpty else {
            let text: String
            if let fallback {
                text = fallback
            } else if !parsed.residual.isEmpty {
                text = "I couldn\u{2019}t find anything about \u{201C}\(parsed.residual.joined(separator: " "))\u{201D} in your meetings."
            } else if let person = parsed.people.first {
                text = "I couldn\u{2019}t find anything from \(person.canonical) in your meetings."
            } else {
                text = "I couldn\u{2019}t find that in your meetings."
            }
            return VidurQuickAnswer(text: text, sources: [], people: [], tasks: [], confidence: forced ?? .notFound,
                                    intent: intent, suggestions: suggestions, meetingTitles: [], wantsReasoning: reasoning,
                                    foundNothing: true)
        }
        var text = sections.map(\.text).joined(separator: "\n\n")
        var sources: [VidurQuickSource] = []
        var seenSources = Set<String>()
        for source in sections.flatMap(\.sources) {
            let key = "\(source.meetingID)|\(source.label ?? "")|\(source.timestamp ?? -1)|\(source.quote)"
            if seenSources.insert(key).inserted, sources.count < 5 { sources.append(source) }
        }
        var people: [String] = []
        for name in sections.flatMap(\.people) where !people.contains(name) && people.count < 4 { people.append(name) }
        let tasks = Array(sections.flatMap(\.tasks).prefix(4))
        var titles: [String] = []
        for source in sources where !titles.contains(source.meetingTitle) { titles.append(source.meetingTitle) }
        let complete = sections.allSatisfy(\.isComplete)
        if !complete, let extra = fallback, !extra.isEmpty, sections.count < parsed.intents.count { text += "\n\n" + extra }
        return VidurQuickAnswer(text: text, sources: sources, people: people, tasks: tasks,
                                confidence: forced ?? (complete ? .complete : .partial),
                                intent: sections[0].intent, suggestions: [], meetingTitles: titles, wantsReasoning: reasoning)
    }
}
