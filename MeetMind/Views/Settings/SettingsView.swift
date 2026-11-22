import SwiftUI
import SwiftData
import OfflineEngineKit
import PhotosUI
import UIKit
import EventKit
import UserNotifications

/// Profile and Settings (v5 H1). Rows are grouped like the Figma frame; every row opens a
/// screen that exists in this build. Manent is account-free and local-only.
public struct SettingsView: View {
    @Environment(SettingsViewModel.self) private var environmentViewModel: SettingsViewModel?
    @State private var localViewModel = SettingsViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState: AppState?
    @Environment(NavigationRouter.self) private var router: NavigationRouter?
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @Query private var actionItems: [ActionItem]
    @Query private var speakers: [Speaker]
    @AppStorage(OrganizationProfileStore.nameKey) private var workspace = "iOS Center"
    @AppStorage(MinutesLanguagePreference.key) private var minutesLanguage = MinutesLanguage.english.rawValue
    @State private var studio = MinutesStudioStore.shared
    @State private var notificationsStatus = "Off"
    @State private var showsEraseAlert = false
    @State private var eraseError: String?
    @State private var isErasing = false

    private var viewModel: SettingsViewModel {
        environmentViewModel ?? localViewModel
    }

    public init() {}

    public var body: some View {
        List {
            Section {
                profileHeader
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            youSection
            organizationSection
            recordingSection
            vidurSection
            connectionsSection
            privacySection
            Section("Models and Storage") {
                NavigationLink {
                    OfflineAnalysisModelsView()
                } label: {
                    SettingsRowLabel(title: "Offline Analysis Models", systemImage: "cpu", color: .indigo)
                }
            }
            SettingsStorageAndCacheSection(viewModel: viewModel)
            SettingsThemeAndAppearanceSection(viewModel: viewModel)
            Section("Developer Settings") {
                NavigationLink("Diagnostics") {
                    Form {
                        NavigationLink("Offline model benchmarks") { OfflineBenchmarkView() }
                        SettingsAboutAndDiagnosticsSection(viewModel: viewModel)
                    }
                    .navigationTitle("Diagnostics")
                }
            } footer: {
                Text("Manent \(appVersion) \u{00B7} Recordings and minutes stay on this iPhone.")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .tint(Theme.Colors.manentAccent)
        .task { await refreshNotificationStatus() }
        .alert("Delete All Data?", isPresented: $showsEraseAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { eraseEverything() }
        } message: {
            Text("This deletes every recording, transcript and minute on this iPhone. This can\u{2019}t be undone.")
        }
        .alert("Could not delete everything", isPresented: Binding(
            get: { eraseError != nil }, set: { if !$0 { eraseError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(eraseError ?? "")
        }
    }

    // MARK: Header

    private var profile: UserProfile { viewModel.userProfile ?? .defaultProfile }

    private var profileHeader: some View {
        VStack(spacing: 8) {
            NavigationLink {
                ProfileEditorView(viewModel: viewModel)
            } label: {
                SettingsProfileAvatar(profile: profile, size: 88)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(Theme.Colors.manentAccent)
                            .frame(width: 26, height: 26)
                            .background(.white, in: Circle())
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit profile photo")
            Text(profile.name).font(.title2.bold())
            Text(profileSubtitle).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                SettingsStatTile(value: meetings.count.formatted(), label: "Meetings")
                SettingsStatTile(value: recordedText, label: "Recorded")
                SettingsStatTile(value: openActionCount.formatted(), label: "Open actions", tint: Theme.Colors.warmAmber)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var profileSubtitle: String {
        var parts: [String] = []
        if !profile.role.isEmpty { parts.append(profile.role) }
        if !workspace.isEmpty { parts.append(workspace) }
        if parts.isEmpty { return "Local profile" }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var openActionCount: Int {
        actionItems.filter { !$0.isCompleted }.count
    }

    private var recordedText: String {
        let seconds = meetings.reduce(0.0) { $0 + max(0, $1.duration) }
        let hours = seconds / 3600
        if hours >= 1 { return "\(Int(hours.rounded())) h" }
        return "\(Int((seconds / 60).rounded())) m"
    }

    // MARK: Sections

    private var youSection: some View {
        Section("You") {
            NavigationLink { NameAndTitleView(viewModel: viewModel) } label: {
                SettingsRowLabel(title: "Name and Title", systemImage: "person.fill", color: .indigo, value: profile.role)
            }
            NavigationLink { SignatureSettingsView() } label: {
                SettingsRowLabel(title: "Signature", systemImage: "signature", color: .purple,
                                 value: SignatureStore.shared.hasSignature ? "Added" : "Set Up")
            }
        }
    }

    private var organizationSection: some View {
        Section("Organization and Minutes") {
            NavigationLink { LetterheadAndLogoView() } label: {
                SettingsRowLabel(title: "Letterhead and Logo", systemImage: "doc.text.image", color: .teal,
                                 value: studio.letterheads.isEmpty ? workspace : "Added")
            }
            NavigationLink { MinutesLanguageView() } label: {
                SettingsRowLabel(title: "Minutes Language", systemImage: "globe", color: .blue,
                                 value: (MinutesLanguage(rawValue: minutesLanguage) ?? .english).title)
            }
            NavigationLink { MinutesStudioSettingsView() } label: {
                SettingsRowLabel(title: "Minutes Studio", systemImage: "doc.richtext", color: .pink)
            }
        }
    }

    private var recordingSection: some View {
        Section("Recording") {
            NavigationLink { LocalRecordingsView() } label: {
                SettingsRowLabel(title: "Recordings on This iPhone", systemImage: "waveform", color: .indigo,
                                 value: recordingsSizeText)
            }
            NavigationLink {
                Form { SettingsAudioQualitySection(viewModel: viewModel) }
                    .navigationTitle("Audio Quality")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                SettingsRowLabel(title: "Audio Quality", systemImage: "speaker.wave.2.fill", color: .pink,
                                 value: viewModel.audioQuality == .high ? "High" : "Standard")
            }
            NavigationLink { TestMicrophoneView() } label: {
                SettingsRowLabel(title: "Test Microphone", systemImage: "mic.fill", color: .red)
            }
        }
    }

    private var vidurSection: some View {
        Section("Vidur") {
            NavigationLink { VidurSettingsView() } label: {
                SettingsRowLabel(title: "Vidur", systemImage: "sparkles", color: Theme.Colors.manentAccent, value: "On this iPhone")
            }
        }
    }

    private var connectionsSection: some View {
        Section("Connections") {
            NavigationLink { AppleCalendarAccessView() } label: {
                SettingsRowLabel(title: "Apple Calendar", systemImage: "calendar", color: .red, value: calendarAccess)
            }
            NavigationLink { ContactsDirectoryView() } label: {
                SettingsRowLabel(title: "Contacts", systemImage: "person.crop.circle.fill", color: .gray,
                                 value: ContactsDirectory.people(from: speakers, query: "").count.formatted())
            }
            NavigationLink { NotificationsInboxView() } label: {
                SettingsRowLabel(title: "Notifications", systemImage: "bell.fill", color: .red, value: notificationsStatus)
            }
        }
    }

    private var privacySection: some View {
        Section("Privacy and Data") {
            NavigationLink { ExportAllMinutesView() } label: {
                SettingsRowLabel(title: "Export All Minutes", systemImage: "square.and.arrow.up", color: .blue)
            }
            Button(role: .destructive) {
                showsEraseAlert = true
            } label: {
                HStack(spacing: 12) {
                    SettingsIconTile(systemImage: "trash.fill", color: .red)
                    Text("Delete All Data").font(.subheadline).foregroundStyle(.red)
                    Spacer()
                }
            }
            .disabled(isErasing)
        }
    }

    // MARK: Values

    private var recordingsSizeText: String {
        var total: Int64 = 0
        for meeting in meetings {
            if let url = meeting.resolvedAudioFileURL { total += LocalRecordingStorage.fileSize(at: url) }
        }
        return LocalRecordingStorage.formatted(bytes: total)
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    private var calendarAccess: String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return "Allowed"
        case .writeOnly: return "Add Only"
        default: return "Not Allowed"
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: notificationsStatus = "On"
        default: notificationsStatus = "Off"
        }
    }

    private func eraseEverything() {
        guard !isErasing else { return }
        isErasing = true
        Task { @MainActor in
            defer { isErasing = false }
            do {
                _ = try await DeletionCoordinator(modelContext: modelContext).eraseAll()
                OrganizationProfileStore().eraseAll()
                viewModel.userProfile = .defaultProfile
                router?.popToRoot(on: .home)
                router?.popToRoot(on: .actionItems)
                router?.popToRoot(on: .search)
                appState?.resetOnboarding()
            } catch {
                eraseError = error.localizedDescription
            }
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
                Text("Hindi–English accuracy is still being evaluated. Review generated tasks and source quotes before accepting them.")
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
