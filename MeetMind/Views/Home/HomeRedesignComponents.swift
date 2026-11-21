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
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
                    .textCase(.uppercase)
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
            .background {
                LinearGradient(
                    colors: [Color(hex: 0x4338FF), Color(hex: 0x7545ED), Color(hex: 0xC05EC5)],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Color(hex: 0x4F46E5).opacity(0.18), radius: 20, y: 10)
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
                Text(dateLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
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
                        HomeDateTile(date: meeting.scheduledStartTime ?? meeting.createdAt)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(meeting.title)
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
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 64)
                    .contentShape(Rectangle())
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
                    HomeDateTile(date: meeting.scheduledStartTime ?? meeting.createdAt)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(meeting.title)
                        if let detail = meeting.status == .scheduled
                            ? (meeting.scheduledStartTime ?? meeting.createdAt).formatted(date: .omitted, time: .shortened)
                            : recentSubtitle(meeting) {
                            Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minHeight: 52)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
}
