import SwiftUI
import SwiftData

// MARK: - Attendance (169:714)

@MainActor
struct MinutesAttendanceView: View {
    let model: MinutesStudioModel

    var body: some View {
        let participants = model.snapshot.participants
        Group {
            if participants.isEmpty {
                ContentUnavailableView(
                    "No Participants",
                    systemImage: "person.2",
                    description: Text("Add participants to this meeting to record attendance.")
                )
            } else {
                List {
                    Section {
                        ForEach(participants) { person in
                            NavigationLink(value: MinutesStudioRoute.attendanceStatus(person.id)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(person.name)
                                        if let role = person.role {
                                            Text(role)
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 12)
                                    Text(model.status(for: person.id).title)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Attendance")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Attendance status (169:732)

@MainActor
struct MinutesAttendanceStatusView: View {
    let model: MinutesStudioModel
    let participantID: UUID
    @Environment(\.modelContext) private var modelContext

    private var personName: String {
        model.snapshot.participants.first { $0.id == participantID }?.name ?? ""
    }

    var body: some View {
        List {
            Section {
                ForEach(MinutesAttendanceStatus.allCases) { status in
                    MinutesChoiceRow(
                        title: status.title,
                        subtitle: status.subtitle,
                        isSelected: model.status(for: participantID) == status
                    ) {
                        model.setAttendance(status, for: participantID, context: modelContext)
                    }
                }
            } header: {
                Text(personName)
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Attendance Status")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Contents (169:750)

@MainActor
struct MinutesContentsView: View {
    let model: MinutesStudioModel

    var body: some View {
        List {
            Section {
                ForEach(model.fullSectionOrder) { section in
                    Toggle(
                        section.title,
                        isOn: Binding(
                            get: { model.config.isEnabled(section) },
                            set: { model.setSection(section, enabled: $0) }
                        )
                    )
                    .tint(.green)
                }
                .onMove { offsets, destination in
                    model.moveSections(from: offsets, to: destination)
                }
            } footer: {
                Text("Tap Edit to change the order of sections in the document.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Contents")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }
}
