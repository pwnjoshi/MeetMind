import Foundation

/// A rendered part of an answer.
struct VidurSection {
    var text: String
    var sources: [VidurQuickSource] = []
    var people: [String] = []
    var tasks: [VidurQuickTask] = []
    var isComplete: Bool
    /// True when the saved data had nothing to show. `text` then explains what was missing.
    var isEmpty = false
    var intent: VidurQuickIntent
}

/// Everything a renderer needs: the meetings in scope, the parsed question and date formatting.
struct VidurQuickContext {
    let records: [VidurMeetingRecord]
    let parsed: VidurParsedQuestion
    let index: VidurPersonIndex
    let selfPerson: VidurPerson?
    let now: Date
    let calendar: Calendar
    private let dayFormatter: DateFormatter
    private let longFormatter: DateFormatter
    private let dueFormatter: DateFormatter

    init(records: [VidurMeetingRecord], parsed: VidurParsedQuestion, index: VidurPersonIndex,
         selfPerson: VidurPerson?, now: Date, calendar: Calendar) {
        self.records = records
        self.parsed = parsed
        self.index = index
        self.selfPerson = selfPerson
        self.now = now
        self.calendar = calendar
        func make(_ format: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format
            return formatter
        }
        dayFormatter = make("d MMM")
        longFormatter = make("EEEE d MMMM yyyy")
        dueFormatter = make("EEE d MMM")
    }

    var isMultiple: Bool { records.count > 1 }

    func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    func longDate(_ date: Date) -> String { longFormatter.string(from: date) }
    func dueDay(_ date: Date) -> String { dueFormatter.string(from: date) }

    static func title(_ record: VidurMeetingRecord) -> String {
        let trimmed = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled meeting" : trimmed
    }

    /// "Launch sync (20 Nov)"
    func label(_ record: VidurMeetingRecord) -> String { "\(Self.title(record)) (\(day(record.date)))" }

    /// "the Launch sync meeting", "your meetings" or "the meetings from last week".
    var scopeText: String {
        if records.count == 1, let only = records.first { return Self.title(only) }
        if let label = parsed.rangeLabel, parsed.meetingRange != nil { return "your meetings \(label)" }
        return "your meetings"
    }

    func source(_ record: VidurMeetingRecord, label: String?, timestamp: TimeInterval?, quote: String,
                speaker: String?) -> VidurQuickSource {
        VidurQuickSource(meetingID: record.id, meetingTitle: Self.title(record), meetingDate: record.date,
                         label: label, timestamp: timestamp, quote: quote, speaker: speaker)
    }

    func displayName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if VidurPersonIndex.isGenericLabel(raw) {
            let lowered = raw.lowercased()
            if lowered == "note" || lowered == "notes" { return nil }
            let digits = lowered.filter(\.isNumber)
            return digits.isEmpty ? "Someone" : "Speaker \(digits)"
        }
        return index.person(forRaw: raw)?.canonical ?? raw
    }

    static func timecode(_ time: TimeInterval) -> String {
        let total = time.isFinite ? Int(max(0, time)) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    /// Search keys for each topic word, used to match minutes and transcript in any script.
    var topicTerms: [[String]] {
        parsed.residual.map { VidurScript.keys(forWord: $0) }.filter { !$0.isEmpty }
    }

    func matchesTopic(_ text: String) -> Bool {
        let terms = topicTerms
        guard !terms.isEmpty else { return true }
        let keys = Set(VidurScript.keys(text))
        let hit = terms.filter { !keys.isDisjoint(with: $0) }.count
        return hit >= max(1, Int((Double(terms.count) * 0.5).rounded(.up)))
    }

    /// The sentence of `text` that shares the most keys with the question, cut to `limit` characters.
    static func excerpt(_ text: String, keys: Set<String>, limit: Int = 200) -> String {
        let whole = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard whole.count > limit else { return whole }
        var sentences: [String] = []
        var current = ""
        for character in whole {
            current.append(character)
            if ".?!\u{0964}".contains(character) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        var best = sentences.first ?? whole
        var bestScore = -1
        for sentence in sentences {
            let score = Set(VidurScript.keys(sentence)).intersection(keys).count
            if score > bestScore { best = sentence; bestScore = score }
        }
        guard best.count > limit else { return best }
        var cut = String(best.prefix(limit))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2 {
            cut = String(cut[cut.startIndex..<space])
        }
        return cut + "\u{2026}"
    }
}
