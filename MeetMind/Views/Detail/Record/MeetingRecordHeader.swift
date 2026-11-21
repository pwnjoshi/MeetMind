import SwiftUI

/// Title, date, series chip, People row and the Minutes / Actions / Decisions control of the meeting record.
struct MeetingRecordHeader: View {
    let viewModel: MeetingDetailViewModel
    @Binding var section: String
    let keptPrivate: Bool
    let reviewStatus: String
    let onRename: () -> Void
    let onOpenPeople: () -> Void
    let onError: (String) -> Void

    static let sections = ["Minutes", "Actions", "Decisions"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onRename) {
                Text(viewModel.headerTitle).font(.title.bold()).multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Rename this meeting")
            if let meeting = viewModel.meeting {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.dateLine(for: meeting))
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(reviewStatus)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reviewStatus == "Finalized" ? Theme.Colors.manentAccent : Color.orange)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background((reviewStatus == "Finalized" ? Theme.Colors.manentAccent : Color.orange).opacity(0.1), in: Capsule())
                    if keptPrivate {
                        Label("Kept private on this iPhone", systemImage: "lock")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                MeetingSeriesMenu(meeting: meeting, onError: onError)
                MeetingPeopleRow(meeting: meeting, openPeople: onOpenPeople)
            }
            Picker("Meeting section", selection: $section) {
                ForEach(Self.sections, id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: section) { _, value in
                if value == "Minutes" { viewModel.selectTab(.summary) }
                if value == "Actions" { viewModel.selectTab(.actionItems) }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    /// "14 October 2026 · 5:30 PM"
    static func dateLine(for meeting: Meeting) -> String {
        let date = meeting.scheduledStartTime ?? meeting.createdAt
        let day = date.formatted(.dateTime.day().month(.wide).year())
        let time = date.formatted(date: .omitted, time: .shortened)
        return "\(day) · \(time)"
    }
}

/// White "People" card with present and absent counts.
struct MeetingPeopleRow: View {
    let meeting: Meeting
    let openPeople: () -> Void

    var body: some View {
        let absentIDs = Set(meeting.absentParticipantIDs ?? [])
        let people = meeting.namedAttendees
        let present = people.filter { !absentIDs.contains($0.id) }
        Button(action: openPeople) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("People")
                    Text("\(present.count) present · \(people.count - present.count) absent")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: -6) {
                    ForEach(present.prefix(4), id: \.id) { person in
                        Text(person.initials)
                            .font(.caption2.bold()).foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color(hex: person.colorHex), in: Circle())
                            .overlay(Circle().strokeBorder(.background, lineWidth: 1))
                    }
                }
                .accessibilityHidden(true)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }
}
