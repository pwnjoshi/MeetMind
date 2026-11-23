import SwiftUI
import SwiftData
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

    @State private var transcriptSearch: String = ""
    @State private var showRenameAlert: Bool = false
    @State private var renameText: String = ""
    @State private var showExportSheet: Bool = false
    @State private var startSharing = false
    @State private var showKeepPrivate = false
    @State private var showAskAISheet: Bool = false
    @State private var showPhotoModal: String? = nil
    @State private var showSpeakerReassign: TranscriptSegment? = nil
    @State private var showDeleteConfirmation = false
    @State private var deletionError: String?
    @State private var showNoteSheet = false
    @State private var showTaskReview = false
    @State private var showAnalysisEvidence = false
    @State private var showPeople = false
    @State private var showMinutesEditor = false
    @State private var followUpDraft: MeetingSetupViewModel?
    @State private var showFollowUp = false
    @State private var recordSection = "Minutes"
    @State private var showsTranscriptPage = false
    @State private var showsMediaPage = false
    @State private var showsStudio = false
    @State private var showsApproval = false
    @State private var showsSeriesComparison = false
    @State private var showsSharedMinutes = false
    @State private var showsReviewChecklist = false
    @State private var externalShare: MinutesShareRequest?
    @State private var showsPDFPreview = false
    @State private var showClassicEditor = false
    @State private var showDraftShareAlert = false
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

    private var reviewStatusText: String {
        guard let meeting = viewModel.meeting else { return "Draft" }
        if lifecycleResolution?.state == .finalized { return "Finalized" }
        let state = (try? reviewStore.record(for: meeting.id)) ?? ReviewStateRecord()
        let content = MinutesReviewContentSnapshot.make(from: meeting)
        let checklist = MinutesReviewChecklist.evaluate(
            content: content,
            acknowledgements: state.acknowledgements(validFor: content.fingerprint)
        )
        return checklist.canFinalize ? "Ready to finalize" : "Draft"
    }

    private var keptPrivate: Bool {
        guard let id = viewModel.meeting?.id else { return false }
        return recordStore.record(for: id).keptPrivate
    }

    public var body: some View {
        Group {
            if recordSection == "Minutes", hasMinutes, let meeting = viewModel.meeting {
                MoMDocumentScreen(
                    meeting: meeting,
                    viewModel: viewModel,
                    isFinalized: lifecycleResolution?.state == .finalized,
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
            } else {
                recordContent
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .tint(Theme.Colors.manentAccent)
        .navigationDestination(isPresented: $showsReviewChecklist) {
            if let meeting = viewModel.meeting { MinutesReviewChecklistView(meeting: meeting) }
        }
        .navigationDestination(isPresented: $showsTranscriptPage) {
            if let id = viewModel.meeting?.id { MeetingTranscriptScreen(meetingId: id) }
        }
        .navigationDestination(isPresented: $showsMediaPage) {
            MeetingNotesMediaTabView(notes: viewModel.notes,
                                     onAddNote: { showNoteSheet = true },
                                     onSelectPhoto: { showPhotoModal = $0 })
                .navigationTitle("Notes & Media")
                .toolbar(.hidden, for: .tabBar)
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
            ToolbarItem(placement: .topBarTrailing) {
                Button("Transcript", systemImage: "doc.text") { showsTranscriptPage = true }
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
            shareText: { momDocument()?.plainText ?? viewModel.exportPlainText() }
        ))
        .alert("Share Draft Minutes?", isPresented: $showDraftShareAlert) {
            Button("Review First") { showsReviewChecklist = true }
            Button("Share Draft") { startSharing = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These minutes are still a draft. Review and finalize them first, or share the draft as it is.")
        }
        .alert("Keep Minutes Private?", isPresented: $showKeepPrivate) {
            Button("Cancel", role: .cancel) {}
            Button("Keep Private") { keepMinutesPrivate() }
        } message: {
            Text("The finalized record stays on this iPhone. No minutes or task notifications will be sent.")
        }
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
        .sheet(isPresented: $showTaskReview) {
            if let meeting = viewModel.meeting { MeetingTaskReviewView(meeting: meeting) }
        }
        .sheet(isPresented: $showAnalysisEvidence) {
            if let result = viewModel.meeting?.offlineAnalysis { MeetingAnalysisEvidenceView(result: result) }
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

    private var optionsMenu: some View {
        Menu {
            if hasMinutes {
                Button("Edit Minutes", systemImage: "square.and.pencil") { showMinutesEditor = true }
                Button("Change Format", systemImage: "list.bullet") { showsStudio = true }
            }
            Button("Show Transcript", systemImage: "doc.text") { showsTranscriptPage = true }
            if let meeting = viewModel.meeting, meeting.status == .completed {
                Button("Schedule Follow-Up", systemImage: "calendar.badge.plus") { beginFollowUp(for: meeting) }
            }
            if hasMinutes {
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Preview PDF", systemImage: "doc.richtext") { showsPDFPreview = true }
                    Button("Export Minutes", systemImage: "square.and.arrow.up.on.square") { showExportSheet = true }
                    Button("Actions List", systemImage: "checklist") { recordSection = "Actions" }
                    Button("Decisions List", systemImage: "checkmark.seal") { recordSection = "Decisions" }
                    Button("Submit for Approval", systemImage: "person.badge.shield.checkmark") { showsApproval = true }
                    if viewModel.meeting?.seriesID != nil {
                        Button("Compare Series", systemImage: "chart.line.uptrend.xyaxis") { showsSeriesComparison = true }
                    }
                    if let meeting = viewModel.meeting, !recordStore.record(for: meeting.id).shares.isEmpty {
                        Button("Shared Minutes", systemImage: "paperplane") { showsSharedMinutes = true }
                    }
                }
            }
            Divider()
            Button("Delete Meeting", systemImage: "trash", role: .destructive) { showDeleteConfirmation = true }
        } label: {
            Label("Meeting options", systemImage: "ellipsis").labelStyle(.iconOnly)
        }
    }

    private var shareMenu: some View {
        Menu {
            Button("Share Minutes", systemImage: "square.and.arrow.up") { requestShare() }
            Button("Preview PDF", systemImage: "doc.richtext") { showsPDFPreview = true }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up").labelStyle(.iconOnly)
        }
    }

    /// Every Share entry point (bottom button, toolbar, PDF preview, Export) ends in the share flow.
    private func requestShare() {
        if lifecycleResolution?.state == .finalized {
            startSharing = true
        } else {
            showDraftShareAlert = true
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
                                          isFinalized: lifecycleResolution?.state == .finalized)
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

    @ViewBuilder
    private var bottomBar: some View {
        if recordSection == "Minutes", viewModel.meeting != nil, hasMinutes {
            VStack(spacing: 6) {
                Button { requestShare() } label: {
                    Text("Share Minutes").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(.white)
                        .background(Theme.Colors.manentAccent, in: Capsule())
                }
                if lifecycleResolution?.state != .finalized {
                    Button("Review and Finalize") { showsReviewChecklist = true }
                        .frame(minHeight: 44)
                } else {
                    Button("Continue Without Sharing") { showKeepPrivate = true }
                        .frame(minHeight: 44)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.manentAccent)
            .padding(.horizontal, 16)
            .background(.regularMaterial)
        }
    }
    private var recordContent: some View {
        VStack(spacing: 0) {
            MeetingRecordHeader(
                viewModel: viewModel,
                section: $recordSection,
                keptPrivate: keptPrivate,
                reviewStatus: reviewStatusText,
                onRename: {
                    renameText = viewModel.headerTitle
                    showRenameAlert = true
                },
                onOpenPeople: { showPeople = true },
                onError: { deletionError = $0 }
            )
            if recordSection == "Minutes", let meeting = viewModel.meeting,
               viewModel.summary == nil, meeting.resolvedAudioFileURL != nil || !meeting.transcriptSegments.isEmpty {
                Button { showsTranscriptPage = true } label: {
                    HStack {
                        Text("Transcript and audio").font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            if let meeting = viewModel.meeting, !meeting.pendingTaskSuggestions.isEmpty {
                Button("Review \(meeting.pendingTaskSuggestions.count) suggested tasks") { showTaskReview = true }
                    .buttonStyle(.borderedProminent).padding(.vertical, 8)
            }
            if let meeting = viewModel.meeting, meeting.status == .scheduled {
                Button("Start recording") {
                    meeting.status = .recording
                    do {
                        try modelContext.save()
                        router.navigate(to: .liveRecording(id: meeting.id), in: .home)
                    } catch { deletionError = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent).padding(.vertical, 8)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                if let meeting = viewModel.meeting, hasMinutes {
                    MeetingMinutesView(meeting: meeting, onOpenPeople: { showPeople = true })
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
