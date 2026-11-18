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
            "\($0.id)|\($0.title)|\($0.status.rawValue)|\($0.scheduledStartTime?.timeIntervalSince1970 ?? 0)"
        }.sorted()
    }
    private func meetingRow(_ meeting: Meeting, upcoming: Bool) -> some View {
        NavigationLink(value: NavigationDestination.meetingDetail(id: meeting.id)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(meeting.title).font(.body).foregroundStyle(.primary)
                    Text(upcoming
                        ? "\((meeting.scheduledStartTime ?? meeting.createdAt).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) \u{00B7} \(meeting.figmaBadgeText)"
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
    }

}
