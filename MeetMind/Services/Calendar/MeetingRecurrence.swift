import Foundation

/// How often a prepared meeting repeats. `nil` anywhere in the app means "Never".
public struct MeetingRecurrence: Codable, Equatable, Hashable, Sendable {
    public enum Unit: String, Codable, CaseIterable, Sendable {
        case day
        case week
        case month

        var calendarComponent: Calendar.Component {
            switch self {
            case .day: return .day
            case .week: return .weekOfYear
            case .month: return .month
            }
        }

        var singular: String {
            switch self {
            case .day: return "Day"
            case .week: return "Week"
            case .month: return "Month"
            }
        }
    }

    public var unit: Unit
    /// Number of units between occurrences. Always at least 1.
    public var interval: Int

    public init(unit: Unit, interval: Int = 1) {
        self.unit = unit
        self.interval = max(1, min(interval, 99))
    }

    public static let daily = MeetingRecurrence(unit: .day)
    public static let weekly = MeetingRecurrence(unit: .week)
    public static let biweekly = MeetingRecurrence(unit: .week, interval: 2)
    public static let monthly = MeetingRecurrence(unit: .month)

    public static let presets: [MeetingRecurrence] = [.daily, .weekly, .biweekly, .monthly]

    public var isPreset: Bool { MeetingRecurrence.presets.contains(self) }

    /// Menu title such as "Every Week" or "Every 3 Days".
    public var title: String {
        interval == 1 ? "Every \(unit.singular)" : "Every \(interval) \(unit.singular)s"
    }

    /// Title for an optional recurrence ("Never" when nil).
    public static func title(for recurrence: MeetingRecurrence?) -> String {
        recurrence?.title ?? "Never"
    }

    /// Text shown on Home and the meeting detail, e.g. "Repeats weekly".
    public var summaryText: String {
        switch (unit, interval) {
        case (.day, 1): return "Repeats daily"
        case (.week, 1): return "Repeats weekly"
        case (.month, 1): return "Repeats monthly"
        case (.day, let n): return "Repeats every \(n) days"
        case (.week, let n): return "Repeats every \(n) weeks"
        case (.month, let n): return "Repeats every \(n) months"
        }
    }

    /// The first occurrence after `base` that is also later than `now`.
    public func nextOccurrence(after base: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        var next = step(base, calendar: calendar)
        var guardCount = 0
        while next <= now && guardCount < 5_000 {
            next = step(next, calendar: calendar)
            guardCount += 1
        }
        return next
    }

    private func step(_ date: Date, calendar: Calendar) -> Date {
        if let result = calendar.date(byAdding: unit.calendarComponent, value: interval, to: date), result > date {
            return result
        }
        return date.addingTimeInterval(86_400 * Double(interval))
    }
}
