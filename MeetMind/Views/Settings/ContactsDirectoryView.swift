import SwiftUI
import SwiftData

/// Pure filtering and de-duplication for the local people directory.
enum ContactsDirectory {
    private static let palette = ["#30B0C7", "#FF9500", "#FF2D55", "#AF52DE", "#34C759"]

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func richness(_ speaker: Speaker) -> Int {
        let emailScore = (speaker.email ?? "").isEmpty ? 0 : 1000
        return emailScore + speaker.meetings.count
    }

    /// Named people (voice labels such as "Speaker 1" are excluded), one per name, filtered by `query`.
    @MainActor
    static func people(from speakers: [Speaker], query: String) -> [Speaker] {
        let needle = key(query)
        var chosen: [String: Speaker] = [:]
        for speaker in speakers {
            let name = key(speaker.name)
            if name.isEmpty || MeetingPeopleEditor.isGenericVoice(speaker) { continue }
            if !needle.isEmpty {
                let email = (speaker.email ?? "").lowercased()
                let role = (speaker.role ?? "").lowercased()
                if !name.contains(needle) && !email.contains(needle) && !role.contains(needle) { continue }
            }
            if let current = chosen[name] {
                if richness(speaker) > richness(current) { chosen[name] = speaker }
            } else {
                chosen[name] = speaker
            }
        }
        return chosen.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func color(forCount count: Int) -> String {
        palette[count % palette.count]
    }

    static func cleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// H12 Contacts. A local people directory built from the people in your meetings.
/// It never asks for system Contacts access.
@MainActor
struct ContactsDirectoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Speaker.name) private var speakers: [Speaker]
    @State private var query = ""
    @State private var editing: ContactDraft?

    private var people: [Speaker] {
        ContactsDirectory.people(from: speakers, query: query)
    }

    var body: some View {
        List {
            Section {
                SettingsBanner(
                    title: "Saved on this iPhone",
                    detail: "People come from your meetings. Manent does not read your iPhone Contacts.",
                    systemImage: "person.2.fill",
                    tint: Theme.Colors.manentAccent
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section("People You Meet") {
                if people.isEmpty {
                    Text(query.isEmpty ? "No people yet. Add someone, or name a voice in a meeting." : "No matches.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(people, id: \.id) { person in
                    Button { editing = ContactDraft(person: person) } label: { row(person) }
                        .buttonStyle(.plain)
                }
            }
        }
        .searchable(text: $query, prompt: "Search people")
        .navigationTitle("Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Person", systemImage: "plus") { editing = ContactDraft(person: nil) }
            }
        }
        .sheet(item: $editing) { draft in
            ContactEditSheet(draft: draft, context: context, existingCount: speakers.count)
        }
    }

    private func row(_ person: Speaker) -> some View {
        HStack(spacing: 12) {
            Text(person.initials)
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color(hex: person.avatarColorHex), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.subheadline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle(person))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ person: Speaker) -> String {
        if let email = person.email, !email.isEmpty { return email }
        if let role = person.role, !role.isEmpty { return role }
        let count = person.meetings.count
        return count == 1 ? "1 meeting" : "\(count) meetings"
    }
}

struct ContactDraft: Identifiable {
    let id = UUID()
    let person: Speaker?
}

@MainActor
struct ContactEditSheet: View {
    let draft: ContactDraft
    let context: ModelContext
    let existingCount: Int
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var role = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).textContentType(.name)
                    TextField("Email (optional)", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Role (optional)", text: $role)
                } footer: {
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle(draft.person == nil ? "Add Person" : "Edit Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                name = draft.person?.name ?? ""
                email = draft.person?.email ?? ""
                role = draft.person?.role ?? ""
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let all = (try? context.fetch(FetchDescriptor<Speaker>())) ?? []
        let clash = all.contains { other in
            other.id != draft.person?.id
                && !MeetingPeopleEditor.isGenericVoice(other)
                && other.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        if clash {
            errorMessage = "\(trimmed) is already in your people."
            return
        }
        if let person = draft.person {
            let previous = (person.name, person.email, person.role)
            person.name = trimmed
            person.email = ContactsDirectory.cleaned(email)
            person.role = ContactsDirectory.cleaned(role)
            do { try context.save() } catch {
                (person.name, person.email, person.role) = previous
                context.rollback()
                errorMessage = error.localizedDescription
                return
            }
        } else {
            let created = Speaker(name: trimmed, email: ContactsDirectory.cleaned(email),
                                  role: ContactsDirectory.cleaned(role),
                                  avatarColorHex: ContactsDirectory.color(forCount: existingCount))
            context.insert(created)
            do { try context.save() } catch {
                context.delete(created)
                errorMessage = error.localizedDescription
                return
            }
        }
        dismiss()
    }
}
