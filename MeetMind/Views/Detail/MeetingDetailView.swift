import SwiftUI
import SwiftData
import UIKit
import OfflineEngineKit

/// Canonical meeting record: Minutes / Actions / Decisions, People, sharing and the meeting options menu.
/// Supporting views live in `Views/Detail/Record/`.
@MainActor
public struct MeetingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @Environment(SettingsViewModel.self) private var settings
    @State public var viewModel: MeetingDetailViewModel
    @State private var recordStore = MeetingRecordStore.shared
    @State private var reviewStore = ReviewStateStore.shared

    @State private var showRenameAlert: Bool = false
    @State private var renameText: String = ""
    @State private var showExportSheet: Bool = false
    @State private var startSharing = false
    @State private var showKeepPrivate = false
    @State private var showAskAISheet: Bool = false
    @State private var showPhotoModal: String? = nil
    @State private var showSpeakerReassign: TranscriptSegment? = nil
    @State private var showReprocessConfirmation = false
    @State private var isReprocessing = false
    @State private var minutesDraft: AnalysisCoordinator.MinutesDraft?
    @State private var showDeleteConfirmation = false
    @State private var deletionError: String?
    @State private var showNoteSheet = false
    @State private var showPeople = false
    @State private var showMinutesEditor = false
    @State private var followUpDraft: MeetingSetupViewModel?
    @State private var showFollowUp = false
    @State private var recordSection = "Minutes"
    @State private var transcriptRoute: TranscriptRoute?
    @State private var showsStudio = false
    @State private var showsApproval = false
    @State private var showsSeriesComparison = false
    @State private var showsSharedMinutes = false
    @State private var showsReviewChecklist = false
    @State private var externalShare: MinutesShareRequest?
    @State private var showsPDFPreview = false
    @State private var showClassicEditor = false
    @State private var showKeepDraft = false
    @State private var showDetails = false
    @State private var showsMoM = false
    @State private var showNameSpeakers = false
    @Query(sort: \Meeting.createdAt) private var allMeetings: [Meeting]

    public init(viewModel: MeetingDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private var hasMinutes: Bool { viewModel.summary != nil }

    private var lifecycleResolution: MeetingLifecycleResolution? {
        guard let meeting = viewModel.meeting else { return nil }
        let state = try? reviewStore.record(for: meeting.id)
        return MeetingLifecycleResolver.resolve(meeting: meeting, reviewState: state)
    }

    private var recordStatus: MeetingRecordStatus {
        guard let meeting = viewModel.meeting else { return .draft }
        let record = recordStore.record(for: meeting.id)
        if !record.shares.isEmpty { return .shared(people: Self.sharedPeopleCount(record)) }
        if record.keptPrivate { return .keptPrivate }
        return lifecycleResolution?.state == .finalized ? .finalized : .draft
    }

    private var isShared: Bool {
        guard let id = viewModel.meeting?.id else { return false }
        return !recordStore.record(for: id).shares.isEmpty
    }

    private var isFinalized: Bool { lifecycleResolution?.state == .finalized }

    /// Distinct people the user addressed across every Mail hand-off. Share-sheet hand-offs name no one.
    private static func sharedPeopleCount(_ record: MeetingRecordData) -> Int {
        var keys = Set<String>()
        for entry in record.shares {
            for recipient in entry.recipients { keys.insert((recipient.email ?? recipient.name).lowercased()) }
        }
        return keys.count
    }

    private var keptPrivate: Bool {
        guard let id = viewModel.meeting?.id else { return false }
        return recordStore.record(for: id).keptPrivate
    }

    private var unnamedVoiceCount: Int {
        guard let meeting = viewModel.meeting else { return 0 }
        return MeetingPeopleEditor.voices(in: meeting, record: recordStore.record(for: meeting.id))
            .filter { $0.assignedPersonID == nil }.count
    }
    /// The record page with the navigation destinations and alerts of the meeting-record actions.
    private var recordPage: some View {
        recordContent
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .tint(Theme.Colors.manentAccent)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showsMoM) {
            if let meeting = viewModel.meeting {
                MoMDocumentScreen(
                    meeting: meeting,
                    viewModel: viewModel,
                    isFinalized: isFinalized,
                    userName: settings.userProfile?.name,
                    onRename: {
                        renameText = viewModel.headerTitle
                        showRenameAlert = true
                    },
                    onEdit: { showMinutesEditor = true },
                    onOpenMeeting: { id in router.navigate(to: .meetingDetail(id: id), in: .home) },
                    onScheduleNext: { beginFollowUp(for: meeting) },
                    onOpenStudio: { showsStudio = true }
                )
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
                .navigationTitle("Formal Minutes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Share", systemImage: "square.and.arrow.up") { shareFromFormalMinutes() }
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .alert("Keep Minutes Private?", isPresented: $showKeepPrivate) {
            Button("Cancel", role: .cancel) {}
            Button("Keep Private") { keepMinutesPrivate() }
        } message: {
            Text("The finalized record stays on this iPhone. No minutes or task notifications will be sent.")
        }
        .alert("Continue Without Sharing?", isPresented: $showKeepDraft) {
            Button("Review and Finalize") { showsReviewChecklist = true }
            Button("Keep as Draft") { keepMinutesPrivate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("No minutes or task notifications will be sent. Review and finalize the minutes first, or keep them on this iPhone as a draft.")
        }
        .sheet(isPresented: $showDetails) {
            if let meeting = viewModel.meeting {
                MeetingDetailsSheet(meeting: meeting)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showNameSpeakers) {
            if let meeting = viewModel.meeting {
                NameSpeakersView(meeting: meeting)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    public var body: some View {
        recordPage
        .navigationDestination(isPresented: $showsReviewChecklist) {
            if let meeting = viewModel.meeting { MinutesReviewChecklistView(meeting: meeting) }
        }
        .fullScreenCover(item: $transcriptRoute) { route in
            MeetingTranscriptScreen(meetingId: route.id, focusTime: route.focusTime)
        }
        .sheet(item: $minutesDraft) { draft in
            NavigationStack {
                List {
                    draftSection("Current minutes", overview: draft.currentOverview, decisions: draft.currentDecisions)
                    draftSection("Regenerated draft", overview: draft.overview, decisions: draft.decisions)
                    Section("Draft action suggestions") {
                        if draft.suggestedActions.isEmpty { Text("No suggested actions").foregroundStyle(.secondary) }
                        ForEach(draft.suggestedActions.indices, id: \.self) { index in
                            Text(draft.suggestedActions[index])
                        }
                    }
                }
                .navigationTitle("Compare Minutes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Keep Current") { minutesDraft = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use Draft") { applyMinutesDraft(draft) }
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showsPDFPreview) {
            if let document = momDocument() {
                MoMPDFPreviewView(document: document) { url in
                    startExternalShare(url, text: document.plainText)
                }
            }
        }
        .navigationDestination(isPresented: $showsStudio) {
            if let meeting = viewModel.meeting { MinutesStudioView(meeting: meeting) }
        }
        .navigationDestination(isPresented: $showsApproval) {
            if let meeting = viewModel.meeting { MinutesApprovalView(meeting: meeting) }
        }
        .navigationDestination(isPresented: $showsSeriesComparison) {
            if let meeting = viewModel.meeting, let seriesID = meeting.seriesID {
                SeriesComparisonView(seriesID: seriesID, seriesName: meeting.seriesName ?? meeting.title)
            }
        }
        .navigationDestination(isPresented: $showsSharedMinutes) {
            if let meeting = viewModel.meeting { OpenSharedMinutesView(meetingID: meeting.id) }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Vidur", systemImage: "sparkles") { showAskAISheet = true }
                    .labelStyle(.iconOnly)
            }
            if hasMinutes {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Share", systemImage: "square.and.arrow.up") { requestShare() }
                        .labelStyle(.iconOnly)
                }
            }
            ToolbarItem(placement: .topBarTrailing) { optionsMenu }
        }
        .modifier(MinutesShareFlowModifier(
            meeting: viewModel.meeting,
            viewModel: viewModel,
            userName: settings.userProfile?.name,
            isStarting: $startSharing,
            externalRequest: $externalShare,
            onBackToMeetings: { router.popToRoot(on: .home) },
            onError: { deletionError = $0 },
            formalText: { momDocument()?.plainText ?? viewModel.exportPlainText() },
            formalPDF: {
                guard let document = momDocument() else { throw MinutesShareFormatError.unavailable }
                return try MoMPDFRenderer.writeTemporaryPDF(document: document, letterhead: nil,
                                                            logo: UIImage(named: "ManentLogo"))
            }
        ))
        .sheet(isPresented: $showPeople) {
            if let meeting = viewModel.meeting {
                MeetingPeopleSheet(meeting: meeting, viewModel: viewModel)
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showMinutesEditor) {
            if let meeting = viewModel.meeting, let document = momDocument() {
                MoMEditMinutesSheet(meeting: meeting, document: document) {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        showClassicEditor = true
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showClassicEditor) {
            if let summary = viewModel.summary, let meeting = viewModel.meeting {
                EditSavedMinutesSheet(meeting: meeting, summary: summary)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showFollowUp, onDismiss: { followUpDraft = nil }) {
            if let followUpDraft {
                ScheduleMeetingView(viewModel: followUpDraft)
                    .presentationDragIndicator(.visible)
            }
        }
        .modifier(MeetingDetailSheetsModifier(
            viewModel: viewModel,
            showExportSheet: $showExportSheet,
            showAskAISheet: $showAskAISheet,
            showRenameAlert: $showRenameAlert,
            renameText: $renameText,
            onRenameError: { deletionError = $0.localizedDescription },
            onShareFile: { url in
                showExportSheet = false
                startExternalShare(url, text: viewModel.exportPlainText())
            }
        ))
        .sheet(isPresented: $showNoteSheet) {
            LiveNoteTakingSheet(timestamp: viewModel.currentPlayheadTime) { text in
                if let meeting = viewModel.meeting {
                    meeting.addNote(Note(content: text, timestamp: viewModel.currentPlayheadTime))
                    do { try modelContext.save() } catch { deletionError = error.localizedDescription }
                }
                showNoteSheet = false
            }
        }
        .sheet(item: $showSpeakerReassign) { segment in
            SpeakerReassignSheet(availableSpeakers: viewModel.meeting?.participants ?? [], currentSpeaker: segment.speaker, onSelect: { speaker in
                do { try viewModel.reassignSpeaker(segment: segment, newSpeaker: speaker) }
                catch { deletionError = error.localizedDescription }
                showSpeakerReassign = nil
            }, onDismiss: { showSpeakerReassign = nil })
        }
        .sheet(isPresented: Binding(get: { showPhotoModal != nil }, set: { if !$0 { showPhotoModal = nil } })) {
            if let path = showPhotoModal {
                WhiteboardDetailModal(photoPath: path, onDismiss: { showPhotoModal = nil })
            }
        }
        .task {
            while !Task.isCancelled {
                viewModel.refreshPlaybackPosition()
                do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
            }
        }
        .onDisappear { viewModel.stopPlayback() }
        .modifier(ReprocessMinutesFeedback(
            isReprocessing: isReprocessing,
            showConfirmation: $showReprocessConfirmation,
            onConfirm: reprocessMinutes
        ))
        .alert("Delete meeting?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task { @MainActor in
                    do { try await viewModel.deleteMeeting(); dismiss() }
                    catch { deletionError = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This deletes the meeting, transcript, notes, and action items.") }
        .alert("Unable to complete action", isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
            Button("OK") { deletionError = nil }
        } message: { Text(deletionError ?? "") }
    }


    // MARK: - Meeting options

    /// The More menu: details, transcript, edit, formal minutes, then delete.
    private var optionsMenu: some View {
        Menu {
            Button("Meeting Details", systemImage: "info.circle") { showDetails = true }
            Button("Show Transcript", systemImage: "doc.text") { openTranscript() }
            if viewModel.meeting?.status == .completed {
                Button("Reprocess Minutes", systemImage: "arrow.clockwise") { showReprocessConfirmation = true }
                    .disabled(!viewModel.transcriptSegments.contains {
                        !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    })
            }
            if hasMinutes {
                Button("Edit Minutes", systemImage: "pencil") { showClassicEditor = true }
                Button("Formal Minutes (MoM)", systemImage: "doc.richtext") { showsMoM = true }
                if !isFinalized {
                    Button("Review and Finalize", systemImage: "checkmark.seal") { showsReviewChecklist = true }
                }
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Change Format", systemImage: "list.bullet") { showsStudio = true }
                    Button("Preview PDF", systemImage: "doc.richtext") { showsPDFPreview = true }
                    Button("Export Minutes", systemImage: "square.and.arrow.up.on.square") { showExportSheet = true }
                    Button("Submit for Approval", systemImage: "person.badge.shield.checkmark") { showsApproval = true }
                    if viewModel.meeting?.seriesID != nil {
                        Button("Compare Series", systemImage: "chart.line.uptrend.xyaxis") { showsSeriesComparison = true }
                    }
                    if isShared {
                        Button("Shared Minutes", systemImage: "paperplane") { showsSharedMinutes = true }
                    }
                }
            }
            Divider()
            Button("Delete Meeting", systemImage: "trash", role: .destructive) { showDeleteConfirmation = true }
        } label: {
            Label("More", systemImage: "ellipsis").labelStyle(.iconOnly)
        }
        .accessibilityLabel("More")
    }

    private struct TranscriptRoute: Identifiable {
        let id: UUID
        let focusTime: Double?
    }

    private func openTranscript() { openTranscript(at: nil) }

    private func openTranscript(at focusTime: Double?) {
        guard let id = viewModel.meeting?.id else { return }
        viewModel.stopPlayback()
        transcriptRoute = TranscriptRoute(id: id, focusTime: focusTime)
    }

    private func reprocessMinutes() {
        guard !isReprocessing, let id = viewModel.meeting?.id else { return }
        isReprocessing = true
        Task { @MainActor in
            defer { isReprocessing = false }
            do {
                minutesDraft = try await AnalysisCoordinator(context: modelContext)
                    .prepareMinutesDraft(meetingID: id, model: VidurModel.selected)
            } catch {
                deletionError = error.localizedDescription
            }
        }
    }

    private func draftSection(_ title: String, overview: String, decisions: [String]) -> some View {
        Section(title) {
            Text(overview.isEmpty ? "No overview" : overview)
            Text("Decisions").font(.subheadline.weight(.semibold))
            if decisions.isEmpty { Text("No decisions").foregroundStyle(.secondary) }
            ForEach(decisions.indices, id: \.self) { index in Text(decisions[index]) }
        }
    }

    private func applyMinutesDraft(_ draft: AnalysisCoordinator.MinutesDraft) {
        do {
            try AnalysisCoordinator(context: modelContext).applyMinutesDraft(draft)
            minutesDraft = nil
        } catch {
            minutesDraft = nil
            deletionError = error.localizedDescription
        }
    }

    /// Every Share entry point (footer, toolbar, PDF preview, Export) opens the recipients sheet over the meeting record.
    private func requestShare() {
        startSharing = true
    }

    /// Share from the formal minutes page: go back to the record first so the sheet opens over it.
    private func shareFromFormalMinutes() {
        showsMoM = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            startSharing = true
        }
    }

    private func startExternalShare(_ url: URL, text: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            externalShare = MinutesShareRequest(fileURL: url, text: text)
        }
    }

    private func momDocument() -> MoMDocumentModel? {
        guard let meeting = viewModel.meeting else { return nil }
        return MoMDocumentBuilder.current(meeting: meeting, allMeetings: allMeetings,
                                          userName: settings.userProfile?.name,
                                          isFinalized: isFinalized)
    }

    private func beginFollowUp(for meeting: Meeting) {
        followUpDraft = MinutesFollowUpDraft.make(from: meeting, modelContext: modelContext)
        showFollowUp = true
    }

    private func keepMinutesPrivate() {
        guard let meeting = viewModel.meeting else { return }
        do {
            try recordStore.update(meeting.id) {
                $0.keptPrivate = true
                $0.keptPrivateAt = Date()
            }
            dismiss()
        } catch {
            deletionError = error.localizedDescription
        }
    }

    // MARK: - Content

    /// Pinned footer: Share Minutes and Continue Without Sharing, or the delivery row once shared.
    @ViewBuilder
    private var bottomBar: some View {
        if viewModel.meeting != nil, hasMinutes {
            VStack(spacing: 6) {
                if isShared, let id = viewModel.meeting?.id {
                    let record = recordStore.record(for: id)
                    let people = Self.sharedPeopleCount(record)
                    Button { showsSharedMinutes = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.24))
                                .accessibilityHidden(true)
                            Text(people == 0 ? "Minutes shared" : (people == 1 ? "Shared with 1 person" : "Shared with \(people) people"))
                                .foregroundStyle(.primary)
                            Text("\u{00B7}").foregroundStyle(.secondary)
                            Text("View delivery").foregroundStyle(Theme.Colors.manentAccent)
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(people == 0 ? "Minutes shared. View delivery" : "Shared with \(people). View delivery")
                } else {
                    Button { requestShare() } label: {
                        Text("Share Minutes").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(.white)
                            .background(Theme.Colors.manentAccent, in: Capsule())
                    }
                    if !keptPrivate {
                        Button("Continue Without Sharing") {
                            if isFinalized { showKeepPrivate = true } else { showKeepDraft = true }
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.manentAccent)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .background(.regularMaterial)
        }
    }

    private var recordContent: some View {
        let content = viewModel.minutesContent
        let suggestionCount = content?.suggestions.count ?? 0
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MeetingRecordHeader(
                    viewModel: viewModel,
                    section: $recordSection,
                    status: recordStatus,
                    pendingReviewCount: recordSection == "Actions" ? 0 : suggestionCount,
                    actionCount: (content?.actions.count ?? 0) + suggestionCount,
                    decisionCount: content?.decisions.count ?? 0,
                    unnamedVoiceCount: unnamedVoiceCount,
                    onRename: {
                        renameText = viewModel.headerTitle
                        showRenameAlert = true
                    },
                    onOpenPeople: { showPeople = true },
                    onNameVoices: { showNameSpeakers = true },
                    onReview: { recordSection = "Actions" },
                    onError: { deletionError = $0 }
                )
                if recordSection == "Minutes", let meeting = viewModel.meeting,
                   viewModel.summary == nil, meeting.resolvedAudioFileURL != nil || !meeting.transcriptSegments.isEmpty {
                    Button { openTranscript() } label: {
                        HStack {
                            Text("Transcript and audio").font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .recordCard()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                if let meeting = viewModel.meeting, meeting.status == .scheduled {
                    Button("Start recording") {
                        meeting.status = .recording
                        do {
                            try modelContext.save()
                            router.navigate(to: .liveRecording(id: meeting.id), in: .home)
                        } catch { deletionError = error.localizedDescription }
                    }
                    .buttonStyle(.borderedProminent).padding(.vertical, 8).padding(.horizontal, 16)
                }

                switch recordSection {
                case "Decisions":
                    MeetingDecisionsList(viewModel: viewModel)
                case "Actions":
                    MeetingActionsList(viewModel: viewModel, onSyncReminders: {
                        Task {
                            do { try await viewModel.syncReviewedTasksToReminders() }
                            catch { deletionError = error.localizedDescription }
                        }
                    })
                default:
                    if let meeting = viewModel.meeting {
                        MeetingMinutesView(meeting: meeting, viewModel: viewModel,
                                           onOpenPeople: { showPeople = true }, onOpenTranscript: { openTranscript(at: $0) })
                    }
                }
            }
        }
        .recordErrorAlert("Could Not Update Record", message: mutationErrorBinding)
    }

    private var mutationErrorBinding: Binding<String?> {
        Binding(
            get: { viewModel.mutationError },
            set: { viewModel.mutationError = $0 }
        )
    }
}

@MainActor
private struct ReprocessMinutesFeedback: ViewModifier {
    let isReprocessing: Bool
    @Binding var showConfirmation: Bool
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content
            .disabled(isReprocessing)
            .navigationBarBackButtonHidden(isReprocessing)
            .overlay {
                if isReprocessing {
                    ProgressView("Reprocessing minutes…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert("Reprocess minutes?", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reprocess", action: onConfirm)
            } message: {
                Text("MeetMind will generate a draft from the current transcript. You can compare it with your saved minutes before choosing which version to keep.")
            }
    }
}
