import Foundation

/// Resolves spoken deadlines ("Friday", "kal tak", "20 November") to an ISO date relative to the meeting date.
enum DueDateResolver {
    private static let monthNames: [String] = [
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
        "november", "december"
    ]
    private static let weekdayNumbers: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7
    ]

    /// Date and weekday phrases, used to quote the spoken date back verbatim.
    static let datePhrasePattern: String = {
        let months = "january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec"
        let days = "monday|tuesday|wednesday|thursday|friday|saturday|sunday"
        let dayMonth = #"\d{1,2}(?:st|nd|rd|th)?\s+(?:of\s+)?(?:"# + months + ")"
        let monthDay = "(?:" + months + #")\s+\d{1,2}(?:st|nd|rd|th)?"#
        return #"(?i)\b(?:"# + dayMonth + "|" + monthDay + "|(?:next\\s+)?(?:" + days + #"))\b"#
    }()

    static func resolve(_ deadline: String, meetingDate: Date?, timeZone: TimeZone) -> String? {
        guard let meetingDate = meetingDate else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: meetingDate)
        let keys = HindiText.tokenize(deadline).map { $0.key }
        guard !keys.isEmpty else { return nil }

        if let date = explicitDate(keys: keys, calendar: calendar, today: today) { return format(date, calendar) }
        for key in keys {
            guard let target = weekdayNumbers[key] else { continue }
            let current = calendar.component(.weekday, from: today)
            var delta = (target - current + 7) % 7
            if delta == 0 { delta = 7 }
            if let date = calendar.date(byAdding: .day, value: delta, to: today) { return format(date, calendar) }
        }
        let keySet = Set(keys)
        if keySet.contains("parso") || (keySet.contains("day") && keySet.contains("after") && keySet.contains("tomorrow")) {
            return shifted(today, days: 2, calendar: calendar)
        }
        if keySet.contains("kal") || keySet.contains("tomorrow") { return shifted(today, days: 1, calendar: calendar) }
        if keySet.contains("aaj") || keySet.contains("today") || keySet.contains("tonight") || keySet.contains("eod")
            || (keySet.contains("end") && keySet.contains("day")) {
            return shifted(today, days: 0, calendar: calendar)
        }
        if keySet.contains("eow") || (keySet.contains("end") && keySet.contains("week")) {
            let current = calendar.component(.weekday, from: today)
            var delta = (6 - current + 7) % 7
            if delta == 0 && current != 6 { delta = 7 }
            return shifted(today, days: delta, calendar: calendar)
        }
        if keySet.contains("hafte") || (keySet.contains("next") && keySet.contains("week")) {
            return shifted(today, days: 7, calendar: calendar)
        }
        if keySet.contains("mahine") || (keySet.contains("next") && keySet.contains("month")) {
            if let date = calendar.date(byAdding: .month, value: 1, to: today) { return format(date, calendar) }
        }
        return nil
    }

    private static func shifted(_ today: Date, days: Int, calendar: Calendar) -> String? {
        guard let date = calendar.date(byAdding: .day, value: days, to: today) else { return nil }
        return format(date, calendar)
    }

    private static func dayNumber(_ key: String) -> Int? {
        var digits = key
        var hadSuffix = false
        for suffix in ["st", "nd", "rd", "th"] where digits.hasSuffix(suffix) && digits.count > 2 {
            digits = String(digits.dropLast(2))
            hadSuffix = true
            break
        }
        _ = hadSuffix
        guard let value = Int(digits), value >= 1, value <= 31 else { return nil }
        return value
    }

    private static func monthNumber(_ key: String) -> Int? {
        guard key.count >= 3 else { return nil }
        for (index, name) in monthNames.enumerated() where name.hasPrefix(key) { return index + 1 }
        return nil
    }

    private static func explicitDate(keys: [String], calendar: Calendar, today: Date) -> Date? {
        var day: Int?
        var month: Int?
        for index in keys.indices {
            if let value = dayNumber(keys[index]), index + 1 < keys.count, let found = monthNumber(keys[index + 1]) {
                day = value
                month = found
                break
            }
            if let found = monthNumber(keys[index]), index + 1 < keys.count, let value = dayNumber(keys[index + 1]) {
                day = value
                month = found
                break
            }
        }
        if let day = day, let month = month {
            let year = calendar.component(.year, from: today)
            for candidate in [year, year + 1] {
                var parts = DateComponents()
                parts.year = candidate
                parts.month = month
                parts.day = day
                guard let date = calendar.date(from: parts), calendar.component(.day, from: date) == day else { continue }
                if date >= today { return date }
            }
            return nil
        }
        // "the 15th": the next 15th of a month.
        for key in keys where key.count > 2 {
            let hasSuffix = key.hasSuffix("st") || key.hasSuffix("nd") || key.hasSuffix("rd") || key.hasSuffix("th")
            guard hasSuffix, let value = dayNumber(key) else { continue }
            let year = calendar.component(.year, from: today)
            let currentMonth = calendar.component(.month, from: today)
            for offset in 0..<13 {
                var parts = DateComponents()
                parts.year = year
                parts.month = currentMonth + offset
                parts.day = value
                guard let date = calendar.date(from: parts), calendar.component(.day, from: date) == value else { continue }
                if date >= today { return date }
            }
        }
        return nil
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        var text = String(value)
        while text.count < width { text = "0" + text }
        return text
    }

    static func format(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return pad(parts.year ?? 0, 4) + "-" + pad(parts.month ?? 0, 2) + "-" + pad(parts.day ?? 0, 2)
    }
}

/// "Agli meeting ..." / "next meeting ..." with a date or time.
enum NextMeetingFinder {
    private static let timePattern = #"(?i)\b\d{1,2}(?::\d{2})?\s*(?:am|pm|a\.m\.|p\.m\.|baje)(?![A-Za-z])"#

    static func isNextMeetingReference(_ keys: [String]) -> Bool {
        guard keys.contains("meeting") else { return false }
        return keys.contains("agli") || keys.contains("agle") || keys.contains("next")
    }

    static func find(turns: [AnalysisTurn], meetingDate: Date?, timeZone: TimeZone) -> MinutesNextMeeting? {
        let pieces = ActionExtractor.sentencePieces(turns)
        for (turnIndex, turnPieces) in pieces.enumerated() {
            for piece in turnPieces {
                let keys = HindiText.tokenize(piece).map { $0.key }
                guard isNextMeetingReference(keys) else { continue }
                var dateText = MinutesRegex.firstMatch(DueDateResolver.datePhrasePattern, in: piece)
                if dateText == nil {
                    let lower = piece.lowercased()
                    if keys.contains("kal") || lower.contains("tomorrow") { dateText = keys.contains("kal") ? "kal" : "tomorrow" }
                }
                let timeText = MinutesRegex.firstMatch(timePattern, in: piece)
                guard dateText != nil || timeText != nil else { continue }
                let iso = dateText.flatMap { DueDateResolver.resolve($0, meetingDate: meetingDate, timeZone: timeZone) }
                var text = "Next meeting"
                if let dateText = dateText { text += " on " + dateText }
                if let timeText = timeText { text += " at " + timeText }
                return MinutesNextMeeting(text: text + ".", dateText: dateText, timeText: timeText, isoDate: iso,
                                          evidence: [SourceEvidence(turnID: turns[turnIndex].id, quote: piece)])
            }
        }
        return nil
    }
}
