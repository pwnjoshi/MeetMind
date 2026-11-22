import SwiftUI

/// H5 Name and title, saved to the local UserProfile.
struct NameAndTitleView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SettingsViewModel
    @State private var name = ""
    @State private var title = ""

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name).textContentType(.name)
                TextField("Title", text: $title).textContentType(.jobTitle)
            } footer: {
                Text("Shown in the minutes sign-off. Stored only on this iPhone.")
            }
        }
        .navigationTitle("Name and Title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save(); dismiss() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task {
            let profile = viewModel.userProfile ?? .defaultProfile
            name = profile.name
            title = profile.role
        }
    }

    private func save() {
        var profile = viewModel.userProfile ?? .defaultProfile
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.role = title.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.saveUserProfile(profile)
    }
}
