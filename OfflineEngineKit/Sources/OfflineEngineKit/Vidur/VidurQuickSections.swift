import Foundation

/// Renders the answer for one intent from the saved minutes, tasks and attendance.
enum VidurQuickSections {
    static let maximumRows = 6

    static func render(_ intent: VidurQuickIntent, _ context: VidurQuickContext, allRecords: [VidurMeetingRecord]) -> VidurSection? {
        switch intent {
        case .tasks: return tasks(context)
        case .decisions: return lines(context, intent: .decisions)
        case .openIssues: return lines(context, intent: .openIssues)
        case .attendees: return attendance(context, absentOnly: false)
        case .absent: return attendance(context, absentOnly: true)
        case .agenda: return agenda(context)
        case .summary: return summary(context)
        case .duration: return duration(context)
        case .date: return date(context)
        case .meetingList: return meetingList(context)
        case .nextMeeting: return nextMeeting(context, allRecords: allRecords)
        case .topic: return nil
        }
    }

    private static func empty(_ text: String, _ intent: VidurQuickIntent) -> VidurSection {
        VidurSection(text: text, isComplete: false, isEmpty: true, intent: intent)
    }

    // MARK: Tasks

    private static func tasks(_ context: VidurQuickContext) -> VidurSection {
        let parsed = context.parsed
        var owners = parsed.people
        var selfUnknown = false
        if owners.isEmpty, parsed.asksForSelf {
            if let me = context.selfPerson { owners = [me] } else { selfUnknown = true }
        }
        var rows: [(task: VidurMeetingTask, record: VidurMeetingRecord)] = []
        for record in context.records {
            for task in record.tasks { rows.append((task, record)) }
        }
        if !owners.isEmpty {
            rows = rows.filter { row in owners.contains { context.index.matches(row.task.owner, $0) } }
        }
        var hiddenDone = 0
        switch parsed.taskFilter {
        case .all:
            hiddenDone = rows.filter { $0.task.isCompleted }.count
            rows = rows.filter { !$0.task.isCompleted }
        case .open:
            rows = rows.filter { !$0.task.isCompleted }
        case .done:
            rows = rows.filter { $0.task.isCompleted }
        case .due:
            rows = rows.filter { row in
                guard !row.task.isCompleted else { return false }
                if let range = parsed.dueRange { return row.task.dueDate.map { range.contains($0) } ?? false }
                return row.task.dueDate != nil || !(row.task.dueText ?? "").isEmpty
            }
        case .overdue:
            rows = rows.filter { row in !row.task.isCompleted && (row.task.dueDate.map { $0 < context.now } ?? false) }
        }
        if !parsed.residual.isEmpty {
            rows = rows.filter { context.matchesTopic($0.task.title + " " + ($0.task.quote ?? "")) }
        }
        rows.sort { lhs, rhs in
            let left = lhs.task.dueDate ?? .distantFuture
            let right = rhs.task.dueDate ?? .distantFuture
            return left != right ? left < right : lhs.record.date < rhs.record.date
        }

        let you = owners.count == 1 && parsed.people.isEmpty
        let who: String? = owners.isEmpty ? nil : (you ? "You" : owners.map(\.canonical).joined(separator: " and "))
        let noun: String
        switch parsed.taskFilter {
        case .done: noun = "completed task"
        case .overdue: noun = "overdue task"
        case .due: noun = parsed.dueRange == nil ? "task with a due date" : "open task"
        case .all, .open: noun = "open task"
        }
        guard !rows.isEmpty else {
            let nounPlural = noun.replacingOccurrences(of: "task", with: "tasks")
            let about = parsed.residual.isEmpty ? "" : " about \(parsed.residual.joined(separator: " "))"
            if let who { return empty("\(who) \(you ? "have" : "has") no \(nounPlural)\(about) in \(context.scopeText).", .tasks) }
            return empty("There are no \(nounPlural)\(about) in \(context.scopeText).", .tasks)
        }

        if parsed.asksOwner, who == nil, !parsed.residual.isEmpty {
            return ownerAnswer(rows: rows, context: context)
        }

        var head: String
        let count = rows.count
        let nounText = noun.replacingOccurrences(of: "task", with: count == 1 ? "task" : "tasks")
        if let who {
            let verb = (you || owners.count > 1) ? "have" : "has"
            head = "\(who) \(verb) \(count) \(nounText)"
        } else {
            head = "There \(count == 1 ? "is" : "are") \(count) \(nounText)"
        }
        if let range = parsed.dueRange, let label = parsed.rangeLabel, range.duration > 0 { head += " due \(label)" }
        else if parsed.meetingRange != nil, let label = parsed.rangeLabel { head += " from \(label)" }
        if selfUnknown { head = "I don't know which name is yours, so this lists everyone. " + head }
        if parsed.taskFilter == .all, hiddenDone > 0 { head += " (\(hiddenDone) more already done)" }

        let shown = rows.prefix(maximumRows)
        var lines: [String] = []
        for row in shown {
            var details: [String] = []
            if who == nil, let owner = row.task.owner, !owner.isEmpty {
                details.append(context.index.person(forRaw: owner)?.canonical ?? owner)
            }
            if let due = row.task.dueDate { details.append("due \(context.dueDay(due))") }
            else if let text = row.task.dueText, !text.isEmpty { details.append("due \(text)") }
            if row.task.isSuggestion { details.append("suggested") }
            if context.isMultiple { details.append(VidurQuickContext.title(row.record)) }
            lines.append("\u{2022} " + row.task.title + (details.isEmpty ? "" : " (" + details.joined(separator: ", ") + ")"))
        }
        var text = head + ":\n" + lines.joined(separator: "\n")
        if rows.count > shown.count { text += "\n\u{2026}and \(rows.count - shown.count) more." }

        var sources: [VidurQuickSource] = []
        for row in shown where sources.count < 5 {
            sources.append(context.source(row.record, label: "Action", timestamp: row.task.timestamp,
                                          quote: row.task.quote ?? row.task.title, speaker: nil))
        }
        var people: [String] = []
        for row in shown {
            guard let owner = row.task.owner, !owner.isEmpty else { continue }
            let name = context.index.person(forRaw: owner)?.canonical ?? owner
            if !people.contains(name), people.count < 4 { people.append(name) }
        }
        let related = shown.map {
            VidurQuickTask(title: $0.task.title, owner: $0.task.owner, dueDate: $0.task.dueDate, dueText: $0.task.dueText,
                           isCompleted: $0.task.isCompleted, meetingID: $0.record.id,
                           meetingTitle: VidurQuickContext.title($0.record))
        }
        return VidurSection(text: text, sources: sources, people: people, tasks: related, isComplete: true, intent: .tasks)
    }

    // MARK: Decisions and open issues

    /// "Who owns the presentation?" answered from saved actions: "Neha \u{2014} Send the presentation (due Fri 21 Nov)".
    private static func ownerAnswer(rows: [(task: VidurMeetingTask, record: VidurMeetingRecord)],
                                    context: VidurQuickContext) -> VidurSection {
        let shown = Array(rows.prefix(3))
        var lines: [String] = []
        var sources: [VidurQuickSource] = []
        var people: [String] = []
        for row in shown {
            var owner = "No owner is set"
            if let raw = row.task.owner, !raw.isEmpty {
                owner = context.index.person(forRaw: raw)?.canonical ?? raw
                if !people.contains(owner) { people.append(owner) }
            }
            var line = owner + " \u{2014} " + row.task.title
            if let due = row.task.dueDate {
                line += " (due \(context.dueDay(due)))"
            } else if let text = row.task.dueText, !text.isEmpty {
                line += " (due \(text))"
            }
            lines.append(line)
            sources.append(context.source(row.record, label: "Action", timestamp: row.task.timestamp,
                                          quote: row.task.quote ?? row.task.title, speaker: nil))
        }
        var text = lines[0]
        if lines.count > 1 { text = lines.map { "\u{2022} " + $0 }.joined(separator: "\n") }
        let related = shown.map {
            VidurQuickTask(title: $0.task.title, owner: $0.task.owner, dueDate: $0.task.dueDate, dueText: $0.task.dueText,
                           isCompleted: $0.task.isCompleted, meetingID: $0.record.id,
                           meetingTitle: VidurQuickContext.title($0.record))
        }
        return VidurSection(text: text, sources: sources, people: people, tasks: related, isComplete: true, intent: .tasks)
    }

    private static func lines(_ context: VidurQuickContext, intent: VidurQuickIntent) -> VidurSection {
        let isDecision = intent == .decisions
        let noun = isDecision ? "decision" : "open issue"
        let label = isDecision ? "Decision" : "Open issue"
        let parsed = context.parsed
        var rows: [(line: VidurMeetingLine, record: VidurMeetingRecord)] = []
        for record in context.records {
            for line in (isDecision ? record.decisions : record.openIssues) { rows.append((line, record)) }
        }
        // A listed decision needs a verb and something it acts on ("Let her come." is not one). The minutes stay as saved.
        if isDecision { rows = rows.filter { VidurDecisionText.isSubstantial($0.line.text) } }
        if !parsed.people.isEmpty {
            rows = rows.filter { row in
                parsed.people.contains { person in
                    context.index.matches(row.line.speaker, person) || context.index.mentions(row.line.text, person)
                }
            }
        }
        if !parsed.residual.isEmpty {
            rows = rows.filter { context.matchesTopic($0.line.text + " " + ($0.line.quote ?? "")) }
        }
        guard !rows.isEmpty else {
            let about = parsed.residual.isEmpty ? "" : " about \(parsed.residual.joined(separator: " "))"
            return empty("No \(noun)s\(about) are recorded in \(context.scopeText).", intent)
        }
        let shown = rows.prefix(maximumRows)
        var head: String
        if context.isMultiple {
            let meetings = Set(rows.map { $0.record.id }).count
            head = "\(VidurQuickContext.plural(rows.count, noun)) across \(VidurQuickContext.plural(meetings, "meeting"))"
        } else if let only = context.records.first {
            head = "\(VidurQuickContext.plural(rows.count, noun)) in \(context.label(only))"
        } else {
            head = VidurQuickContext.plural(rows.count, noun)
        }
        if !parsed.people.isEmpty { head += " involving \(parsed.people.map(\.canonical).joined(separator: " and "))" }
        var bullets: [String] = []
        for row in shown {
            var text = "\u{2022} " + row.line.text
            if context.isMultiple { text += " (\(context.label(row.record)))" }
            bullets.append(text)
        }
        var text = head + ":\n" + bullets.joined(separator: "\n")
        if rows.count > shown.count { text += "\n\u{2026}and \(rows.count - shown.count) more." }
        var sources: [VidurQuickSource] = []
        for row in shown where sources.count < 5 {
            sources.append(context.source(row.record, label: label, timestamp: row.line.timestamp,
                                          quote: row.line.quote ?? row.line.text, speaker: row.line.speaker))
        }
        var people: [String] = []
        for row in shown {
            guard let name = context.displayName(row.line.speaker), name != "Someone", !people.contains(name),
                  people.count < 4, !name.hasPrefix("Speaker ") else { continue }
            people.append(name)
        }
        return VidurSection(text: text, sources: sources, people: people, isComplete: true, intent: intent)
    }

    // MARK: Attendance

    private static func attendance(_ context: VidurQuickContext, absentOnly: Bool) -> VidurSection {
        let intent: VidurQuickIntent = absentOnly ? .absent : .attendees
        let recent = Array(context.records.suffix(5))
        guard !recent.isEmpty else { return empty("There is no meeting to check attendance for.", intent) }
        let parsed = context.parsed

        // "Was Pawan at the meeting?"
        if !parsed.people.isEmpty {
            var answers: [String] = []
            var complete = true
            for record in recent {
                for person in parsed.people {
                    let name = person.canonical
                    if record.attendees.contains(where: { context.index.matches($0, person) }) {
                        answers.append("Yes, \(name) was at \(context.label(record)).")
                    } else if record.absent.contains(where: { context.index.matches($0, person) }) {
                        answers.append("No, \(name) was marked absent from \(context.label(record)).")
                    } else if record.turns.contains(where: { context.index.matches($0.speaker, person) }) {
                        answers.append("Yes, \(name) spoke in \(context.label(record)).")
                    } else {
                        answers.append("\(name) is not listed for \(context.label(record)).")
                        complete = false
                    }
                }
            }
            let sources = recent.prefix(4).map {
                context.source($0, label: "Attendees", timestamp: nil,
                               quote: ($0.attendees + $0.absent).joined(separator: ", "), speaker: nil)
            }
            return VidurSection(text: answers.joined(separator: "\n"), sources: Array(sources),
                                people: parsed.people.map(\.canonical), isComplete: complete, intent: intent)
        }

        var lines: [String] = []
        var sources: [VidurQuickSource] = []
        var people: [String] = []
        var complete = true
        for record in recent {
            var present = record.attendees
            var presentIsSpeakers = false
            if present.isEmpty {
                var seen = Set<String>()
                for turn in record.turns {
                    guard let raw = turn.speaker, !VidurPersonIndex.isGenericLabel(raw) else { continue }
                    let name = context.index.person(forRaw: raw)?.canonical ?? raw
                    if seen.insert(name).inserted { present.append(name) }
                }
                presentIsSpeakers = !present.isEmpty
            }
            var parts: [String] = []
            if !absentOnly {
                if present.isEmpty {
                    parts.append("No attendees are saved")
                } else if presentIsSpeakers {
                    parts.append("People who spoke (\(present.count)): \(present.joined(separator: ", "))")
                } else {
                    let verb = record.attendanceRecorded ? "Present" : "Participants"
                    parts.append("\(verb) (\(present.count)): \(present.joined(separator: ", "))")
                }
            }
            if !record.absent.isEmpty {
                parts.append("Absent (\(record.absent.count)): \(record.absent.joined(separator: ", "))")
            } else if absentOnly {
                if record.attendanceRecorded { parts.append("No one is marked absent") }
                else { parts.append("Attendance was not confirmed"); complete = false }
            }
            guard !parts.isEmpty else { continue }
            let body = parts.joined(separator: ". ") + "."
            lines.append(context.isMultiple ? "\u{2022} \(context.label(record)): \(body)" : "\(context.label(record)): \(body)")
            sources.append(context.source(record, label: "Attendees", timestamp: nil,
                                          quote: (present + record.absent).joined(separator: ", "), speaker: nil))
            for name in present where !people.contains(name) && people.count < 4 { people.append(name) }
            if present.isEmpty && record.absent.isEmpty { complete = false }
        }
        guard !lines.isEmpty else { return empty("No attendance is saved for \(context.scopeText).", intent) }
        return VidurSection(text: lines.joined(separator: "\n"), sources: Array(sources.prefix(4)), people: people,
                            isComplete: complete, intent: intent)
    }

    // MARK: Agenda, summary, duration, date

    private static func agenda(_ context: VidurQuickContext) -> VidurSection {
        let withAgenda = context.records.filter { !$0.agenda.isEmpty }
        guard !withAgenda.isEmpty else { return empty("No agenda is saved for \(context.scopeText).", .agenda) }
        var parts: [String] = []
        for record in withAgenda.suffix(3) {
            parts.append("Agenda for \(context.label(record)):\n" + record.agenda.prefix(8).map { "\u{2022} \($0)" }.joined(separator: "\n"))
        }
        let sources = withAgenda.suffix(3).map {
            context.source($0, label: "Agenda", timestamp: nil, quote: $0.agenda.joined(separator: "; "), speaker: nil)
        }
        return VidurSection(text: parts.joined(separator: "\n\n"), sources: sources, isComplete: true, intent: .agenda)
    }

    private static func summary(_ context: VidurQuickContext) -> VidurSection {
        let recent = Array(context.records.suffix(context.isMultiple ? 6 : 1))
        guard !recent.isEmpty else { return empty("There is no meeting to summarize.", .summary) }
        if recent.count == 1, let record = recent.first {
            var text = "\(context.label(record)): "
            let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let points = record.discussion.filter { $0 != summary }.prefix(3)
            if !summary.isEmpty {
                text += summary
            } else if let first = points.first {
                text += first
            } else {
                var facts: [String] = []
                if !record.decisions.isEmpty { facts.append(VidurQuickContext.plural(record.decisions.count, "decision")) }
                if !record.tasks.isEmpty { facts.append(VidurQuickContext.plural(record.tasks.count, "task")) }
                if facts.isEmpty { return empty("No summary is saved for \(context.label(record)) yet.", .summary) }
                text += "No written summary is saved. It has \(facts.joined(separator: " and "))."
            }
            if !summary.isEmpty, !points.isEmpty { text += "\n" + points.map { "\u{2022} \($0)" }.joined(separator: "\n") }
            let quote = summary.isEmpty ? (points.first ?? "") : summary
            let sources = quote.isEmpty ? [] : [context.source(record, label: "Summary", timestamp: nil, quote: quote, speaker: nil)]
            return VidurSection(text: text, sources: sources, isComplete: true, intent: .summary)
        }
        var lines: [String] = []
        var sources: [VidurQuickSource] = []
        for record in recent {
            let body = record.summary.isEmpty ? (record.discussion.first ?? "") : record.summary
            guard !body.isEmpty else { continue }
            let short = VidurQuickContext.excerpt(body, keys: [], limit: 160)
            lines.append("\u{2022} \(context.label(record)): \(short)")
            sources.append(context.source(record, label: "Summary", timestamp: nil, quote: body, speaker: nil))
        }
        guard !lines.isEmpty else { return empty("No summaries are saved for \(context.scopeText).", .summary) }
        let head = "\(VidurQuickContext.plural(recent.count, "meeting"))" + (context.parsed.rangeLabel.map { " \($0)" } ?? "")
        return VidurSection(text: head + ":\n" + lines.joined(separator: "\n"), sources: Array(sources.prefix(4)),
                            isComplete: true, intent: .summary)
    }

    private static func duration(_ context: VidurQuickContext) -> VidurSection {
        let withLength = context.records.filter { $0.duration > 0 }.suffix(3)
        guard !withLength.isEmpty else { return empty("No recording length is saved for \(context.scopeText).", .duration) }
        let lines = withLength.map { "\(context.label($0)) ran \(durationText($0.duration))." }
        return VidurSection(text: lines.joined(separator: "\n"), isComplete: true, intent: .duration)
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0))
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        if hours > 0 { return "\(hours) h \(minutes) min" }
        if minutes > 0 { return secs > 0 ? "\(minutes) min \(secs) s" : "\(minutes) min" }
        return "\(secs) s"
    }

    private static func date(_ context: VidurQuickContext) -> VidurSection {
        let chosen = Array(context.records.suffix(3))
        guard !chosen.isEmpty else { return empty("There is no meeting to date.", .date) }
        let lines = chosen.map { "\(VidurQuickContext.title($0)) was on \(context.longDate($0.date))." }
        return VidurSection(text: lines.joined(separator: "\n"), isComplete: true, intent: .date)
    }

    private static func meetingList(_ context: VidurQuickContext) -> VidurSection {
        guard !context.records.isEmpty else { return empty("I found no meetings \(context.parsed.rangeLabel ?? "saved").", .meetingList) }
        let shown = context.records.suffix(8)
        let head = "You had \(VidurQuickContext.plural(context.records.count, "meeting"))" + (context.parsed.rangeLabel.map { " \($0)" } ?? "")
        let lines = shown.map { "\u{2022} \(context.label($0))" }
        return VidurSection(text: head + ":\n" + lines.joined(separator: "\n"), isComplete: true, intent: .meetingList)
    }

    // MARK: Next meeting

    private static let nextMeetingCues = [
        "next meeting", "next call", "agli meeting", "agle meeting", "agla meeting", "meet again", "reconvene",
        "follow up meeting", "followup meeting", "next session", "फिर मिलेंगे", "अगली मीटिंग", "अगले हफ्ते मिलते"
    ]
    private static let dateCues: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "tomorrow", "kal", "next week",
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november",
        "december", "somvar", "mangalvar", "budhvar", "guruvar", "shukravar", "shanivar", "ravivar"
    ]

    private static func nextMeeting(_ context: VidurQuickContext, allRecords: [VidurMeetingRecord]) -> VidurSection {
        // 1. A next meeting written into the minutes.
        for record in allRecords.reversed() {
            if let text = record.nextMeetingText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return VidurSection(
                    text: "Next meeting: \(text). This is from the minutes of \(context.label(record)).",
                    sources: [context.source(record, label: "Next meeting", timestamp: nil, quote: text, speaker: nil)],
                    isComplete: true, intent: .nextMeeting)
            }
        }
        // 2. A turn where someone mentioned it, in the newest meeting that mentions it at all.
        for record in allRecords.reversed() {
            var mentions: [VidurMeetingTurn] = []
            for turn in record.turns.reversed() {
                let padded = " " + VidurScript.words(turn.text).joined(separator: " ") + " "
                if nextMeetingCues.contains(where: { padded.contains(" \($0) ") }) { mentions.append(turn) }
            }
            func hasDate(_ turn: VidurMeetingTurn) -> Bool {
                VidurScript.words(turn.text).contains { dateCues.contains($0) || $0.allSatisfy(\.isNumber) }
            }
            guard let turn = mentions.first(where: hasDate) ?? mentions.first else { continue }
            let quote = VidurQuickContext.excerpt(turn.text, keys: [], limit: 200)
            let speaker = context.displayName(turn.speaker)
            let who = speaker.map { "\($0) said" } ?? "It was mentioned"
            let dated = hasDate(turn)
            let text = dated
                ? "A next meeting was mentioned in \(context.label(record)). \(who): \u{201C}\(quote)\u{201D}"
                : "No date for the next meeting is recorded. In \(context.label(record)), \(who): \u{201C}\(quote)\u{201D}"
            return VidurSection(
                text: text,
                sources: [context.source(record, label: nil, timestamp: turn.start, quote: turn.text, speaker: turn.speaker)],
                people: speaker.map { [$0] } ?? [], isComplete: dated, intent: .nextMeeting)
        }
        return empty("No next meeting is recorded in your meetings.", .nextMeeting)
    }
}
