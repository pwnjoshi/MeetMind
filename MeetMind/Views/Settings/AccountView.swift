import SwiftUI
import SwiftData

/// Local profile and data controls (Figma 161:2360, Delete account 161:2387/2408, Sign Out 1794:13347).
/// Manent has no account or sign-in, so "Sign Out" and "Delete Account" are replaced by
/// one truthful action: erase everything stored on this iPhone.
struct AccountView: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState: AppState?
    @Environment(NavigationRouter.self) private var router: NavigationRouter?
    @Query private var meetings: [Meeting]

    @State private var showingEraseAlert = false
    @State private var errorMessage: String?

    private var profile: UserProfile { viewModel.userProfile ?? .defaultProfile }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    SettingsProfileAvatar(profile: profile, size: 96)
                    Text(profile.name).font(.title3.bold())
                    Text(profile.email.isEmpty ? (profile.role.isEmpty ? "Local profile" : profile.role) : profile.email)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                NavigationLink("Edit Profile") { ProfileEditorView(viewModel: viewModel) }
            } footer: {
                Text("Your name, role and photo are stored only on this iPhone. Manent has no account or sign-in.")
            }
            Section {
                Button("Erase All Local Data", role: .destructive) { showingEraseAlert = true }
            } footer: {
                Text("Permanently deletes all \(meetings.count) meetings, transcripts, minutes, tasks, notes, recordings, photos, custom document templates, processing records, Vidur history, your profile and private settings from this iPhone, then returns to onboarding. Downloaded public models and the selected model are kept. This cannot be undone.")
            }
        }
        .navigationTitle("Profile & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Erase everything on this iPhone?", isPresented: $showingEraseAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Erase Everything", role: .destructive) { eraseEverything() }
        } message: {
            Text("This permanently deletes every meeting, transcript, minute, task, note, recording, attachment, custom template and processing record Manent saved, plus your profile, Vidur history and private settings. Downloaded public models and your selected model are kept. There is no backup and no way to undo this.")
        }
        .alert("Could not erase everything", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func eraseEverything() {
        Task { @MainActor in
            do {
                _ = try await DeletionCoordinator(modelContext: modelContext).eraseAll()
                viewModel.userProfile = .defaultProfile
                router?.popToRoot(on: .home)
                router?.popToRoot(on: .actionItems)
                router?.popToRoot(on: .search)
                appState?.resetOnboarding()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
