import SwiftUI

/// Text formatting for the "Prepare meeting" page (Figma D1).
enum PrepareMeetingFormat {
    /// "In 25 min \u{00B7} 9:00 \u{2013} 9:45 AM", "Tomorrow \u{00B7} 9:00 \u{2013} 9:45 AM" or "Mon, 12 Nov \u{00B7} 9:00 AM".
    static func subtitle(start: Date, end: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let safeEnd = max(end, start)
        let range = (start..<safeEnd).formatted(.interval.hour().minute())
        let separator = " \u{00B7} "

        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes > 0 && minutes < 60 {
            return "In \(minutes) min" + separator + range
        }
        if now >= start && now < safeEnd {
            return "Happening now" + separator + range
        }
        if calendar.isDateInToday(start) { return "Today" + separator + range }
        if calendar.isDateInTomorrow(start) { return "Tomorrow" + separator + range }
        if calendar.isDateInYesterday(start) { return "Yesterday" + separator + range }
        let day = start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return day + separator + start.formatted(date: .omitted, time: .shortened)
    }

    /// "Thu, 12 Nov".
    static func dayText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "9:00 \u{2013} 9:45 AM". Shows only the start when the end is not after it.
    static func timeRange(start: Date, end: Date) -> String {
        guard end > start else { return start.formatted(date: .omitted, time: .shortened) }
        return (start..<end).formatted(.interval.hour().minute())
    }

    /// Agenda lines without list markers ("- ", "\u{2022} ", "1. ").
    static func agendaItems(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            var item = line.trimmingCharacters(in: .whitespaces)
            item = String(item.drop(while: { $0 == "-" || $0 == "*" || $0 == "\u{2022}" || $0 == " " }))
            item = item.replacingOccurrences(of: #"^\d+[.)]\s+"#, with: "", options: .regularExpression)
            item = item.trimmingCharacters(in: .whitespaces)
            return item.isEmpty ? nil : item
        }
    }

    /// "due today", "overdue", "due Fri" or "due 12 Nov". `isUrgent` is true for today and overdue.
    static func due(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> (text: String, isUrgent: Bool)? {
        guard let date else { return nil }
        if calendar.isDate(date, inSameDayAs: now) { return ("due today", true) }
        if date < calendar.startOfDay(for: now) { return ("overdue", true) }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if days < 7 {
            return ("due " + date.formatted(.dateTime.weekday(.abbreviated)), false)
        }
        return ("due " + date.formatted(.dateTime.day().month(.abbreviated)), false)
    }

    /// "Maya, Arjun and 3 others".
    static func peopleSummary(_ names: [String]) -> String {
        let firstNames = names.map { $0.split(separator: " ").first.map(String.init) ?? $0 }
        switch firstNames.count {
        case 0: return "Add people"
        case 1: return firstNames[0]
        case 2: return "\(firstNames[0]) and \(firstNames[1])"
        default:
            let others = firstNames.count - 2
            return "\(firstNames[0]), \(firstNames[1]) and \(others) \(others == 1 ? "other" : "others")"
        }
    }
}

/// Round material button face used in the page header. Wrap in a Button or Menu.
struct PrepareGlassIcon: View {
    let systemName: String
    var tint: Color = .primary

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
            .contentShape(Circle())
    }
}

/// Section heading with an optional trailing control.
struct PrepareSectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
    }
}

extension PrepareSectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// Stacked, overlapping avatars for the People row.
struct PrepareAvatarStack: View {
    let people: [Speaker]
    var limit: Int = 5

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(people.prefix(limit)), id: \.id) { person in
                PrepAvatar(name: person.name, initials: person.initials, colorHex: person.avatarColorHex)
                    .overlay(Circle().strokeBorder(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}
