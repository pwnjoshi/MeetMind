import Foundation

// Vidur's retrieval index. Every saved meeting becomes a set of small documents ("chunks"), each with
// the metadata a question can filter on: meeting title, series, date, speaker or owner, time in the
// recording, status. Hindi text is indexed twice, as written and in Roman letters with English loanwords
// (HindiRomanizer), so an English question finds Hindi speech. All of it is in memory.

/// What kind of saved text a chunk holds.
public enum VidurRagKind: String, Sendable, Equatable, CaseIterable {
    /// One block per meeting with the structured facts: when, how long, who, agenda, counts, summary.
    case facts
    case attendance, agenda, summary, decision, action, openIssue, discussion, nextMeeting
    /// A 60 to 90 second window of the transcript or typed notes.
    case transcript

    public var isMinutes: Bool { self != .transcript }

    /// Heading of a source row for minutes items. Nil for a transcript quote.
    public var sourceLabel: String? {
        switch self {
        case .facts: return "Meeting facts"
        case .attendance: return "Attendees"
        case .agenda: return "Agenda"
        case .summary: return "Summary"
        case .decision: return "Decision"
        case .action: return "Action"
        case .openIssue: return "Open issue"
        case .discussion: return "Discussion"
        case .nextMeeting: return "Next meeting"
        case .transcript: return nil
        }
    }

    /// The word used in a context block header.
    var headerWord: String {
        switch self {
        case .facts: return "meeting facts"
        case .attendance: return "attendees"
        case .agenda: return "agenda"
        case .summary: return "summary"
        case .decision: return "decision"
        case .action: return "action"
        case .openIssue: return "open issue"
        case .discussion: return "discussion"
        case .nextMeeting: return "next meeting"
        case .transcript: return "transcript"
        }
    }
}

/// One spoken turn or typed note inside a transcript chunk.
public struct VidurRagPassage: Sendable, Equatable {
    public let speaker: String?
    public let start: TimeInterval
    public let text: String

    public init(speaker: String?, start: TimeInterval, text: String) {
        self.speaker = speaker
        self.start = start
        self.text = text
    }
}

public struct VidurRagChunk: Sendable, Equatable, Identifiable {
    /// Position in `VidurRagIndex.chunks`.
    public let id: Int
    public let kind: VidurRagKind
    public let meetingID: UUID
    public let meetingTitle: String
    public let meetingDate: Date
    public let seriesTitle: String?
    /// Who said, decided or owns it. Nil when it is not about one person.
    public let speaker: String?
    /// Everyone this chunk is about, for person filters.
    public let people: [String]
    /// Moment in the recording. For a transcript chunk, the start of its window.
    public let timestamp: TimeInterval?
    /// End of a transcript window.
    public let endTimestamp: TimeInterval?
    /// What the model reads. For a transcript chunk, the lines "Name [mm:ss]: text".
    public let text: String
    public let passages: [VidurRagPassage]
    /// Words the retrieval ranks on: the text plus its Roman form for Hindi.
    public let keys: [String]
    /// Actions only.
    public let isCompleted: Bool?
    public let dueDate: Date?

    public init(id: Int, kind: VidurRagKind, meetingID: UUID, meetingTitle: String, meetingDate: Date,
                seriesTitle: String? = nil, speaker: String? = nil, people: [String] = [],
                timestamp: TimeInterval? = nil, endTimestamp: TimeInterval? = nil, text: String,
                passages: [VidurRagPassage] = [], keys: [String] = [], isCompleted: Bool? = nil,
                dueDate: Date? = nil) {
        self.id = id
        self.kind = kind
        self.meetingID = meetingID
        self.meetingTitle = meetingTitle
        self.meetingDate = meetingDate
        self.seriesTitle = seriesTitle
        self.speaker = speaker
        self.people = people
        self.timestamp = timestamp
        self.endTimestamp = endTimestamp
        self.text = text
        self.passages = passages
        self.keys = keys
        self.isCompleted = isCompleted
        self.dueDate = dueDate
    }
}

/// Meeting level metadata kept next to the chunks.
public struct VidurRagMeeting: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let date: Date
    public let duration: TimeInterval
    public let seriesTitle: String?
    public let attendees: [String]
    public let absent: [String]
    public let attendanceRecorded: Bool
    public let decisionCount: Int
    public let openActionCount: Int
    public let doneActionCount: Int
}

public struct VidurRagIndex: Sendable {
    /// Oldest first.
    public let meetings: [VidurRagMeeting]
    public let chunks: [VidurRagChunk]
    /// Changes whenever anything Vidur reads changes, so a cached index can be trusted.
    public let contentHash: String
    /// Every person named in the meetings (attendees, owners, speakers), used to resolve names in questions.
    public let names: [String]
    let factsIndexByMeeting: [UUID: Int]

    public var isEmpty: Bool { chunks.isEmpty }

    /// The structured facts block of a meeting.
    public func facts(for meetingID: UUID) -> VidurRagChunk? {
        guard let position = factsIndexByMeeting[meetingID], chunks.indices.contains(position) else { return nil }
        return chunks[position]
    }

    // MARK: Building

    /// Longest transcript window in seconds, and how far each next window moves on. The difference is the overlap.
    public static let windowSeconds: TimeInterval = 75
    public static let strideSeconds: TimeInterval = 60
    static let maximumWindowCharacters = 1_600

    public static func build(records: [VidurMeetingRecord], calendar: Calendar = .current) -> VidurRagIndex {
        let usable = records.filter(\.hasContent).sorted { $0.date < $1.date }
        let format = VidurRagFormat(calendar: calendar)
        var builder = Builder(format: format)
        for record in usable { builder.add(record) }
        return VidurRagIndex(meetings: builder.meetings, chunks: builder.chunks, contentHash: fingerprint(of: records, calendar: calendar),
                             names: builder.sortedNames, factsIndexByMeeting: builder.factsIndex)
    }

    /// A 64-bit FNV-1a hash of everything the index is built from.
    public static func fingerprint(of records: [VidurMeetingRecord], calendar: Calendar = .current) -> String {
        var hasher = VidurRagHasher()
        hasher.add(calendar.timeZone.identifier)
        for record in records.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.add(record.id.uuidString)
            hasher.add(record.title)
            hasher.add(number: record.date.timeIntervalSince1970)
            hasher.add(number: record.duration)
            hasher.add(record.seriesTitle ?? "")
            hasher.add(record.attendees.joined(separator: "|"))
            hasher.add(record.absent.joined(separator: "|"))
            hasher.add(record.attendanceRecorded ? "1" : "0")
            hasher.add(record.agenda.joined(separator: "|"))
            hasher.add(record.summary)
            hasher.add(record.discussion.joined(separator: "|"))
            hasher.add(record.nextMeetingText ?? "")
            for line in record.decisions + record.openIssues {
                hasher.add(line.text)
                hasher.add(line.speaker ?? "")
                hasher.add(line.quote ?? "")
                hasher.add(number: line.timestamp ?? -1)
            }
            for task in record.tasks {
                hasher.add(task.title)
                hasher.add(task.owner ?? "")
                hasher.add(number: task.dueDate?.timeIntervalSince1970 ?? -1)
                hasher.add(task.dueText ?? "")
                hasher.add((task.isCompleted ? "1" : "0") + (task.isSuggestion ? "1" : "0"))
                hasher.add(task.quote ?? "")
            }
            hasher.add(number: Double(record.turns.count))
            for turn in record.turns {
                hasher.add(turn.text)
                hasher.add(turn.speaker ?? "")
                hasher.add(number: turn.start)
            }
        }
        return hasher.hex
    }

    // MARK: Builder

    private struct Builder {
        let format: VidurRagFormat
        var meetings: [VidurRagMeeting] = []
        var chunks: [VidurRagChunk] = []
        var factsIndex: [UUID: Int] = [:]
        private var names: [String] = []
        private var seenNames = Set<String>()

        init(format: VidurRagFormat) { self.format = format }

        var sortedNames: [String] { names }

        private mutating func remember(_ raw: String?) {
            guard let raw, !raw.isEmpty, !VidurPersonIndex.isGenericLabel(raw) else { return }
            if seenNames.insert(raw.lowercased()).inserted { names.append(raw) }
        }

        private mutating func append(_ record: VidurMeetingRecord, kind: VidurRagKind, speaker: String? = nil,
                                     people: [String] = [], timestamp: TimeInterval? = nil,
                                     endTimestamp: TimeInterval? = nil, text: String,
                                     passages: [VidurRagPassage] = [], isCompleted: Bool? = nil, dueDate: Date? = nil) {
            let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return }
            var searchable = body + " " + record.title
            if let series = record.seriesTitle { searchable += " " + series }
            for person in people { searchable += " " + person }
            let keys = VidurScript.keys(VidurRagFormat.withRoman(searchable))
            chunks.append(VidurRagChunk(
                id: chunks.count, kind: kind, meetingID: record.id, meetingTitle: VidurRagFormat.title(record.title),
                meetingDate: record.date, seriesTitle: record.seriesTitle, speaker: speaker, people: people,
                timestamp: timestamp, endTimestamp: endTimestamp, text: body, passages: passages, keys: keys,
                isCompleted: isCompleted, dueDate: dueDate))
        }

        mutating func add(_ record: VidurMeetingRecord) {
            record.attendees.forEach { remember($0) }
            record.absent.forEach { remember($0) }
            record.tasks.forEach { remember($0.owner) }
            record.decisions.forEach { remember($0.speaker) }
            record.openIssues.forEach { remember($0.speaker) }
            record.turns.forEach { remember($0.speaker) }

            let openCount = record.tasks.filter { !$0.isCompleted }.count
            meetings.append(VidurRagMeeting(
                id: record.id, title: VidurRagFormat.title(record.title), date: record.date, duration: record.duration,
                seriesTitle: record.seriesTitle, attendees: record.attendees, absent: record.absent,
                attendanceRecorded: record.attendanceRecorded, decisionCount: record.decisions.count,
                openActionCount: openCount, doneActionCount: record.tasks.count - openCount))

            // 1. Facts: the always-included block.
            factsIndex[record.id] = chunks.count
            append(record, kind: .facts, people: record.attendees + record.absent, text: format.factsText(record))

            // 2. Minutes.
            if !record.attendees.isEmpty || !record.absent.isEmpty {
                var text = record.attendanceRecorded ? "Present: " : "Participants (attendance not confirmed): "
                text += record.attendees.isEmpty ? "none" : record.attendees.joined(separator: ", ")
                text += "."
                if !record.absent.isEmpty { text += " Absent: " + record.absent.joined(separator: ", ") + "." }
                append(record, kind: .attendance, people: record.attendees + record.absent, text: text)
            }
            if !record.agenda.isEmpty {
                append(record, kind: .agenda, text: "Agenda: " + record.agenda.joined(separator: "; ") + ".")
            }
            let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty { append(record, kind: .summary, text: "Summary: " + summary) }
            for line in record.discussion where line != summary {
                append(record, kind: .discussion, text: "Discussed: " + line)
            }
            for decision in record.decisions {
                var text = "Decision: " + decision.text
                if let speaker = decision.speaker, !speaker.isEmpty, !VidurPersonIndex.isGenericLabel(speaker) {
                    text += " (decided by \(VidurRagFormat.speakerName(speaker)))"
                }
                if let quote = decision.quote, !quote.isEmpty, quote != decision.text {
                    text += " Reason or words: \u{201C}\(VidurRagFormat.clip(quote, 160))\u{201D}"
                }
                append(record, kind: .decision, speaker: decision.speaker.map(VidurRagFormat.speakerName),
                       people: decision.speaker.map { [VidurRagFormat.speakerName($0)] } ?? [],
                       timestamp: decision.timestamp, text: text)
            }
            for task in record.tasks {
                var parts = ["Action: " + task.title]
                parts.append("owner: " + (VidurRagFormat.nonEmpty(task.owner) ?? "not set"))
                if let due = task.dueDate { parts.append("due: " + format.day(due)) }
                else if let text = task.dueText, !text.isEmpty { parts.append("due: " + text) }
                else { parts.append("due: not set") }
                parts.append(task.isCompleted ? "status: done" : (task.isSuggestion ? "status: suggested, not yet accepted" : "status: open"))
                var text = parts.joined(separator: " | ")
                if let quote = task.quote, !quote.isEmpty, quote != task.title {
                    text += " | said: \u{201C}\(VidurRagFormat.clip(quote, 140))\u{201D}"
                }
                let owner = VidurRagFormat.nonEmpty(task.owner)
                append(record, kind: .action, speaker: owner, people: owner.map { [$0] } ?? [],
                       timestamp: task.timestamp, text: text, isCompleted: task.isCompleted, dueDate: task.dueDate)
            }
            for issue in record.openIssues {
                var text = "Open issue: " + issue.text
                if let speaker = issue.speaker, !speaker.isEmpty, !VidurPersonIndex.isGenericLabel(speaker) {
                    text += " (raised by \(VidurRagFormat.speakerName(speaker)))"
                }
                append(record, kind: .openIssue, speaker: issue.speaker.map(VidurRagFormat.speakerName),
                       people: issue.speaker.map { [VidurRagFormat.speakerName($0)] } ?? [],
                       timestamp: issue.timestamp, text: text)
            }
            if let next = record.nextMeetingText?.trimmingCharacters(in: .whitespacesAndNewlines), !next.isEmpty {
                append(record, kind: .nextMeeting, text: "Next meeting: " + next)
            }

            // 3. Transcript windows.
            addTranscript(record)
        }

        private mutating func addTranscript(_ record: VidurMeetingRecord) {
            let turns = record.turns.enumerated().sorted {
                $0.element.start != $1.element.start ? $0.element.start < $1.element.start : $0.offset < $1.offset
            }.map(\.element).filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            var first = 0
            while first < turns.count {
                let windowStart = turns[first].start
                var end = first
                var characters = 0
                while end < turns.count {
                    let turn = turns[end]
                    if end > first,
                       turn.start - windowStart > VidurRagIndex.windowSeconds
                        || characters + turn.text.count > VidurRagIndex.maximumWindowCharacters { break }
                    characters += turn.text.count
                    end += 1
                }
                let slice = Array(turns[first..<end])
                let passages = slice.map { turn in
                    VidurRagPassage(speaker: VidurRagFormat.passageSpeaker(turn.speaker), start: turn.start,
                                    text: turn.text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                let lines = passages.map { VidurRagFormat.line($0) }.joined(separator: "\n")
                var speakers: [String] = []
                for passage in passages {
                    if let name = passage.speaker, name != "Note", !speakers.contains(name) { speakers.append(name) }
                }
                append(record, kind: .transcript, speaker: speakers.first, people: speakers,
                       timestamp: slice.first?.start, endTimestamp: slice.last?.start, text: lines, passages: passages)
                if end >= turns.count { break }
                var next = first + 1
                while next < end && turns[next].start - windowStart < VidurRagIndex.strideSeconds { next += 1 }
                first = next
            }
        }
    }
}

// MARK: - Formatting helpers

struct VidurRagFormat {
    private let dayFormatter: DateFormatter
    private let longFormatter: DateFormatter
    private let timeFormatter: DateFormatter

    init(calendar: Calendar) {
        func make(_ pattern: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = pattern
            return formatter
        }
        dayFormatter = make("EEE d MMM")
        longFormatter = make("EEE d MMM yyyy")
        timeFormatter = make("HH:mm")
    }

    func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    func longDate(_ date: Date) -> String { longFormatter.string(from: date) }
    func time(_ date: Date) -> String { timeFormatter.string(from: date) }

    static func nonEmpty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func title(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled meeting" : trimmed
    }

    /// "S1" and "speaker_3" become "Speaker 1". Real names pass through.
    static func speakerName(_ raw: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard VidurPersonIndex.isGenericLabel(name) else { return name }
        let lowered = name.lowercased()
        if lowered == "note" || lowered == "notes" { return "Note" }
        let digits = lowered.filter(\.isNumber)
        return digits.isEmpty ? "Someone" : "Speaker \(digits)"
    }

    static func passageSpeaker(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return speakerName(raw)
    }

    static func timecode(_ time: TimeInterval) -> String {
        let total = time.isFinite ? Int(max(0, time)) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// "Maya Rao [12:10]: text"
    static func line(_ passage: VidurRagPassage) -> String {
        let name = passage.speaker ?? "Someone"
        return "\(name) [\(timecode(passage.start))]: \(passage.text)"
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > limit, limit > 1 else { return flat }
        var cut = String(flat.prefix(limit - 1))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2 {
            cut = String(cut[cut.startIndex..<space])
        }
        return cut + "\u{2026}"
    }

    /// The text plus its Roman spelling when it contains Devanagari, so both scripts are searchable.
    static func withRoman(_ text: String) -> String {
        guard HindiText.containsDevanagari(text) else { return text }
        return text + " " + HindiRomanizer.romanize(text)
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours) h \(minutes) min" : "\(hours) h" }
        return minutes > 0 ? "\(minutes) min" : "\(total) s"
    }

    /// The structured facts of a meeting in a few lines. The summary comes last so a cut loses it first.
    func factsText(_ record: VidurMeetingRecord) -> String {
        var parts: [String] = []
        var when = "Held \(longDate(record.date)) at \(time(record.date))"
        if record.duration > 0 { when += ", \(VidurRagFormat.durationText(record.duration))" }
        parts.append(when + ".")
        if let series = record.seriesTitle, !series.isEmpty { parts.append("Series: \(series).") }
        if !record.attendees.isEmpty {
            parts.append((record.attendanceRecorded ? "Present: " : "Participants: ") + record.attendees.joined(separator: ", ") + ".")
        }
        if !record.absent.isEmpty { parts.append("Absent: " + record.absent.joined(separator: ", ") + ".") }
        if !record.agenda.isEmpty { parts.append("Agenda: " + record.agenda.joined(separator: "; ") + ".") }
        let open = record.tasks.filter { !$0.isCompleted }.count
        var counts: [String] = []
        if !record.decisions.isEmpty { counts.append("\(record.decisions.count) decision\(record.decisions.count == 1 ? "" : "s")") }
        if !record.tasks.isEmpty { counts.append("\(record.tasks.count) action\(record.tasks.count == 1 ? "" : "s") (\(open) open)") }
        if !record.openIssues.isEmpty { counts.append("\(record.openIssues.count) open issue\(record.openIssues.count == 1 ? "" : "s")") }
        if !counts.isEmpty { parts.append("Minutes: " + counts.joined(separator: ", ") + ".") }
        if let next = record.nextMeetingText, !next.isEmpty { parts.append("Next meeting: \(next).") }
        let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty { parts.append("Summary: " + summary) }
        return parts.joined(separator: " ")
    }
}

/// 64-bit FNV-1a. Each added value ends with a separator byte so "ab"+"c" differs from "a"+"bc".
struct VidurRagHasher {
    private var state: UInt64 = 0xcbf2_9ce4_8422_2325

    mutating func add(_ text: String) {
        for byte in text.utf8 {
            state ^= UInt64(byte)
            state = state &* 0x0000_0100_0000_01b3
        }
        state ^= 0xFF
        state = state &* 0x0000_0100_0000_01b3
    }

    mutating func add(number: Double) {
        add(String(number.bitPattern, radix: 16))
    }

    var hex: String { String(state, radix: 16) }
}

// MARK: - Cache

/// Keeps the last index in memory. It is rebuilt only when the content hash changes, which happens when a
/// meeting, its minutes, its tasks or its transcript change.
public enum VidurRagIndexCache {
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: VidurRagIndex?
        func get() -> VidurRagIndex? { lock.lock(); defer { lock.unlock() }; return stored }
        func set(_ value: VidurRagIndex?) { lock.lock(); stored = value; lock.unlock() }
    }

    private static let box = Box()

    public static func index(for records: [VidurMeetingRecord], calendar: Calendar = .current) -> VidurRagIndex {
        let hash = VidurRagIndex.fingerprint(of: records, calendar: calendar)
        if let cached = box.get(), cached.contentHash == hash { return cached }
        let built = VidurRagIndex.build(records: records, calendar: calendar)
        box.set(built)
        return built
    }

    public static func reset() { box.set(nil) }

    /// The hash of the cached index, for tests and diagnostics.
    public static var cachedHash: String? { box.get()?.contentHash }
}
