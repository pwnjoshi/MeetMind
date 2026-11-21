import SwiftUI
import SwiftData

/// Add People sheet: search people already known on this iPhone, tick them, or create a new person.
struct AddPeopleSheet: View {
    @Bindable var viewModel: MeetingSetupViewModel
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Speaker.name) private var knownSpeakers: [Speaker]
    @State private var searchText = ""
    @State private var showsNewPerson = false

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Known people plus anyone added in this form who is not saved yet.
    private var contacts: [Speaker] {
        var result: [Speaker] = []
        var seen = Set<String>()
        for speaker in knownSpeakers + viewModel.participants {
            guard speaker.name != UserProfile.defaultLocalName else { continue }
            let key = (speaker.email?.lowercased()).flatMap { $0.isEmpty ? nil : $0 } ?? speaker.name.lowercased()
            if seen.insert(key).inserted { result.append(speaker) }
        }
        guard isSearching else { return result }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.filter {
            $0.name.localizedCaseInsensitiveContains(query) || ($0.email ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        PrepCard {
                            Button(isSearching ? "Add Manually" : "New Person\u{2026}") { showsNewPerson = true }
                                .foregroundStyle(Theme.Colors.manentAccent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        }
                        if isSearching {
                            Text("Enter a name and email for someone who isn\u{2019}t in your contacts.")
                                .font(.footnote)
                                .foregroundStyle(PrepStyle.secondaryText)
                                .padding(.horizontal, 16)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        PrepSectionLabel(text: "Contacts")
                        if contacts.isEmpty {
                            Text(isSearching ? "No matches." : "People you add to meetings appear here.")
                                .font(.footnote)
                                .foregroundStyle(PrepStyle.secondaryText)
                                .padding(.horizontal, 16)
                        } else {
                            PrepCard {
                                ForEach(Array(contacts.enumerated()), id: \.element.id) { index, speaker in
                                    Button { toggle(speaker) } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(speaker.name).foregroundStyle(.primary)
                                                if let email = speaker.email, !email.isEmpty {
                                                    Text(email).font(.subheadline).foregroundStyle(PrepStyle.secondaryText)
                                                }
                                            }
                                            Spacer()
                                            if isSelected(speaker) {
                                                Image(systemName: "checkmark").foregroundStyle(.primary)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(isSelected(speaker) ? .isSelected : [])
                                    if index < contacts.count - 1 { Divider().padding(.leading, 16) }
                                }
                            }
                        }
                        if viewModel.isParticipantLimitReached {
                            Text("Maximum participant limit (50) reached")
                                .font(.footnote)
                                .foregroundStyle(Theme.Colors.coralRed)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(PrepStyle.background.ignoresSafeArea())
            .navigationTitle("Add People")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Contacts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    PrepConfirmButton { dismiss() }
                }
            }
            .sheet(isPresented: $showsNewPerson) {
                NewPersonSheet(initialName: searchText) { speaker in
                    viewModel.addParticipant(speaker)
                    searchText = ""
                }
            }
        }
    }

    private func isSelected(_ speaker: Speaker) -> Bool {
        viewModel.participants.contains { selected in
            selected.id == speaker.id
                || (selected.email?.lowercased()).map { !$0.isEmpty && $0 == speaker.email?.lowercased() } ?? false
        }
    }

    private func toggle(_ speaker: Speaker) {
        if let existing = viewModel.participants.first(where: { selected in
            selected.id == speaker.id
                || (selected.email?.lowercased()).map { !$0.isEmpty && $0 == speaker.email?.lowercased() } ?? false
        }) {
            viewModel.removeParticipant(existing)
        } else {
            viewModel.addParticipant(speaker)
        }
    }
}

/// New Person sheet. Creates a Speaker; it is saved with the meeting.
struct NewPersonSheet: View {
    var initialName: String = ""
    let onCreate: (Speaker) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""

    private static let avatarColors = ["#FF9500", "#FF2D55", "#34C759", "#5856D6", "#22AFC4", "#AF52DE"]

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canCreate: Bool {
        !trimmedName.isEmpty && (trimmedEmail.isEmpty || trimmedEmail.contains("@"))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    field("Name", placeholder: "Name", text: $name, keyboard: .default)
                    field("Email", placeholder: "Email", text: $email, keyboard: .emailAddress)
                    VStack(alignment: .leading, spacing: 8) {
                        field("Phone (Optional)", placeholder: "Phone", text: $phone, keyboard: .phonePad)
                        Text("Minutes are shared by email. A phone number is optional.")
                            .font(.footnote)
                            .foregroundStyle(PrepStyle.secondaryText)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(PrepStyle.background.ignoresSafeArea())
            .navigationTitle("New Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { PrepCloseButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    PrepConfirmButton(isEnabled: canCreate) { create() }
                }
            }
            .onAppear {
                if name.isEmpty { name = initialName }
            }
        }
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PrepSectionLabel(text: label)
            PrepCard {
                TextField(placeholder, text: text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(keyboard == .default ? .words : .never)
                    .autocorrectionDisabled(keyboard != .default)
                    .padding(16)
            }
        }
    }

    private func create() {
        guard canCreate else { return }
        let seed = trimmedName.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let color = Self.avatarColors[seed % Self.avatarColors.count]
        let speaker = Speaker(
            name: trimmedName,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail,
            avatarColorHex: color
        )
        onCreate(speaker)
        dismiss()
    }
}
