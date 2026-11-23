import SwiftUI

@MainActor
struct HomeSectionHeader: View {
    let title: String
    let showsSeeAll: Bool
    let seeAll: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
            Spacer()
            if showsSeeAll {
                Button("See All", action: seeAll)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.manentAccent)
            }
        }
        .padding(.horizontal, 2)
    }
}

@MainActor
struct UpNextMeetingCard: View {
    let meeting: Meeting
    let recurrenceText: String?
    let referenceDate: Date
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text(eyebrow)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.84))
                        .textCase(.uppercase)
                    Spacer(minLength: 4)
                    if meeting.isFavorite { ImportantBadge(style: .onDark) }
                }
                Text(meeting.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text(timeLine)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
                HStack(spacing: 10) {
                    HomeAvatarStack(people: meeting.namedAttendees, lightBorder: true)
                    Text(attendeeSummary)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .accessibilityHidden(true)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background { UpNextBackground() }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Color(hex: 0x4F46E5).opacity(0.18), radius: 20, y: 10)
            .importantGlowBorder(meeting.isFavorite, cornerRadius: 26, lineWidth: 3, glowRadius: 14, glowOpacity: 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Up next, \(meeting.title), \(timeLine)")
        .accessibilityHint("Opens meeting details")
    }

    private var eyebrow: String {
        guard let start = meeting.scheduledStartTime else { return "Up next" }
        let seconds = start.timeIntervalSince(referenceDate)
        if seconds <= 60 { return "Up next · Now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "Up next · In \(minutes) min" }
        if minutes < 24 * 60 {
            let hours = max(1, Int(round(Double(minutes) / 60)))
            return "Up next · In \(hours) \(hours == 1 ? "hr" : "hrs")"
        }
        return "Up next · \(start.formatted(.dateTime.weekday(.abbreviated).day()))"
    }

    private var timeLine: String {
        guard let start = meeting.scheduledStartTime else { return meeting.formattedDate }
        var value = start.formatted(date: .omitted, time: .shortened)
        if meeting.duration > 60 {
            value += " – \(start.addingTimeInterval(meeting.duration).formatted(date: .omitted, time: .shortened))"
        }
        if let recurrenceText { value += " · \(recurrenceText)" }
        return value
    }

    private var attendeeSummary: String {
        let people = meeting.namedAttendees
        guard !people.isEmpty else { return "No people added" }
        let visible = people.prefix(2).map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
        let remaining = people.count - visible.count
        if remaining > 0 { return "\(visible.joined(separator: ", ")) and \(remaining) other\(remaining == 1 ? "" : "s")" }
        return visible.joined(separator: " and ")
    }
}

@MainActor
struct WeekMeetingCard: View {
    let meeting: Meeting
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Text(dateLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                    Spacer(minLength: 0)
                    if meeting.isFavorite { ImportantBadge(iconOnly: true) }
                }
                Text(meeting.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                Spacer(minLength: 2)
                HStack {
                    Text((meeting.scheduledStartTime ?? meeting.createdAt)
                        .formatted(date: .omitted, time: .shortened))
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Circle()
                        .fill(accentColor)
                        .frame(width: 11, height: 11)
                }
            }
            .padding(16)
            .frame(width: 154, height: 138, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .importantGlowBorder(meeting.isFavorite, cornerRadius: 22, lineWidth: 2.5, glowRadius: 10)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens meeting details")
    }

    private var dateLabel: String {
        (meeting.scheduledStartTime ?? meeting.createdAt)
            .formatted(.dateTime.weekday(.abbreviated).day())
            .uppercased()
    }

    private var accentColor: Color {
        let palette = [Theme.Colors.warmAmber, Theme.Colors.mintGreen, Theme.Colors.aiPurple]
        let index = meeting.title.unicodeScalars.reduce(0) { $0 + Int($1.value) } % palette.count
        return palette[index]
    }
}

@MainActor
struct RecentMeetingsCard: View {
    let meetings: [Meeting]
    let subtitle: (Meeting) -> String?
    let statusColor: (Meeting) -> Color
    let open: (Meeting) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                Button { open(meeting) } label: {
                    HStack(spacing: 14) {
                        HomeDateTile(date: HomeViewModel.recencyDate(for: meeting))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(RecentMeetingPresenter.title(for: meeting))
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if let subtitle = subtitle(meeting) {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(statusColor(meeting))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        if meeting.isFavorite { ImportantBadge(iconOnly: true) }
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 64)
                    .contentShape(Rectangle())
                    .importantGlowBorder(meeting.isFavorite, cornerRadius: 16, lineWidth: 1.5, glowRadius: 0, inset: 4)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens meeting")
                if index < meetings.count - 1 {
                    Divider().padding(.leading, 72).padding(.trailing, 16)
                }
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct HomeDateTile: View {
    let date: Date

    var body: some View {
        VStack(spacing: -1) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.red)
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 19, weight: .medium, design: .rounded))
        }
        .frame(width: 44, height: 44)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }
}

struct HomeAvatarStack: View {
    let people: [Speaker]
    let lightBorder: Bool

    var body: some View {
        HStack(spacing: -7) {
            ForEach(Array(people.prefix(3)), id: \.id) { person in
                Text(person.initials)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color(hex: person.avatarColorHex), in: Circle())
                    .overlay(Circle().stroke(borderColor, lineWidth: 2))
            }
            if people.count > 3 {
                Text("+\(people.count - 3)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color(uiColor: .systemGray), in: Circle())
                    .overlay(Circle().stroke(borderColor, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(people.isEmpty ? "No attendees" : "\(people.count) attendees")
    }

    private var borderColor: Color {
        lightBorder ? Color.white.opacity(0.65) : Color(uiColor: .systemBackground)
    }
}

@MainActor
struct HomeMeetingCollectionView: View {
    let title: String
    let meetings: [Meeting]
    let recentSubtitle: (Meeting) -> String?

    var body: some View {
        List(meetings) { meeting in
            NavigationLink {
                MeetingDetailContainerView(meetingId: meeting.id)
            } label: {
                HStack(spacing: 12) {
                    HomeDateTile(date: HomeViewModel.recencyDate(for: meeting))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(RecentMeetingPresenter.title(for: meeting))
                        if let detail = detailText(for: meeting) {
                            Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if meeting.isFavorite { ImportantBadge(iconOnly: true) }
                }
                .frame(minHeight: 52)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }

    private func detailText(for meeting: Meeting) -> String? {
        if meeting.status == .scheduled {
            let planned = meeting.scheduledStartTime ?? meeting.createdAt
            if planned > Date() { return planned.formatted(date: .omitted, time: .shortened) }
        }
        return recentSubtitle(meeting)
    }
}

/// v5 Up Next surface: MeshGradient on iOS 18+, LinearGradient before that.
struct UpNextBackground: View {
    var body: some View {
        if #available(iOS 18.0, *) {
            MeshGradient(
                width: 3,
                height: 3,
                points: Self.points,
                colors: Self.meshColors
            )
        } else {
            LinearGradient(
                colors: [Color(hex: 0x4338FF), Color(hex: 0x7545ED), Color(hex: 0xC05EC5)],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        }
    }

    private static let points: [SIMD2<Float>] = [
        SIMD2<Float>(0.0, 0.0), SIMD2<Float>(0.5, 0.0), SIMD2<Float>(1.0, 0.0),
        SIMD2<Float>(0.0, 0.5), SIMD2<Float>(0.55, 0.45), SIMD2<Float>(1.0, 0.5),
        SIMD2<Float>(0.0, 1.0), SIMD2<Float>(0.5, 1.0), SIMD2<Float>(1.0, 1.0)
    ]

    private static let meshColors: [Color] = [
        Color(hex: 0x3B2FE0), Color(hex: 0x5B3FF0), Color(hex: 0x8A4DE8),
        Color(hex: 0x4338FF), Color(hex: 0x7545ED), Color(hex: 0xB654D0),
        Color(hex: 0x4F46E5), Color(hex: 0x7A4BEA), Color(hex: 0xC05EC5)
    ]
}
/// Label of the floating create (+) menu. Pre-iOS 26 it draws its own accent circle;
/// on iOS 26 the system glass prominent style (see `GlassCircleButtonStyle`) draws it.
struct CreateMenuLabel: View {
    var body: some View {
        if usesSystemGlass {
            Image(systemName: "plus")
                .font(.title2.weight(.medium))
                .frame(width: 30, height: 30)
        } else {
            Image(systemName: "plus")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Theme.Colors.manentAccent, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                .shadow(color: Theme.Colors.manentAccent.opacity(0.28), radius: 12, y: 6)
        }
    }

    private var usesSystemGlass: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }
}

struct GlassCircleButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Theme.Colors.manentAccent)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// A4 All meetings: an Upcoming / Earlier switch over one list, pushed full screen
/// without the tab bar, with search.
@MainActor
struct AllMeetingsView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case upcoming = "Upcoming"
        case earlier = "Earlier"
        var id: String { rawValue }
    }

    let upcoming: [Meeting]
    let earlier: [Meeting]
    let subtitle: (Meeting) -> String?
    let statusColor: (Meeting) -> Color
    @State private var scope: Scope
    @State private var query = ""
    @State private var searchPresented = false

    init(upcoming: [Meeting], earlier: [Meeting], subtitle: @escaping (Meeting) -> String?,
         statusColor: @escaping (Meeting) -> Color, initialScope: Scope = .upcoming) {
        self.upcoming = upcoming
        self.earlier = earlier
        self.subtitle = subtitle
        self.statusColor = statusColor
        _scope = State(initialValue: initialScope)
    }

    var body: some View {
        List {
            Section {
                Picker("Meetings", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
            }
            let meetings = scope == .upcoming ? filteredUpcoming : filteredEarlier
            if meetings.isEmpty {
                Section {
                    Text(emptyText).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(meetings) { meeting in
                        row(meeting, isUpcoming: scope == .upcoming)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle("All Meetings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .searchable(text: $query, isPresented: $searchPresented, prompt: "Search meetings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { searchPresented = true } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search meetings")
            }
        }
        .animation(.default, value: scope)
    }

    private var emptyText: String {
        if !query.isEmpty { return "No meetings match \"\(query)\"" }
        return scope == .upcoming ? "No upcoming meetings" : "No earlier meetings yet"
    }

    private var filteredUpcoming: [Meeting] { filtered(upcoming) }

    /// Earlier meetings, most recent first, without any meeting that is also upcoming.
    private var filteredEarlier: [Meeting] {
        let upcomingIDs = Set(upcoming.map { $0.id })
        return filtered(earlier)
            .filter { !upcomingIDs.contains($0.id) }
            .sorted { HomeViewModel.recencyDate(for: $0) > HomeViewModel.recencyDate(for: $1) }
    }

    private func filtered(_ meetings: [Meeting]) -> [Meeting] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return meetings }
        return meetings.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    private func row(_ meeting: Meeting, isUpcoming: Bool) -> some View {
        let date = isUpcoming ? (meeting.scheduledStartTime ?? meeting.createdAt) : HomeViewModel.recencyDate(for: meeting)
        return NavigationLink {
            MeetingDetailContainerView(meetingId: meeting.id)
        } label: {
            HStack(spacing: 12) {
                HomeDateTile(date: date)
                VStack(alignment: .leading, spacing: 3) {
                    Text(RecentMeetingPresenter.title(for: meeting))
                        .lineLimit(1)
                    if let line = detail(meeting, date: date, isUpcoming: isUpcoming) {
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(isUpcoming ? Color.secondary : statusColor(meeting))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if meeting.isFavorite { ImportantBadge(iconOnly: true) }
                if isUpcoming {
                    Text(date.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 52)
        }
    }

    private func detail(_ meeting: Meeting, date: Date, isUpcoming: Bool) -> String? {
        guard isUpcoming else { return subtitle(meeting) }
        let day = date.formatted(.dateTime.weekday(.abbreviated))
        let count = meeting.namedAttendees.count
        if count > 0 { return "\(day) \u{00B7} \(count) \(count == 1 ? "person" : "people")" }
        return day
    }
}
