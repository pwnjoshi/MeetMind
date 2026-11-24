import SwiftUI

/// H5 Name and title, saved to the local UserProfile.
struct NameAndTitleView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SettingsViewModel
    @State private var name = ""
    @State private var title = ""
    @State private var email = ""

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var shownOnMinutes: String {
        if trimmedName.isEmpty { return "Your name" }
        if trimmedTitle.isEmpty { return trimmedName }
        return "\(trimmedName), \(trimmedTitle)"
    }

    var body: some View {
        Form {
            Section {
                ProfileAvatarView(profile: draftProfile, size: 88)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            Section("Name") {
                TextField("Full Name", text: $name).textContentType(.name)
            }
            Section("Role") {
                TextField("Title", text: $title).textContentType(.jobTitle)
            }
            Section("Contact") {
                TextField("Email (optional)", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SHOWN ON MINUTES AS")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.Colors.manentAccent)
                    Text(shownOnMinutes)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .listRowBackground(Theme.Colors.manentAccent.opacity(0.12))
            } footer: {
                Text("Shown in the minutes sign-off. Stored only on this iPhone.")
            }
        }
        .navigationTitle("Name and Title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") { save(); dismiss() }
                    .disabled(trimmedName.isEmpty)
            }
        }
        .task {
            let profile = viewModel.userProfile ?? .defaultProfile
            name = profile.name
            title = profile.role
            email = profile.email
        }
    }

    private var draftProfile: UserProfile {
        var profile = viewModel.userProfile ?? .defaultProfile
        if !trimmedName.isEmpty { profile.name = trimmedName }
        return profile
    }

    private func save() {
        var profile = viewModel.userProfile ?? .defaultProfile
        profile.name = trimmedName
        profile.role = trimmedTitle
        profile.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.saveUserProfile(profile)
    }
}
