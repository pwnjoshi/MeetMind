import SwiftUI
import SwiftData

/// "Add Person": search people already known on this iPhone (from any meeting) or create a new one.
/// Added people become attendees, present by default, even when they never spoke.
@MainActor
struct MeetingAddPersonSheet: View {
    let meeting: Meeting
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Speaker.name) private var speakers: [Speaker]
    @State private var query = ""
    @State private var added: [String] = []
    @State private var errorMessage: String?

    private var matches: [Speaker] {
        MeetingPeopleEditor.candidates(from: speakers, for: meeting, query: query)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        MeetingPersonForm(meeting: meeting, person: nil, initialName: query)
                    } label: {
                        Label("New Person", systemImage: "person.crop.circle.badge.plus")
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .accessibilityHint("Create someone who is not in the list")
                }
                if !added.isEmpty {
                    Section("Added") {
                        ForEach(added, id: \.self) { name in
                            Label(name, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.Colors.manentAccent)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                    }
                }
                Section {
                    if matches.isEmpty {
                        Text(query.isEmpty ? "No other people on this iPhone yet." : "No one matches \u{201C}\(query)\u{201D}.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(matches, id: \.id) { person in
                        Button { add(person) } label: { candidateRow(person) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(person.name)")
                    }
                } header: {
                    Text("People You Know")
                } footer: {
                    Text("People who never spoke can still be added as attendees and given actions or decisions.")
                }
            }
            .searchable(text: $query, prompt: "Search people")
            .navigationTitle("Add Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .recordErrorAlert("Could Not Add Person", message: $errorMessage)
        }
    }

    private func candidateRow(_ person: Speaker) -> some View {
        HStack(spacing: 12) {
            Text(person.initials)
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color(hex: person.avatarColorHex), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.subheadline)
                if let detail = detail(for: person) {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "plus.circle").foregroundStyle(Theme.Colors.manentAccent)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func detail(for person: Speaker) -> String? {
        let parts = [person.role, person.email].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private func add(_ person: Speaker) {
        do {
            try MeetingPeopleEditor.addAttendee(person, to: meeting, context: context)
            added.append(person.name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Name, optional email and role. Creates a person (when `person` is nil) or edits one.
@MainActor
struct MeetingPersonForm: View {
    let meeting: Meeting
    let person: Speaker?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var email: String
    @State private var role: String
    @State private var errorMessage: String?

    init(meeting: Meeting, person: Speaker?, initialName: String = "") {
        self.meeting = meeting
        self.person = person
        _name = State(initialValue: person?.name ?? initialName)
        _email = State(initialValue: person?.email ?? "")
        _role = State(initialValue: person?.role ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .frame(minHeight: 44)
                TextField("Email (optional)", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: 44)
                TextField("Role (optional)", text: $role)
                    .frame(minHeight: 44)
            } footer: {
                if person == nil {
                    Text("They are added as present. Changes to a person apply in every meeting they are in.")
                } else {
                    Text("Changes apply in every meeting this person is in.")
                }
            }
        }
        .navigationTitle(person == nil ? "New Person" : "Edit Person")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") { save() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .disabled(!canSave)
            }
        }
        .recordErrorAlert("Could Not Save Person", message: $errorMessage)
    }

    private func save() {
        do {
            if let person {
                try MeetingPeopleEditor.updatePerson(person, name: name, email: email, role: role,
                                                     meeting: meeting, context: context)
            } else {
                try MeetingPeopleEditor.addNewAttendee(name: name, email: email, role: role,
                                                       meeting: meeting, context: context)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Sheet wrapper for editing an existing attendee.
@MainActor
struct MeetingPersonEditSheet: View {
    let meeting: Meeting
    let person: Speaker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MeetingPersonForm(meeting: meeting, person: person)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
