import SwiftUI
import SwiftData

/// One topic: title, outcome and discussion points (Figma B6f).
struct MoMTopicEditor: View {
    @Binding var topic: MoMTopic

    var body: some View {
        Form {
            Section("Topic") {
                TextField("Title", text: $topic.title)
            }
            Section("Outcome") {
                Picker("Outcome", selection: $topic.outcomeKind) {
                    Text("Resolved").tag(MoMOutcomeKind.resolved)
                    Text("Deferred").tag(MoMOutcomeKind.deferred)
                    Text("Open").tag(MoMOutcomeKind.open)
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 4) {
                    Text(topic.outcomeKind.label).font(.caption2.weight(.bold)).foregroundStyle(tint)
                    TextField("Outcome", text: $topic.outcomeText, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            Section("Discussion") {
                ForEach(topic.discussion.indices, id: \.self) { index in
                    TextField("Point", text: Binding(
                        get: { topic.discussion.indices.contains(index) ? topic.discussion[index] : "" },
                        set: { if topic.discussion.indices.contains(index) { topic.discussion[index] = $0 } }
                    ), axis: .vertical)
                }
                .onDelete { topic.discussion.remove(atOffsets: $0) }
                Button("Add Point", systemImage: "plus") { topic.discussion.append("") }
            }
        }
        .navigationTitle(topic.title.isEmpty ? "Topic" : topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tint: Color {
        switch topic.outcomeKind {
        case .resolved: return .green
        case .deferred: return .orange
        case .open: return .gray
        }
    }
}

private enum MoMAttendanceChoice: String, CaseIterable, Identifiable {
    case member = "Member"
    case invitee = "Invitee"
    case absent = "Absent"
    case leave = "Leave granted"
    var id: String { rawValue }
}

/// Edits every section of the Minutes of Meeting. Saving writes the sidecar and the shared people data in one pass.
struct MoMEditMinutesSheet: View {
    let meeting: Meeting
    let document: MoMDocumentModel
    let onOpenClassicEditor: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var store = MoMSidecarStore.shared

    @State private var venue = ""
    @State private var minutesBy = ""
    @State private var chairID = ""
    @State private var topics: [MoMTopic] = []
    @State private var aob = ""
    @State private var closure = ""
    @State private var hasNext = false
    @State private var nextDate = Date()
    @State private var nextNote = ""
    @State private var choices: [String: MoMAttendanceChoice] = [:]
    @State private var original: [String: MoMAttendanceChoice] = [:]
    @State private var errorMessage: String?
    @State private var loaded = false

    private var people: [Speaker] { meeting.namedAttendees }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Venue", text: $venue)
                    Picker("Chairperson", selection: $chairID) {
                        Text("Not set").tag("")
                        ForEach(people, id: \.id) { Text($0.name).tag($0.id.uuidString) }
                    }
                    TextField("Minutes by", text: $minutesBy)
                }
                Section("Attendance") {
                    if people.isEmpty { Text("No attendees yet.").foregroundStyle(.secondary) }
                    ForEach(people, id: \.id) { person in
                        Picker(person.name, selection: choiceBinding(person)) {
                            ForEach(MoMAttendanceChoice.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                }
                Section("Agenda and Discussion") {
                    ForEach($topics) { $topic in
                        NavigationLink {
                            MoMTopicEditor(topic: $topic)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.title.isEmpty ? "Untitled topic" : topic.title)
                                if topic.hasOutcome {
                                    Text("\(topic.outcomeKind.label.capitalized): \(topic.outcomeText)")
                                        .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                    .onDelete { topics.remove(atOffsets: $0) }
                    .onMove { topics.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add Topic", systemImage: "plus") {
                        topics.append(MoMTopic(id: "user-\(UUID().uuidString)", title: ""))
                    }
                }
                Section("Any Other Business") {
                    TextField("Any other business", text: $aob, axis: .vertical).lineLimit(2...6)
                }
                Section("Next Meeting") {
                    Toggle("Set a date", isOn: $hasNext)
                    if hasNext { DatePicker("Date", selection: $nextDate) }
                    TextField("Note (for example Same venue, hybrid)", text: $nextNote)
                }
                Section("Closure") {
                    TextField("Closure", text: $closure, axis: .vertical).lineLimit(2...6)
                }
                Section {
                    Button("Edit Summary, Decisions and Actions", systemImage: "list.bullet") {
                        dismiss()
                        onOpenClassicEditor()
                    }
                } footer: {
                    Text("Changing the discussion, attendance or closure returns the minutes to Draft and removes the signature.")
                }
            }
            .navigationTitle("Edit Minutes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") { save() }
                        .labelStyle(.iconOnly)
                        .toolbarConfirmButtonStyle()
                }
            }
            .alert("Could Not Save Minutes", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .onAppear(perform: load)
        }
    }

    private func choiceBinding(_ person: Speaker) -> Binding<MoMAttendanceChoice> {
        Binding(
            get: { choices[person.id.uuidString] ?? .member },
            set: { choices[person.id.uuidString] = $0 }
        )
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let sidecar = store.sidecar(for: meeting.id)
        venue = sidecar.venue ?? ""
        minutesBy = sidecar.minutesBy ?? document.minutesBy ?? ""
        chairID = sidecar.chairpersonID ?? people.first(where: { $0.name == document.chairperson })?.id.uuidString ?? ""
        topics = document.topics
        aob = sidecar.anyOtherBusiness ?? ""
        closure = sidecar.closure ?? document.closure
        hasNext = sidecar.nextMeetingDate != nil
        nextDate = sidecar.nextMeetingDate ?? Date().addingTimeInterval(7 * 86_400)
        nextNote = sidecar.nextMeetingNote ?? ""
        let absent = Set(meeting.absentParticipantIDs ?? [])
        for person in people {
            let key = person.id.uuidString
            let choice: MoMAttendanceChoice
            if absent.contains(person.id) {
                choice = sidecar.leaveGrantedIDs.contains(key) ? .leave : .absent
            } else {
                choice = sidecar.inviteeIDs.contains(key) ? .invitee : .member
            }
            choices[key] = choice
            original[key] = choice
        }
    }

    private func save() {
        let cleanTopics = topics.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { topic -> MoMTopic in
                var copy = topic
                copy.discussion = topic.discussion.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                return copy
            }
        let topicsChanged = cleanTopics != document.topics
        let current = store.sidecar(for: meeting.id)
        let trimmedAOB = aob.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedClosure = closure.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = nextNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let newDate: Date? = hasNext ? nextDate : nil
        let materialChanged = topicsChanged
            || trimmedAOB != (current.anyOtherBusiness ?? "")
            || trimmedClosure != (current.closure ?? document.closure)
            || newDate != current.nextMeetingDate
            || trimmedNote != (current.nextMeetingNote ?? "")
            || choices != original
        var invitees: [String] = []
        var leaveGranted: [String] = []
        for (key, choice) in choices {
            if choice == .invitee { invitees.append(key) }
            if choice == .leave { leaveGranted.append(key) }
        }
        let venueValue = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        let byValue = minutesBy.trimmingCharacters(in: .whitespacesAndNewlines)
        let chair = chairID
        do {
            for person in people {
                let key = person.id.uuidString
                guard let choice = choices[key], choice != original[key] else { continue }
                let shouldBeAbsent = choice == .absent || choice == .leave
                if MeetingPeopleEditor.isAbsent(person, in: meeting) != shouldBeAbsent {
                    try MeetingPeopleEditor.setAbsent(shouldBeAbsent, person: person, meeting: meeting, context: context)
                }
            }
            try MoMEditor.edit(meeting, context: context, store: store, material: materialChanged) { sidecar in
                sidecar.venue = venueValue.isEmpty ? nil : venueValue
                sidecar.minutesBy = byValue.isEmpty ? nil : byValue
                sidecar.chairpersonID = chair.isEmpty ? nil : chair
                sidecar.inviteeIDs = invitees
                sidecar.leaveGrantedIDs = leaveGranted
                if topicsChanged { sidecar.topics = cleanTopics }
                sidecar.anyOtherBusiness = trimmedAOB.isEmpty ? nil : trimmedAOB
                sidecar.closure = trimmedClosure.isEmpty ? nil : trimmedClosure
                sidecar.nextMeetingDate = newDate
                sidecar.nextMeetingNote = trimmedNote.isEmpty ? nil : trimmedNote
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
