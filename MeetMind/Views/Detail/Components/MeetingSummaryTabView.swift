import SwiftUI

/// Summary tab displaying executive overview, key decisions, and discussion topics
public struct MeetingSummaryTabView: View {
    public let summary: Summary?
    public let onCopy: () -> Void
    
    public init(summary: Summary?, onCopy: @escaping () -> Void) {
        self.summary = summary
        self.onCopy = onCopy
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let summary {
                    if let meeting = summary.meeting {
                        meetingContext(meeting)
                    }
                    executiveSection(summary.executiveSummary)
                    if !summary.keyDecisions.isEmpty {
                        MeetingSummaryPointsCard(
                            title: "Key Decisions",
                            icon: "checkmark.seal.fill",
                            tintColor: Theme.Colors.mintGreenDark,
                            backgroundColor: Theme.Colors.mintGreenLight.opacity(0.3),
                            items: summary.keyDecisions
                        )
                    }
                    if !summary.keyPoints.isEmpty {
                        MeetingSummaryPointsCard(
                            title: "Discussion Topics",
                            icon: "bubble.left.and.bubble.right.fill",
                            tintColor: Theme.Colors.liveBlue,
                            backgroundColor: Theme.Colors.cardBackground,
                            items: summary.keyPoints
                        )
                    }
                }
            }
            .padding(Spacing.lg)
        }
    }

    @ViewBuilder
    private func meetingContext(_ meeting: Meeting) -> some View {
        let absentIDs = Set(meeting.absentParticipantIDs ?? [])
        if meeting.agendaText?.isEmpty == false || !meeting.participants.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if let agenda = meeting.agendaText, !agenda.isEmpty {
                    Text("Agenda").font(.headline)
                    Text(agenda)
                }
                attendance("Present", people: meeting.participants.filter { !absentIDs.contains($0.id) })
                attendance("Absent", people: meeting.participants.filter { absentIDs.contains($0.id) })
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(.background, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    @ViewBuilder
    private func attendance(_ title: String, people: [Speaker]) -> some View {
        if !people.isEmpty {
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
    
    private func executiveSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Label("Executive Overview", systemImage: "sparkles")
                    .font(Typography.headline).foregroundStyle(Theme.Colors.aiPurple)
                Spacer()
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc").font(.system(size: 14)).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Text(text).font(Typography.body).foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(Spacing.md).background(Theme.Colors.cardBackground).clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.lg))
    }
}
