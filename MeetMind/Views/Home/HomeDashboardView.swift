import SwiftUI
import SwiftData
import UIKit

/// Main Meetings home screen matching Figma node 1408:3209
@MainActor
public struct HomeDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(NavigationRouter.self) private var router
    @Environment(SettingsViewModel.self) private var settings
    @Query private var savedMeetings: [Meeting]
    @State public var viewModel: HomeViewModel
    @State private var reviewStore = ReviewStateStore.shared
    
    @State private var isMicrophoneCheckPresented: Bool = false
    @State private var selectedSeriesID: UUID?
    @State private var showsSeries = false
    @State private var showsAllUpcoming = false
    @State private var showsAllRecent = false
    @State private var showsVidur = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var waveformPhase = 0
    @AppStorage("Manent.dismissedFirstMeetingTip") private var dismissedFirstMeetingTip = false
    
    public init(viewModel: HomeViewModel = HomeViewModel()) { _viewModel = State(initialValue: viewModel) }
    public init(modelContext: ModelContext? = nil) { _viewModel = State(initialValue: HomeViewModel(modelContext: modelContext)) }
    
    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    homeHeader

                    if let loadingError = viewModel.loadingErrorMessage {
                        ContentUnavailableView {
                            Label("Meetings Unavailable", systemImage: "calendar.badge.exclamationmark")
                        } description: {
                            Text(loadingError)
                        } actions: {
                            Button("Try Again") { viewModel.fetchMeetings() }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 70)
                    } else if savedMeetings.isEmpty || viewModel.isEmptyState {
                        emptyMeetingsState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 70)
                    } else {
                        populatedHome
                    }
                    Color.clear.frame(height: 88)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            if savedMeetings.isEmpty && !dismissedFirstMeetingTip {
                firstMeetingTip
            }

            createMeetingMenu
                .padding(.trailing, 22)
                .padding(.bottom, 10)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsSeries) {
            if let id = selectedSeriesID {
                NavigationStack { LocalSeriesTimeline(seriesID: id) }
            }
        }
        .sheet(isPresented: $showsAllUpcoming) {
            NavigationStack {
                HomeMeetingCollectionView(
                    title: "Upcoming Meetings",
                    meetings: viewModel.filteredUpcomingMeetings,
                    recentSubtitle: recentSubtitle
                )
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsAllUpcoming = false } } }
            }
        }
        .sheet(isPresented: $showsAllRecent) {
            NavigationStack {
                HomeMeetingCollectionView(
                    title: "Recent Meetings",
                    meetings: viewModel.filteredRecentMeetings,
                    recentSubtitle: recentSubtitle
                )
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsAllRecent = false } } }
            }
        }
        .sheet(isPresented: $showsVidur) {
            if let meeting = vidurMeeting {
                NavigationStack {
                    RootAskAISheet(meetingId: meeting.id, modelContext: modelContext) { showsVidur = false }
                }
            }
        }
        .sheet(isPresented: $isMicrophoneCheckPresented) {
            MicrophoneCheckView {
                let meeting = Meeting(title: "Quick meeting", createdAt: Date(), duration: 0, status: .recording)
                viewModel.addMeeting(meeting)
                router.navigate(to: .liveRecording(id: meeting.id), in: .home)
            }
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
            viewModel.fetchMeetings()
        }
        .onChange(of: savedMeetingRevision) { _, _ in viewModel.fetchMeetings() }
    }

    private var homeHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Meetings")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.8)
            Spacer()
            Button { showsVidur = true } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Theme.Colors.manentAccent)
                    .frame(width: 50, height: 50)
                    .background(.background, in: Circle())
                    .overlay(Circle().stroke(Color(uiColor: .separator).opacity(0.6)))
            }
            .buttonStyle(.plain)
            .disabled(vidurMeeting == nil)
            .accessibilityLabel("Ask Vidur")
            .accessibilityHint(vidurMeeting == nil ? "Available after a meeting has been saved" : "Ask about your latest meeting")
            profileButton
        }
    }

    @ViewBuilder
    private var populatedHome: some View {
        let upcoming = viewModel.filteredUpcomingMeetings
        let featured = upcoming.first
        let week = thisWeekMeetings(from: upcoming, excluding: featured?.id)
        let recent = Array(viewModel.filteredRecentMeetings.prefix(4))

        if let featured {
            UpNextMeetingCard(
                meeting: featured,
                recurrenceText: seriesSubtitle(featured),
                referenceDate: Date()
            ) { openMeeting(featured) }
        }

        if !week.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: "This Week", showsSeeAll: true) {
                    showsAllUpcoming = true
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(week) { meeting in
                            WeekMeetingCard(meeting: meeting) { openMeeting(meeting) }
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .contentMargins(.horizontal, 0, for: .scrollContent)
            }
        }

        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(
                    title: "Recent",
                    showsSeeAll: true
                ) { showsAllRecent = true }
                RecentMeetingsCard(
                    meetings: recent,
                    subtitle: recentSubtitle,
                    statusColor: recentStatusColor,
                    open: openMeeting
                )
            }
        }
    }

    private var firstMeetingTip: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic").foregroundStyle(Theme.Colors.manentAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Record Your First Meeting").font(.subheadline.bold())
                Text("Tap + to record. Manent writes the minutes.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Button { dismissedFirstMeetingTip = true } label: {
                Image(systemName: "xmark").font(.caption).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss recording tip")
        }
        .padding(.leading, 16).padding(.vertical, 12)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.10), radius: 14, y: 8)
        .frame(maxWidth: 310)
        .padding(.trailing, 16).padding(.bottom, 82)
    }

    private var createMeetingMenu: some View {
        Menu {
            Button("Quick Meet", systemImage: "mic.fill") { isMicrophoneCheckPresented = true }
            Button("Schedule Meet", systemImage: "calendar.badge.plus") { appState.activeSheet = .scheduleMeeting }
            Button("Import Audio", systemImage: "square.and.arrow.down") { appState.activeSheet = .audioImport }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Theme.Colors.manentAccent, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                .shadow(color: Theme.Colors.manentAccent.opacity(0.28), radius: 12, y: 6)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("New meeting")
        .accessibilityHint("Choose Quick Meet, Schedule Meet, or Import Audio")
    }

    private var vidurMeeting: Meeting? {
        viewModel.filteredUpcomingMeetings.first ?? viewModel.filteredRecentMeetings.first
    }

    private func thisWeekMeetings(from meetings: [Meeting], excluding featuredID: UUID?) -> [Meeting] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? Date.distantFuture
        return meetings.filter { meeting in
            guard meeting.id != featuredID else { return false }
            let date = meeting.scheduledStartTime ?? meeting.createdAt
            return date >= start && date < end
        }
    }

    private func openMeeting(_ meeting: Meeting) {
        router.navigate(to: .meetingDetail(id: meeting.id), in: .home)
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
                    if let subtitle = upcoming ? seriesSubtitle(meeting) : recentSubtitle(meeting) {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if upcoming {
                    Text((meeting.scheduledStartTime ?? meeting.createdAt).formatted(date: .omitted, time: .shortened))
                        .font(.body).foregroundStyle(.secondary)
                }
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

    private func recentSubtitle(_ meeting: Meeting) -> String? {
        let review = try? reviewStore.record(for: meeting.id)
        let lifecycleStatus = MeetingLifecycleResolver.reviewDisplayStatus(meeting: meeting, reviewState: review)
        if lifecycleStatus == "Needs speaker review" || meeting.analysisState == "speakerReview" {
            return "Needs speaker review"
        }
        if meeting.analysisState == "failed" { return "Processing needs attention" }
        let open = meeting.actionItems.filter { !$0.isCompleted }.count
        if open > 0 { return "\(open) open \(open == 1 ? "action" : "actions")" }
        guard meeting.duration > 0 else { return lifecycleStatus }
        let minutes = max(1, Int(round(meeting.duration / 60)))
        let duration = "\(minutes) min"
        let date = meeting.scheduledStartTime ?? meeting.createdAt
        if Calendar.current.isDateInYesterday(date) { return "Yesterday · \(duration)" }
        if Calendar.current.isDateInToday(date) { return "Today · \(duration)" }
        return duration
    }

    private func recentStatusColor(_ meeting: Meeting) -> Color {
        if meeting.analysisState == "failed" { return Theme.Colors.coralRed }
        if meeting.analysisState == "speakerReview" { return Theme.Colors.warmAmber }
        return .secondary
    }

    /// Cadence inferred from the dates of the meetings that share a series.
    private func seriesSubtitle(_ meeting: Meeting) -> String? {
        guard let id = meeting.seriesID else { return nil }
        let dates = savedMeetings.filter { $0.seriesID == id }
            .map { $0.scheduledStartTime ?? $0.createdAt }.sorted()
        guard dates.count >= 2 else { return "Series" }
        let gaps = zip(dates, dates.dropFirst()).map { $1.timeIntervalSince($0) / 86_400 }
        let average = gaps.reduce(0, +) / Double(gaps.count)
        switch average {
        case 6...8: return "Repeats weekly"
        case 13...15: return "Repeats every 2 weeks"
        case 27...32: return "Repeats monthly"
        default: return "Series \u{00B7} \(dates.count) meetings"
        }
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

@MainActor
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
    @State private var reviewStore = ReviewStateStore.shared

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
                        : (MeetingLifecycleResolver.reviewDisplayStatus(
                            meeting: meeting,
                            reviewState: try? reviewStore.record(for: meeting.id)
                        ) ?? meeting.figmaBadgeText))
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
