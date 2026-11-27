import SwiftUI

/// Where the minutes stand: draft, finalized, kept private, or handed to Mail or the share sheet.
enum MeetingRecordStatus: Equatable {
    case draft
    case finalized
    case keptPrivate
    /// `people` is the number of distinct recipients the user addressed; 0 when only the share sheet was used.
    case shared(people: Int)

    var title: String {
        switch self {
        case .draft: return "Draft \u{00B7} Review before sharing"
        case .finalized: return "Finalized"
        case .keptPrivate: return "Kept private on this iPhone"
        case .shared(let people):
            if people == 0 { return "Shared" }
            return people == 1 ? "Shared with 1 person" : "Shared with \(people) people"
        }
    }

    var tint: Color {
        switch self {
        case .draft: return Color.orange
        case .finalized: return Theme.Colors.manentAccent
        case .keptPrivate: return Color.secondary
        case .shared: return Color(red: 0.13, green: 0.55, blue: 0.24)
        }
    }
}

/// Title, date line, status and series pills, People card, review banner and the Minutes / Actions / Decisions control.
struct MeetingRecordHeader: View {
    let viewModel: MeetingDetailViewModel
    @Binding var section: String
    let status: MeetingRecordStatus
    let pendingReviewCount: Int
    let actionCount: Int
    let decisionCount: Int
    let unnamedVoiceCount: Int
    let onRename: () -> Void
    let onOpenPeople: () -> Void
    let onNameVoices: () -> Void
    let onReview: () -> Void
    let onError: (String) -> Void

    static let sections = ["Minutes", "Actions", "Decisions"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onRename) {
                Text(viewModel.headerTitle)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint("Rename this meeting")
            if let meeting = viewModel.meeting {
                Text(Self.metaLine(for: meeting))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        statusPill
                        MeetingSeriesMenu(meeting: meeting, onError: onError)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        statusPill
                        MeetingSeriesMenu(meeting: meeting, onError: onError)
                    }
                }
                MeetingPeopleRow(meeting: meeting, openPeople: onOpenPeople)
                if unnamedVoiceCount > 0 { nameVoicesCard }
                if pendingReviewCount > 0 { reviewBanner }
            }
            segmentedControl
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var statusPill: some View {
        Text(status.title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(status.tint.opacity(0.14), in: Capsule())
            .accessibilityLabel("Status: \(status.title)")
    }

    private var reviewBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(Theme.Colors.manentAccent)
                .accessibilityHidden(true)
            Text(pendingReviewCount == 1 ? "1 action needs your review" : "\(pendingReviewCount) actions need your review")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onReview) {
                Text("Review")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Theme.Colors.manentAccent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Review suggested actions")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.Colors.manentAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var nameVoicesCard: some View {
        Button(action: onNameVoices) {
            HStack(spacing: 14) {
                Image(systemName: "person.2.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.manentAccent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(unnamedVoiceCount == 1 ? "Name the voice" : "Name the \(unnamedVoiceCount) voices")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.manentAccent)
                    Text("So minutes show who decided what")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .recordCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(Self.sections, id: \.self) { name in
                let selected = section == name
                Button {
                    section = name
                } label: {
                    Text(label(for: name))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.8))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if selected {
                                Capsule().fill(Color(uiColor: .systemBackground))
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(for: name))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        .onChange(of: section) { _, value in
            if value == "Minutes" { viewModel.selectTab(.summary) }
            if value == "Actions" { viewModel.selectTab(.actionItems) }
        }
    }

    private func label(for name: String) -> String {
        switch name {
        case "Actions": return actionCount > 0 ? "Actions \(actionCount)" : "Actions"
        case "Decisions": return decisionCount > 0 ? "Decisions \(decisionCount)" : "Decisions"
        default: return name
        }
    }

    /// "Thu, 12 Nov 2026 \u{00B7} 9:00 \u{2013} 9:45 AM \u{00B7} 45 min"
    static func metaLine(for meeting: Meeting) -> String {
        let start = meeting.scheduledStartTime ?? meeting.createdAt
        let day = start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        var parts = [day]
        let startText = start.formatted(date: .omitted, time: .shortened)
        if meeting.duration >= 60 {
            let end = start.addingTimeInterval(meeting.duration)
            parts.append("\(startText) \u{2013} \(end.formatted(date: .omitted, time: .shortened))")
            parts.append("\(Int((meeting.duration / 60).rounded())) min")
        } else {
            parts.append(startText)
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// White "People" card with present and absent counts and an avatar stack.
struct MeetingPeopleRow: View {
    let meeting: Meeting
    let openPeople: () -> Void

    private var summary: String {
        let absentIDs = Set(meeting.absentParticipantIDs ?? [])
        let people = meeting.namedAttendees
        let absent = people.filter { absentIDs.contains($0.id) }.count
        let present = people.count - absent
        if people.isEmpty { return "Add the people who were there" }
        if absent == 0 { return "\(present) present" }
        return "\(present) present \u{00B7} \(absent) absent"
    }

    var body: some View {
        let absentIDs = Set(meeting.absentParticipantIDs ?? [])
        let present = meeting.namedAttendees.filter { !absentIDs.contains($0.id) }
        Button(action: openPeople) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("People").font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(summary).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                HStack(spacing: -8) {
                    ForEach(Array(present.prefix(4)), id: \.id) { person in
                        RecordAvatar(initials: person.initials, colorHex: person.avatarColorHex, size: 30)
                            .overlay(Circle().strokeBorder(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 2))
                    }
                }
                .accessibilityHidden(true)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .recordCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("People, \(summary)")
        .accessibilityHint("Open people")
    }
}
