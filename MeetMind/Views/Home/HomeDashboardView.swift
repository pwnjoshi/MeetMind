import SwiftUI
import SwiftData

/// Main Meetings home screen matching Figma node 1408:3209
public struct HomeDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(NavigationRouter.self) private var router
    @Query private var savedMeetings: [Meeting]
    @State public var viewModel: HomeViewModel
    
    @State private var isShowingSettings: Bool = false
    @State private var isMicrophoneCheckPresented: Bool = false
    @State private var selectedSeriesID: UUID?
    @State private var showsSeries = false
    
    public init(viewModel: HomeViewModel = HomeViewModel()) { _viewModel = State(initialValue: viewModel) }
    public init(modelContext: ModelContext? = nil) { _viewModel = State(initialValue: HomeViewModel(modelContext: modelContext)) }
    
    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            List {
                Section("Upcoming meetings") {
                    if viewModel.filteredUpcomingMeetings.isEmpty {
                        Text("No upcoming meetings scheduled").foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.filteredUpcomingMeetings) { meeting in
                        meetingRow(meeting, upcoming: true)
                    }
                }
                Section("Recent meetings") {
                    if viewModel.filteredRecentMeetings.isEmpty {
                        Text("No recent meetings").foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.filteredRecentMeetings) { meeting in
                        meetingRow(meeting, upcoming: false)
                    }
                }
                Section { Color.clear.frame(height: 56).listRowBackground(Color.clear) }
            }
            .listStyle(.insetGrouped)
            .headerProminence(.increased)
            .overlay {
                if viewModel.isEmptyState {
                    ContentUnavailableView("No Meetings Yet", systemImage: "mic",
                        description: Text("Tap + to record your first meeting."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(uiColor: .systemGroupedBackground))
                }
            }

            // Bottom Action FAB
            Menu {
                Button("Quick Meet", systemImage: "mic.fill") { isMicrophoneCheckPresented = true }
                Button("Schedule Meet", systemImage: "calendar.badge.plus") { appState.activeSheet = .scheduleMeeting }
                Button("Import Audio", systemImage: "square.and.arrow.down") { appState.activeSheet = .audioImport }
            } label: {
                Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color(hex: "#0088FF"))
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)
            }
            .menuOrder(.fixed)
            .accessibilityLabel("New meeting")
            .accessibilityHint("Choose Quick Meet, Schedule Meet, or Import Audio")
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Meetings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { isShowingSettings = true }) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 28))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Profile and settings")
            }
        }
        .sheet(isPresented: $isShowingSettings) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $showsSeries) {
            if let id = selectedSeriesID {
                NavigationStack { LocalSeriesTimeline(seriesID: id) }
            }
        }
        .sheet(isPresented: $isMicrophoneCheckPresented) {
            MicrophoneCheckView {
                let m = Meeting(title: "New Meeting \(Date().formatted(date: .omitted, time: .shortened))", createdAt: Date(), duration: 0, status: .recording)
                viewModel.addMeeting(m)
                router.navigate(to: .liveRecording(id: m.id), in: .home)
            }
        }
        .onAppear { viewModel.setModelContext(modelContext); viewModel.fetchMeetings() }
        .onChange(of: savedMeetingRevision) { _, _ in viewModel.fetchMeetings() }
    }

    // Sheet-based creation does not always trigger the underlying view's onAppear.
    // Observe persisted changes so imports, scheduling, and edits refresh the list.
    private var savedMeetingRevision: [String] {
        savedMeetings.map {
            "\($0.id)|\($0.title)|\($0.status.rawValue)|\($0.scheduledStartTime?.timeIntervalSince1970 ?? 0)|\($0.seriesName ?? "")|\($0.seriesID?.uuidString ?? "")"
        }.sorted()
    }
    private func meetingRow(_ meeting: Meeting, upcoming: Bool) -> some View {
        NavigationLink(value: NavigationDestination.meetingDetail(id: meeting.id)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(meeting.title).font(.body).foregroundStyle(.primary)
                    Text(upcoming
                        ? "\((meeting.scheduledStartTime ?? meeting.createdAt).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) \u{00B7} \(seriesSubtitle(meeting))"
                        : meeting.figmaBadgeText)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(upcoming
                    ? (meeting.scheduledStartTime ?? meeting.createdAt).formatted(date: .omitted, time: .shortened)
                    : meeting.createdAt.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.body).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
        }
        .contextMenu {
            if let id = meeting.seriesID {
                Button("View Series", systemImage: "calendar") {
                    selectedSeriesID = id
                    showsSeries = true
                }
            }
        }
    }

    private func seriesSubtitle(_ meeting: Meeting) -> String {
        guard let id = meeting.seriesID else { return meeting.figmaBadgeText }
        let count = savedMeetings.filter { $0.seriesID == id }.count
        return "Series \u{00B7} \(count) \(count == 1 ? "meeting" : "meetings")"
    }

}

private struct LocalSeriesTimeline: View {
    let seriesID: UUID
    @Query private var meetings: [Meeting]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var setup: MeetingSetupViewModel?
    @State private var showsSchedule = false
    @State private var showsRename = false
    @State private var nameDraft = ""
    @State private var saveError: String?

    private var occurrences: [Meeting] {
        meetings.filter { $0.seriesID == seriesID }.sorted {
            ($0.scheduledStartTime ?? $0.createdAt) < ($1.scheduledStartTime ?? $1.createdAt)
        }
    }

    var body: some View {
        List {
            Section("Upcoming") {
                if occurrences.allSatisfy({ $0.status != .scheduled }) {
                    Text("No upcoming meetings").foregroundStyle(.secondary)
                }
                ForEach(occurrences.filter { $0.status == .scheduled }) { row($0) }
            }
            Section("Past meetings") {
                if occurrences.allSatisfy({ $0.status == .scheduled }) {
                    Text("No past meetings").foregroundStyle(.secondary)
                }
                ForEach(occurrences.filter { $0.status != .scheduled }.reversed()) { row($0) }
            }
        }
        .listStyle(.insetGrouped)
        .headerProminence(.increased)
        .navigationTitle(occurrences.first?.seriesName ?? "Meeting Series")
        .safeAreaInset(edge: .bottom) {
            Button {
                let model = MeetingSetupViewModel(modelContext: modelContext)
                model.scheduledSeriesID = seriesID
                model.scheduledSeriesName = occurrences.first?.seriesName
                model.title = occurrences.first?.seriesName ?? ""
                setup = model
                showsSchedule = true
            } label: {
                Text("Add Meeting").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .sheet(isPresented: $showsSchedule) {
            if let setup { ScheduleMeetingView(viewModel: setup) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename Series") {
                        nameDraft = occurrences.first?.seriesName ?? ""
                        showsRename = true
                    }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("Series options")
            }
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .alert("Rename Series", isPresented: $showsRename) {
            TextField("Series name", text: $nameDraft)
            Button("Cancel", role: .cancel) { }
            Button("Save") { renameSeries() }
                .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Could Not Save Series", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private func renameSeries() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let previous = occurrences.map { ($0, $0.seriesName) }
        for meeting in occurrences { meeting.seriesName = name }
        do { try modelContext.save() }
        catch {
            for (meeting, oldName) in previous { meeting.seriesName = oldName }
            saveError = "The series name could not be saved. Try again."
        }
    }

    private func row(_ meeting: Meeting) -> some View {
        NavigationLink {
            MeetingDetailContainerView(meetingId: meeting.id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title).foregroundStyle(.primary)
                    Text(meeting.status == .scheduled
                        ? "\((meeting.scheduledStartTime ?? meeting.createdAt).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) \u{00B7} Scheduled"
                        : meeting.figmaBadgeText)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(meeting.status == .scheduled
                    ? (meeting.scheduledStartTime ?? meeting.createdAt).formatted(date: .omitted, time: .shortened)
                    : meeting.createdAt.formatted(.dateTime.day().month(.abbreviated)))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
        }
    }
}
