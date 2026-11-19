import SwiftUI

/// The saved minutes use one reading surface from agenda through action items.
public struct MeetingSummaryTabView: View {
    public let summary: Summary?
    public let actionItems: [ActionItem]
    public let onDocumentFormat: () -> Void

    public var body: some View {
        ScrollView {
            if let summary {
                VStack(alignment: .leading, spacing: 16) {
                    if let meeting = summary.meeting {
                        meetingContext(meeting)
                    }
                    let discussion = summary.keyPoints.isEmpty ? [summary.executiveSummary] : summary.keyPoints
                    documentSection("Discussion", lines: discussion.filter { !$0.isEmpty })
                    documentSection("Decision", lines: summary.keyDecisions)
                    if !actionItems.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Action items").font(.headline)
                            ForEach(actionItems) { action in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(action.title)
                                    Text(actionDetails(action)).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Button(action: onDocumentFormat) {
                        Text("Document format").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(.background, in: RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private func meetingContext(_ meeting: Meeting) -> some View {
        let absentIDs = Set(meeting.absentParticipantIDs ?? [])
        if let agenda = meeting.agendaText, !agenda.isEmpty {
            documentSection("Agenda", lines: [agenda])
        }
        attendance("Present", people: meeting.participants.filter { !absentIDs.contains($0.id) })
        attendance("Absent", people: meeting.participants.filter { absentIDs.contains($0.id) })
    }

    @ViewBuilder
    private func documentSection(_ title: String, lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                ForEach(Array(lines.enumerated()), id: \.offset) { line in
                    Text(line.element).textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func attendance(_ title: String, people: [Speaker]) -> some View {
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                ForEach(people, id: \.id) { person in
                    Label {
                        Text(person.name)
                    } icon: {
                        Circle().fill(Color(hex: person.avatarColorHex)).frame(width: 10, height: 10)
                    }
                }
            }
        }
    }

    private func actionDetails(_ action: ActionItem) -> String {
        guard let date = action.dueDate else { return action.assigneeName }
        return "\(action.assigneeName) · Due \(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))"
    }
}
