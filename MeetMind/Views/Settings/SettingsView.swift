import SwiftUI
import SwiftData
import OfflineEngineKit
import PhotosUI
import UIKit
import EventKit

/// Main Settings page for Manent (Figma 161:2315).
public struct SettingsView: View {
    @Environment(SettingsViewModel.self) private var environmentViewModel: SettingsViewModel?
    @State private var localViewModel = SettingsViewModel()
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @AppStorage("Manent.workspaceName") private var workspace = "iOS Center"
    @Environment(\.openURL) private var openURL

    private var viewModel: SettingsViewModel {
        environmentViewModel ?? localViewModel
    }

    public init() {}

    public var body: some View {
        Form {
            Section {
                NavigationLink { AccountView(viewModel: viewModel) } label: {
                    HStack(spacing: 12) {
                        SettingsProfileAvatar(profile: viewModel.userProfile ?? .defaultProfile, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.userProfile?.name ?? UserProfile.defaultLocalName)
                                .font(.headline).foregroundStyle(.primary)
                            Text(profileSubtitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Meetings") {
                NavigationLink {
                    Form {
                        Section {
                            TextField("Workspace name", text: $workspace)
                        } footer: {
                            Text("Manent keeps one workspace on this iPhone. This name is only a local label.")
                        }
                    }
                    .navigationTitle("Workspace")
                } label: {
                    LabeledContent("Workspace", value: workspace.isEmpty ? "Local workspace" : workspace)
                }
                NavigationLink { AppleCalendarAccessView() } label: {
                    LabeledContent("Apple Calendar", value: calendarAccess)
                }
                NavigationLink("Notifications") { NotificationsInboxView() }
            }
            Section {
                NavigationLink {
                    LocalRecordingsView()
                } label: {
                    LabeledContent("Local Recordings", value: meetings.filter { $0.resolvedAudioFileURL != nil }.count.formatted())
                }
                NavigationLink("Vidur") { VidurSettingsView() }
            } header: {
                Text("Recordings & Vidur")
            } footer: {
                Text("Manent \(appVersion) · Recordings stay on this iPhone.")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            Section("Developer Settings") {
                NavigationLink("Diagnostics") {
                    Form {
                        NavigationLink("Offline model benchmarks") { OfflineBenchmarkView() }
                        SettingsAboutAndDiagnosticsSection(viewModel: viewModel)
                    }
                    .navigationTitle("Diagnostics")
                }
            }
            SettingsAudioQualitySection(viewModel: viewModel)
            SettingsStorageAndCacheSection(viewModel: viewModel)
            SettingsThemeAndAppearanceSection(viewModel: viewModel)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .tint(Theme.Colors.manentAccent)
    }

    private var profileSubtitle: String {
        if let email = viewModel.userProfile?.email, !email.isEmpty { return email }
        return "Local profile"
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    private var calendarAccess: String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return "Allowed"
        case .writeOnly: return "Add Only"
        default: return "Not Allowed"
        }
    }
}
/// Local-only profile editing: the image is retained in the app's preferences
/// and never enables an account or cloud sync.
struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SettingsViewModel
    @State private var name = ""
    @State private var role = ""
    @State private var email = ""
    @State private var avatarData: Data?
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        SettingsProfileAvatar(profile: draftProfile, size: 112)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.fill").font(.caption.bold()).foregroundStyle(.white)
                                    .frame(width: 32, height: 32).background(Color.accentColor, in: Circle())
                            }
                    }
                    .accessibilityLabel("Choose profile photo")
                    Spacer()
                }
                Text("Stored only on this iPhone").font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            Section("Profile") {
                TextField("Name", text: $name).textContentType(.name)
                TextField("Role", text: $role)
                TextField("Email (optional)", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
            }
        }
        .navigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { save(); dismiss() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task { load() }
        .onChange(of: selectedPhoto) { _, item in
            Task { avatarData = try? await item?.loadTransferable(type: Data.self) }
        }
    }

    private var draftProfile: UserProfile {
        var profile = viewModel.userProfile ?? .defaultProfile
        profile.name = name.isEmpty ? profile.name : name
        profile.avatarImageData = avatarData ?? profile.avatarImageData
        return profile
    }
    private func load() {
        let profile = viewModel.userProfile ?? .defaultProfile
        name = profile.name; role = profile.role; email = profile.email; avatarData = profile.avatarImageData
    }
    private func save() {
        var profile = viewModel.userProfile ?? .defaultProfile
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.role = role.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.avatarImageData = avatarData
        viewModel.saveUserProfile(profile)
    }
}

struct SettingsProfileAvatar: View {
    let profile: UserProfile
    let size: CGFloat
    var body: some View {
        Group {
            if let data = profile.avatarImageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(profile.initials).font(.system(size: size * 0.34, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.accentColor)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
}

@MainActor
struct OfflineAnalysisModelsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var profiles: [ModelProfile] = []
    @State private var installed = Set<String>()
    @State private var operation: Task<Void, Never>?
    @State private var busy = false
    @State private var progress = 0.0
    @State private var message = ""

    var body: some View {
        List {
            Section {
                Text("Meeting audio, transcripts, and analysis stay on this iPhone. Internet is needed only to download public model files. Keep the app open during downloads and meeting analysis.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Hindiâ€“English accuracy is still being evaluated. Review generated tasks and source quotes before accepting them.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !message.isEmpty { Text(message) }
                if busy {
                    ProgressView(value: progress)
                    Button("Pause download") { operation?.cancel() }
                }
            }
            ForEach(profiles) { profile in
                Section(profile.name) {
                    LabeledContent("Download size", value: ByteCountFormatter.string(fromByteCount: profile.downloadBytes, countStyle: .file))
                    LabeledContent("Status", value: installed.contains(profile.id) ? "Downloaded" : "Not downloaded")
                    Button(installed.contains(profile.id) ? "Verify or repair model" : "Download model") {
                        perform {
                            try await OfflineModelStore.shared.install(profile) { value in
                                Task { @MainActor in progress = value }
                            }
                            message = "Model verified and ready."
                        }
                    }.disabled(busy)
                    if installed.contains(profile.id) {
                        Button("Remove model download", role: .destructive) {
                            perform {
                                try await OfflineModelStore.shared.remove(profile)
                                message = "Model removed. Saved recordings and results are preserved. Download it again before analyzing another meeting."
                            }
                        }.disabled(busy)
                    }
                }
            }
            NavigationLink("Model licenses") {
                ScrollView { Text(OfflineModelStore.notices).font(.footnote).textSelection(.enabled).padding() }
                    .navigationTitle("Licenses")
            }
        }
        .navigationTitle("Offline models")
        .task {
            do {
                let ids = Set(MeetingAnalysisPipeline.requiredModelIDs + VidurModel.allCases.map(\.rawValue))
                profiles = try OfflineModelStore.profiles().filter { ids.contains($0.id) }
                await refresh()
            } catch { message = error.localizedDescription }
        }
        .onDisappear { operation?.cancel(); UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in if phase != .active { operation?.cancel() } }
    }

    private func refresh() async {
        var ready = Set<String>()
        for profile in profiles {
            if await OfflineModelStore.shared.isInstalled(profile) { ready.insert(profile.id) }
        }
        installed = ready
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        progress = 0
        message = ""
        UIApplication.shared.isIdleTimerDisabled = true
        operation = Task { @MainActor in
            defer { busy = false; UIApplication.shared.isIdleTimerDisabled = false }
            do { try await action() }
            catch is CancellationError { message = "Paused. Completed download chunks are saved; tap Download to resume." }
            catch { message = error.localizedDescription }
            await refresh()
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(SettingsViewModel())
            .modelContainer(for: Meeting.self, inMemory: true)
    }
}
