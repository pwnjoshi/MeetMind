import SwiftUI
import SwiftData
import UIKit

/// Main Meetings home screen matching Figma node 1408:3209
public struct HomeDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(NavigationRouter.self) private var router
    @Environment(SettingsViewModel.self) private var settings
    @Query private var savedMeetings: [Meeting]
    @State public var viewModel: HomeViewModel
    
    @State private var isMicrophoneCheckPresented: Bool = false
    @State private var selectedSeriesID: UUID?
    @State private var showsSeries = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var waveformPhase = 0
    @AppStorage("Manent.dismissedFirstMeetingTip") private var dismissedFirstMeetingTip = false
    
    public init(viewModel: HomeViewModel = HomeViewModel()) { _viewModel = State(initialValue: viewModel) }
    public init(modelContext: ModelContext? = nil) { _viewModel = State(initialValue: HomeViewModel(modelContext: modelContext)) }
    
    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    if savedMeetings.isEmpty || viewModel.isEmptyState {
                        emptyMeetingsState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 150)
                    } else {
                        meetingSection("Upcoming meetings", meetings: viewModel.filteredUpcomingMeetings, upcoming: true)
                        meetingSection("Recent meetings", meetings: viewModel.filteredRecentMeetings, upcoming: false)
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
            }

            if savedMeetings.isEmpty && !dismissedFirstMeetingTip {
                HStack(spacing: 12) {
                    Image(systemName: "mic").foregroundStyle(Theme.Colors.manentAccent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Record Your First Meeting").font(.subheadline.bold())
                        Text("Tap + to record. Manent writes the minutes.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button { dismissedFirstMeetingTip = true } label: {
                        Image(systemName: "xmark").font(.caption)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss recording tip")
                }
                .padding(.leading, 16).padding(.vertical, 12)
                .background(.background, in: RoundedRectangle(cornerRadius: 22))
                .shadow(color: .black.opacity(0.10), radius: 14, y: 8)
                .frame(maxWidth: 300)
                .padding(.trailing, 16).padding(.bottom, 88)
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
                .frame(width: 48, height: 48)
                .background(Theme.Colors.manentAccent)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
            }
            .menuOrder(.fixed)
            .accessibilityLabel("New meeting")
            .accessibilityHint("Choose Quick Meet, Schedule Meet, or Import Audio")
            .padding(.trailing, 28)
            .padding(.bottom, 8)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Meetings")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    profileButton
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    profileButton
                }
            }
        }
        .sheet(isPresented: $showsSeries) {
            if let id = selectedSeriesID {
                NavigationStack { LocalSeriesTimeline(seriesID: id) }
            }
        }
        .sheet(isPresented: $isMicrophoneCheckPresented) {
            MicrophoneCheckView {
                let m = Meeting(title: "Quick meeting", createdAt: Date(), duration: 0, status: .recording)
                viewModel.addMeeting(m)
                router.navigate(to: .liveRecording(id: m.id), in: .home)
            }
        }
        .onAppear { viewModel.setModelContext(modelContext); viewModel.fetchMeetings() }
        .onChange(of: savedMeetingRevision) { _, _ in viewModel.fetchMeetings() }
    }

    private var profileButton: some View {
        Button {
            router.navigate(to: .settings, in: .home)
        } label: {
            profileAvatar
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile and settings")
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let data = settings.userProfile?.avatarImageData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 36, height: 36).clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(uiColor: .systemBackground), Color(uiColor: .systemGray))
                .frame(width: 36, height: 36)
        }
    }

    // Sheet-based creation does not always trigger the underlying view's onAppear.
    // Observe persisted changes so imports, scheduling, and edits refresh the list.
    private var savedMeetingRevision: [String] {
        savedMeetings.map {
            "\($0.id)|\($0.title)|\($0.status.rawValue)|\($0.scheduledStartTime?.timeIntervalSince1970 ?? 0)|\($0.seriesName ?? "")|\($0.seriesID?.uuidString ?? "")"
        }.sorted()
    }
    private var emptyMeetingsState: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(uiColor: .systemBackground).opacity(0.6))
                    .frame(width: 132, height: 92)
                    .rotationEffect(.degrees(-6))
                    .position(x: 112, y: 61)
                HStack(spacing: 6) {
                    ForEach(0..<9) { index in
                        Capsule()
                            .fill(Color(hex: "#4F46E5").opacity(0.35 + Double(index) * 0.08125))
                            .frame(width: 6, height: waveformHeights[waveformPhase][index])
                    }
                }
                .frame(width: 140, height: 96)
                .background(.background, in: RoundedRectangle(cornerRadius: 22))
                .shadow(color: .black.opacity(0.10), radius: 22, y: 8)
                .position(x: 100, y: 82)
                Image("MeetingEmptyBadge")
                    .resizable()
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "mic").font(.system(size: 17)).foregroundStyle(.white)
                    }
                    .position(x: 164, y: 124)
            }
            .frame(width: 200, height: 150)
            .accessibilityHidden(true)
            .task(id: reduceMotion) {
                waveformPhase = 0
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                    withAnimation(.easeInOut(duration: 0.32)) {
                        waveformPhase = (waveformPhase + 1) % waveformHeights.count
                    }
                }
            }
            Text("No Meetings Yet").font(.title3.bold())
            Text("Your recordings and minutes appear here.").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private let waveformHeights: [[CGFloat]] = [
        [10, 22, 34, 18, 40, 26, 14, 30, 12],
        [18, 34, 20, 38, 22, 36, 26, 16, 24],
        [26, 14, 38, 28, 16, 30, 40, 20, 34]
    ]

    @ViewBuilder
    private func meetingSection(_ title: String, meetings: [Meeting], upcoming: Bool) -> some View {
        if !meetings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title3.weight(.semibold)).padding(.horizontal, 16)
                VStack(spacing: 0) {
                    ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                        meetingRow(meeting, upcoming: upcoming)
                        if index < meetings.count - 1 { Divider().padding(.horizontal, 16) }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private func meetingRow(_ meeting: Meeting, upcoming: Bool) -> some View {
        NavigationLink(value: NavigationDestination.meetingDetail(id: meeting.id)) {
            HStack(spacing: 12) {
                MeetingDateTile(date: upcoming ? (meeting.scheduledStartTime ?? meeting.createdAt) : meeting.createdAt)
                VStack(alignment: .leading, spacing: 3) {
                    Text(meeting.title).font(.body).foregroundStyle(.primary)
                    Text(upcoming
                        ? "\((meeting.scheduledStartTime ?? meeting.createdAt).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) \u{00B7} \(seriesSubtitle(meeting))"
                        : recentSubtitle(meeting))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(upcoming
                    ? (meeting.scheduledStartTime ?? meeting.createdAt).formatted(date: .omitted, time: .shortened)
                    : meeting.createdAt.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.body).foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16).padding(.vertical, 11).frame(minHeight: 66)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let id = meeting.seriesID {
                Button("View Series", systemImage: "calendar") {
                    selectedSeriesID = id
                    showsSeries = true
                }
            }
        }
    }

    private func recentSubtitle(_ meeting: Meeting) -> String {
        let open = meeting.actionItems.filter { !$0.isCompleted }.count
        guard meeting.figmaBadgeText == "Finalized", open > 0 else { return meeting.figmaBadgeText }
        return "Finalized \u{00B7} \(open) open \(open == 1 ? "action" : "actions")"
    }

    private func seriesSubtitle(_ meeting: Meeting) -> String {
        guard let id = meeting.seriesID else { return meeting.figmaBadgeText }
        let count = savedMeetings.filter { $0.seriesID == id }.count
        return "Series \u{00B7} \(count) \(count == 1 ? "meeting" : "meetings")"
    }

}

private struct MeetingDateTile: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.red)
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(.primary)
        }
        .frame(width: 40, height: 40)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
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
