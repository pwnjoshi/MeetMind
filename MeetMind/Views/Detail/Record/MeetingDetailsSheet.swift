import SwiftUI

/// "Meeting Details" from the More menu: when it happened, how long, where it is filed and who was there.
struct MeetingDetailsSheet: View {
    let meeting: Meeting
    @Environment(\.dismiss) private var dismiss

    private var start: Date { meeting.scheduledStartTime ?? meeting.createdAt }

    private var timeText: String {
        let first = start.formatted(date: .omitted, time: .shortened)
        guard meeting.duration >= 60 else { return first }
        let end = start.addingTimeInterval(meeting.duration).formatted(date: .omitted, time: .shortened)
        return "\(first) \u{2013} \(end)"
    }

    private var durationText: String {
        guard meeting.duration >= 60 else { return "Under a minute" }
        let minutes = Int((meeting.duration / 60).rounded())
        if minutes >= 60 {
            let remainder = minutes % 60
            return remainder == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(remainder) min"
        }
        return "\(minutes) min"
    }

    private var peopleText: String {
        let absentIDs = Set(meeting.absentParticipantIDs ?? [])
        let people = meeting.namedAttendees
        let absent = people.filter { absentIDs.contains($0.id) }.count
        if people.isEmpty { return "None added" }
        return "\(people.count - absent) present \u{00B7} \(absent) absent"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Date", value: start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                    LabeledContent("Time", value: timeText)
                    LabeledContent("Duration", value: durationText)
                }
                Section {
                    LabeledContent("People", value: peopleText)
                    LabeledContent("Series", value: meeting.seriesName ?? "None")
                    if let folder = meeting.folder?.name, !folder.isEmpty {
                        LabeledContent("Folder", value: folder)
                    }
                    if let template = meeting.templateName, !template.isEmpty {
                        LabeledContent("Template", value: template)
                    }
                    LabeledContent("Recording", value: meeting.resolvedAudioFileURL != nil ? "Saved on this iPhone" : "Not on this iPhone")
                }
            }
            .navigationTitle("Meeting Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
