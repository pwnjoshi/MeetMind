import SwiftUI
import SwiftData
import OfflineEngineKit
import UIKit
import EventKit
import UserNotifications

/// Profile and Settings (v5 H1). Rows are grouped like the Figma frame; every row opens a
/// screen that exists in this build. Manent is account-free and local-only.
public struct SettingsView: View {
    @Environment(SettingsViewModel.self) private var environmentViewModel: SettingsViewModel?
    @State private var localViewModel = SettingsViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppState.self) private var appState: AppState?
    @Environment(NavigationRouter.self) private var router: NavigationRouter?
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @Query private var actionItems: [ActionItem]
    @Query private var speakers: [Speaker]
    @AppStorage(OrganizationProfileStore.nameKey) private var workspace = "iOS Center"
    @AppStorage(MinutesLanguagePreference.key) private var minutesLanguage = MinutesLanguage.english.rawValue
    @State private var studio = MinutesStudioStore.shared
    @AppStorage(MinutesFormat.preferenceKey) private var minutesFormatRaw = ""
    @State private var notificationsStatus = "Off"
    @State private var showsEraseAlert = false
    @State private var eraseError: String?
    @State private var isErasing = false
    @State private var showsProfileEditor = false
    private let fixtureStatistics: ProfileStatistics?

    private var viewModel: SettingsViewModel {
        environmentViewModel ?? localViewModel
    }

    public init() {
        fixtureStatistics = nil
    }

    init(fixtureStatistics: ProfileStatistics) {
        self.fixtureStatistics = fixtureStatistics
    }

    public var body: some View {
        List {
            Section {
                profileHeader
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            youSection
                .profileSectionRows()
            organizationSection
                .profileSectionRows()
            recordingSection
                .profileSectionRows()
            vidurSection
                .profileSectionRows()
            connectionsSection
                .profileSectionRows()
            privacySection
                .profileSectionRows()
            appSection
                .profileSectionRows()
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(ProfilePalette.sectionSpacing)
        .environment(\.defaultMinListRowHeight, 52)
        .scrollContentBackground(.hidden)
        .background(ProfilePalette.groupedBackground)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsProfileEditor = true } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Edit profile")
            }
        }
        .navigationDestination(isPresented: $showsProfileEditor) {
            ProfileEditorView(viewModel: viewModel)
        }
        .tint(ProfilePalette.accent)
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
        VStack(spacing: 5) {
            Button { showsProfileEditor = true } label: {
                SettingsProfileAvatar(profile: profile, size: 76)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ProfilePalette.accent)
                            .frame(width: 27, height: 27)
                            .background(ProfilePalette.cardBackground, in: Circle())
                            .overlay(Circle().strokeBorder(ProfilePalette.separator.opacity(0.25), lineWidth: 0.5))
                            .shadow(color: Color.black.opacity(0.10), radius: 2, y: 1)
                            .offset(x: 3, y: 3)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit profile photo")

            Text(profile.name)
                .font(.title.bold())
                .foregroundStyle(ProfilePalette.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .allowsTightening(true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
                .padding(.top, 5)

            profileMetadata
                .frame(maxWidth: 330)

            Label("On this iPhone", systemImage: "lock.fill")
                .font(.caption2)
                .foregroundStyle(ProfilePalette.secondaryText)
                .padding(.top, 1)

            statisticsRow
                .padding(.top, 9)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var profileMetadata: some View {
        let role = ProfileFormatting.cleaned(profile.role)
        let organization = ProfileFormatting.cleaned(workspace)
        if role.isEmpty && organization.isEmpty {
            Text("Local profile")
                .font(.subheadline)
                .foregroundStyle(ProfilePalette.secondaryText)
        } else if dynamicTypeSize.isAccessibilitySize {
            verticalProfileMetadata(role: role, organization: organization)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    if !role.isEmpty {
                        Text(role).fixedSize(horizontal: true, vertical: false)
                    }
                    if !role.isEmpty && !organization.isEmpty {
                        Text("·")
                    }
                    if !organization.isEmpty {
                        Text(organization).fixedSize(horizontal: true, vertical: false)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(ProfilePalette.secondaryText)
                verticalProfileMetadata(role: role, organization: organization)
            }
        }
    }

    private func verticalProfileMetadata(role: String, organization: String) -> some View {
        VStack(spacing: 1) {
            if !role.isEmpty {
                Text(role)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !organization.isEmpty {
                Text(organization)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.subheadline)
        .foregroundStyle(ProfilePalette.secondaryText)
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var statisticsRow: some View {
        let values = profileStatistics
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    SettingsStatTile(value: values.meetings, label: "Meetings", width: 144)
                    SettingsStatTile(value: values.recorded, label: "Recorded", width: 144)
                    SettingsStatTile(value: values.openActions, label: "Open actions", tint: ProfilePalette.orange, width: 144)
                }
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 8) {
                SettingsStatTile(value: values.meetings, label: "Meetings")
                SettingsStatTile(value: values.recorded, label: "Recorded")
                SettingsStatTile(value: values.openActions, label: "Open actions", tint: ProfilePalette.orange)
            }
            .padding(.horizontal, 16)
        }
    }

    private var profileStatistics: ProfileStatistics {
        fixtureStatistics ?? ProfileStatistics(
            meetings: meetings.count.formatted(),
            recorded: recordedText,
            openActions: openActionCount.formatted()
        )
    }

    private var openActionCount: Int {
        actionItems.filter { !$0.isCompleted }.count
    }

    private var recordedText: String {
        let seconds = meetings.reduce(0.0) { $0 + max(0, $1.duration) }
        return ProfileFormatting.recordedDurationText(seconds: seconds)
    }

    // MARK: Sections

    private var youSection: some View {
        Section {
            NavigationLink { NameAndTitleView(viewModel: viewModel) } label: {
                SettingsRowLabel(title: "Name and Title", systemImage: "person.fill",
                                 color: ProfilePalette.avatar, value: profile.role)
            }
            NavigationLink { SignatureSettingsView() } label: {
                SettingsRowLabel(title: "Signature", systemImage: "signature",
                                 color: ProfilePalette.accent,
                                 value: SignatureStore.shared.hasSignature ? "Added" : "Set Up")
            }
        } header: {
            ProfileSectionHeader("You")
        }
    }

    private var organizationSection: some View {
        Section {
            NavigationLink { OrganizationDetailsView() } label: {
                SettingsRowLabel(title: "Organization", systemImage: "briefcase.fill",
                                 color: ProfilePalette.teal, value: workspace)
            }
            NavigationLink { LetterheadAndLogoView() } label: {
                SettingsRowLabel(title: "Letterhead and Logo", systemImage: "doc.text.fill",
                                 color: ProfilePalette.indigo,
                                 value: studio.letterheads.isEmpty ? "Add" : "Added")
            }
            SettingsMenuRow(title: "MoM Format", systemImage: "list.bullet",
                            color: ProfilePalette.orange, value: minutesFormatTitle) {
                Picker("MoM Format", selection: $minutesFormatRaw) {
                    Text("Automatic").tag("")
                    ForEach(MinutesFormat.allCases) { format in
                        Text(format.title).tag(format.rawValue)
                    }
                }
            }
            NavigationLink { MinutesLanguageView() } label: {
                SettingsRowLabel(title: "Minutes Language", systemImage: "globe",
                                 color: ProfilePalette.blue,
                                 value: (MinutesLanguage(rawValue: minutesLanguage) ?? .english).title)
            }
            NavigationLink { MinutesStudioSettingsView() } label: {
                SettingsRowLabel(title: "Minutes Studio", systemImage: "doc.richtext.fill",
                                 color: ProfilePalette.pink)
            }
        } header: {
            ProfileSectionHeader("Organization and Minutes")
        }
    }

    private var minutesFormatTitle: String {
        MinutesFormat(rawValue: minutesFormatRaw)?.title ?? "Automatic"
    }

    private var recordingSection: some View {
        Section {
            NavigationLink { LocalRecordingsView() } label: {
                SettingsRowLabel(title: "Recordings on This iPhone", systemImage: "waveform",
                                 color: ProfilePalette.accent, value: recordingsSizeText)
            }
            SettingsMenuRow(title: "Audio Quality", systemImage: "speaker.wave.2.fill",
                            color: ProfilePalette.pink,
                            value: viewModel.audioQuality == .high ? "High" : "Standard") {
                Picker("Audio Quality", selection: Binding(
                    get: { viewModel.audioQuality },
                    set: { viewModel.setAudioQuality($0) }
                )) {
                    Text("High (128 kbps)").tag(AudioQuality.high)
                    Text("Standard (64 kbps)").tag(AudioQuality.standard)
                }
                Toggle("Background Noise Suppression", isOn: Binding(
                    get: { viewModel.isNoiseSuppressionEnabled },
                    set: { viewModel.isNoiseSuppressionEnabled = $0 }
                ))
            }
            .disabled(viewModel.isAudioSettingsLocked)
            NavigationLink { TestMicrophoneView() } label: {
                SettingsRowLabel(title: "Test Microphone", systemImage: "mic.fill",
                                 color: ProfilePalette.red)
            }
        } header: {
            ProfileSectionHeader("Recording")
        }
    }

    private var vidurSection: some View {
        Section {
            NavigationLink { VidurSettingsView() } label: {
                SettingsRowLabel(title: "Vidur", systemImage: "sparkles",
                                 color: ProfilePalette.accent, value: "On this iPhone")
            }
        } header: {
            ProfileSectionHeader("Vidur and Speakers")
        }
    }

    private var connectionsSection: some View {
        Section {
            NavigationLink { AppleCalendarAccessView() } label: {
                SettingsRowLabel(title: "Apple Calendar", systemImage: "calendar",
                                 color: ProfilePalette.red, value: calendarAccess)
            }
            NavigationLink { ContactsDirectoryView() } label: {
                SettingsRowLabel(title: "Contacts", systemImage: "person.fill",
                                 color: ProfilePalette.gray,
                                 value: ContactsDirectory.people(from: speakers, query: "").count.formatted())
            }
            NavigationLink { NotificationsInboxView() } label: {
                SettingsRowLabel(title: "Notifications", systemImage: "bell.fill",
                                 color: ProfilePalette.red, value: notificationsStatus)
            }
        } header: {
            ProfileSectionHeader("Connections")
        }
    }

    private var privacySection: some View {
        Section {
            NavigationLink { ExportAllMinutesView() } label: {
                SettingsRowLabel(title: "Export All Minutes", systemImage: "square.and.arrow.up",
                                 color: ProfilePalette.blue)
            }
            Button(role: .destructive) {
                showsEraseAlert = true
            } label: {
                HStack(spacing: 12) {
                    SettingsIconTile(systemImage: "trash.fill", color: ProfilePalette.red)
                    Text("Delete All Data").font(.body).foregroundStyle(ProfilePalette.red)
                    Spacer()
                }
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + 42 }
            }
            .disabled(isErasing)
        } header: {
            ProfileSectionHeader("Privacy and Data")
        }
    }

    /// App and system destinations remain reachable after the H1 sections.
    private var appSection: some View {
        Section {
            NavigationLink {
                Form { SettingsThemeAndAppearanceSection(viewModel: viewModel) }
                    .navigationTitle("Appearance")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                SettingsRowLabel(title: "Appearance", systemImage: "circle.lefthalf.filled",
                                 color: ProfilePalette.indigo)
            }
            NavigationLink { OfflineAnalysisModelsView() } label: {
                SettingsRowLabel(title: "Offline Models", systemImage: "cpu",
                                 color: ProfilePalette.accent)
            }
            NavigationLink {
                Form { SettingsStorageAndCacheSection(viewModel: viewModel) }
                    .navigationTitle("Storage")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                SettingsRowLabel(title: "Storage", systemImage: "internaldrive.fill",
                                 color: ProfilePalette.gray)
            }
            NavigationLink { AboutAndLicensesView() } label: {
                SettingsRowLabel(title: "About", systemImage: "info.circle.fill",
                                 color: ProfilePalette.gray)
            }
            #if DEBUG
            NavigationLink {
                Form {
                    NavigationLink("Offline model benchmarks") { OfflineBenchmarkView() }
                    SettingsAboutAndDiagnosticsSection(viewModel: viewModel)
                }
                .navigationTitle("Diagnostics")
            } label: {
                SettingsRowLabel(title: "Diagnostics (debug builds only)", systemImage: "wrench.and.screwdriver.fill",
                                 color: ProfilePalette.gray)
            }
            #endif
        } header: {
            ProfileSectionHeader("Manent")
        } footer: {
            Text("Manent \(appVersion) \u{00B7} Recordings and minutes stay on this iPhone.")
                .font(.footnote)
                .foregroundStyle(ProfilePalette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
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
        case .fullAccess: return "Connected"
        case .writeOnly: return "Add Only"
        default: return "Not Connected"
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
/// Organization name and registered details printed on minutes. Same local stores as the
/// Letterhead page; nothing leaves this iPhone.
struct OrganizationDetailsView: View {
    @AppStorage(OrganizationProfileStore.nameKey) private var organizationName = "iOS Center"
    @State private var details = OrganizationProfileStore().load()
    private let detailsStore = OrganizationProfileStore()

    var body: some View {
        Form {
            Section("Organization") {
                TextField("Company Name", text: $organizationName)
                TextField("Registered Address", text: $details.address, axis: .vertical)
            }
            Section("Registration") {
                TextField("CIN", text: $details.cin).textInputAutocapitalization(.characters)
                TextField("GSTIN", text: $details.gstin).textInputAutocapitalization(.characters)
            }
            Section("Contact") {
                TextField("Phone", text: $details.phone).keyboardType(.phonePad)
                TextField("Email", text: $details.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }
        }
        .navigationTitle("Organization")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: details) { _, value in detailsStore.save(value) }
    }
}

/// Keeps the top-bar edit destination and the H5 row on one editor implementation.
struct ProfileEditorView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        NameAndTitleView(viewModel: viewModel, navigationTitle: "Edit Profile")
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
