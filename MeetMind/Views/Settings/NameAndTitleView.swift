import SwiftUI
import PhotosUI
import UIKit

/// H5 profile editor. Profile text and the optional photo remain on this iPhone.
struct NameAndTitleView: View {
    private enum Field: Hashable {
        case name
        case role
        case email
    }

    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SettingsViewModel
    let navigationTitle: String

    @State private var name = ""
    @State private var role = ""
    @State private var email = ""
    @State private var avatarData: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoError: String?
    @State private var hasLoaded = false
    @FocusState private var focusedField: Field?

    init(viewModel: SettingsViewModel, navigationTitle: String = "Name and Title") {
        self.viewModel = viewModel
        self.navigationTitle = navigationTitle
    }

    private var isNameValid: Bool {
        ProfileFormatting.isValidName(name)
    }

    private var shownOnMinutes: String {
        ProfileFormatting.shownOnMinutes(name: name, role: role)
    }

    var body: some View {
        Form {
            Section {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    SettingsProfileAvatar(profile: draftProfile, size: 80)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(ProfilePalette.accent, in: Circle())
                                .overlay(Circle().strokeBorder(ProfilePalette.cardBackground, lineWidth: 2))
                                .offset(x: 3, y: 3)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose profile photo")
                .frame(maxWidth: .infinity)

                Text("Stored only on this iPhone")
                    .font(.footnote)
                    .foregroundStyle(ProfilePalette.secondaryText)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            Section {
                TextField("Full name", text: $name, axis: .vertical)
                    .textContentType(.name)
                    .lineLimit(1...4)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .role }
            } header: {
                Text("Name")
            } footer: {
                if hasLoaded && !isNameValid {
                    Label("Enter a name containing at least one visible character.", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(ProfilePalette.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Name error. Enter a name containing at least one visible character.")
                }
            }

            Section("Role") {
                TextField("Role or title", text: $role, axis: .vertical)
                    .textContentType(.jobTitle)
                    .lineLimit(1...4)
                    .focused($focusedField, equals: .role)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .email }
            }

            Section("Contact") {
                TextField("Email (optional)", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SHOWN ON MINUTES AS")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ProfilePalette.accent)
                    Text(shownOnMinutes)
                        .font(.headline)
                        .foregroundStyle(ProfilePalette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .listRowBackground(ProfilePalette.accent.opacity(0.12))
            } footer: {
                Text("This sign-off is stored with your local profile. Your full values are saved without a length limit.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(!isNameValid)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .task { loadIfNeeded() }
        .onChange(of: selectedPhoto) { _, item in
            loadPhoto(item)
        }
        .alert("Could not use this photo", isPresented: Binding(
            get: { photoError != nil },
            set: { if !$0 { photoError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(photoError ?? "")
        }
    }

    private var draftProfile: UserProfile {
        var profile = viewModel.userProfile ?? .defaultProfile
        if isNameValid {
            profile.name = ProfileFormatting.cleaned(name)
        }
        profile.avatarImageData = avatarData ?? profile.avatarImageData
        return profile
    }

    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        let profile = viewModel.userProfile ?? .defaultProfile
        name = profile.name
        role = profile.role
        email = profile.email
        avatarData = profile.avatarImageData
        hasLoaded = true
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      UIImage(data: data) != nil else {
                    photoError = "Choose a valid image file."
                    return
                }
                avatarData = data
            } catch {
                photoError = error.localizedDescription
            }
            selectedPhoto = nil
        }
    }

    private func save() {
        guard isNameValid else { return }
        var profile = viewModel.userProfile ?? .defaultProfile
        profile.name = ProfileFormatting.cleaned(name)
        profile.role = ProfileFormatting.cleaned(role)
        profile.email = ProfileFormatting.cleaned(email)
        profile.avatarImageData = avatarData
        viewModel.saveUserProfile(profile)
    }
}
