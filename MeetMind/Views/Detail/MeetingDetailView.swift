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

    @State private var transcriptSearch: String = ""
    @State private var showRenameAlert: Bool = false
    @State private var renameText: String = ""
    @State private var showExportSheet: Bool = false
    @State private var startSharing = false
    @State private var showKeepPrivate = false
    @State private var showAskAISheet: Bool = false
    @State private var showActionItemModal: Bool = false
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

    public init(viewModel: MeetingDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private var hasMinutes: Bool { viewModel.summary != nil }

    private var keptPrivate: Bool {
        guard let id = viewModel.meeting?.id else { return false }
        return recordStore.record(for: id).keptPrivate
    }

    public var body: some View {
        Group {
            if recordSection == "Minutes", hasMinutes {
                ScrollView { recordContent }
            } else {
                recordContent
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .tint(Theme.Colors.manentAccent)
        .navigationDestination(isPresented: $showsTranscriptPage) {
            MeetingTranscriptAudioPage(viewModel: viewModel, searchText: $transcriptSearch) { showSpeakerReassign = $0 }
        }
        .navigationDestination(isPresented: $showsMediaPage) {
            MeetingNotesMediaTabView(notes: viewModel.notes,
                                     onAddNote: { showNoteSheet = true },
                                     onSelectPhoto: { showPhotoModal = $0 })
                .navigationTitle("Notes & Media")
                .toolbar(.hidden, for: .tabBar)
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
            ToolbarItem(placement: .topBarTrailing) { optionsMenu }
        }
        .modifier(MinutesShareFlowModifier(
            meeting: viewModel.meeting,
            viewModel: viewModel,
            userName: settings.userProfile?.name,
            isStarting: $startSharing,
            onBackToMeetings: { dismiss() },
            onError: { deletionError = $0 }
        ))
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
            onRenameError: { deletionError = $0.localizedDescription }
        ))
        .sheet(isPresented: $showActionItemModal) {
            ActionItemEditModal(onSave: { title, priority, dueDate, assignee in
                if let meeting = viewModel.meeting {
                    let action = ActionItem(title: title, assigneeName: assignee, dueDate: dueDate, priority: priority)
                    if action.assignee != nil { action.assignedByLocalUser = true }
                    meeting.addActionItem(action)
                    do { try modelContext.save() } catch { deletionError = error.localizedDescription }
                }
                showActionItemModal = false
            }, onDismiss: { showActionItemModal = false })
        }
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
                do { try viewModel.deleteMeeting(); dismiss() }
                catch { deletionError = error.localizedDescription }
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
            Button("Meeting Details", systemImage: "info.circle") { recordSection = "Minutes" }
            if let meeting = viewModel.meeting, meeting.status == .completed {
                Button("Schedule Follow-Up", systemImage: "calendar") { beginFollowUp(for: meeting) }
            }
            Button("Show Transcript", systemImage: "doc.text") { showsTranscriptPage = true }
            if hasMinutes {
                Button("Edit Minutes", systemImage: "pencil") { showMinutesEditor = true }
                Divider()
                Button("Document Format", systemImage: "doc.richtext") { showsStudio = true }
                Button("Submit for Approval", systemImage: "checkmark.seal") { showsApproval = true }
                if viewModel.meeting?.seriesID != nil {
                    Button("Compare Series", systemImage: "chart.line.uptrend.xyaxis") { showsSeriesComparison = true }
                }
                Button("Export Minutes", systemImage: "square.and.arrow.up") { showExportSheet = true }
                if let meeting = viewModel.meeting, !recordStore.record(for: meeting.id).shares.isEmpty {
                    Button("Shared Minutes", systemImage: "paperplane") { showsSharedMinutes = true }
                }
            }
        } label: {
            Label("Meeting options", systemImage: "ellipsis").labelStyle(.iconOnly)
        }
    }

    private func beginFollowUp(for meeting: Meeting) {
        let draft = MeetingSetupViewModel(modelContext: modelContext)
        draft.title = meeting.seriesName ?? "\(meeting.title) follow-up"
        draft.scheduledSeriesID = meeting.seriesID
        draft.scheduledSeriesName = meeting.seriesName
        draft.variant = .followUp
        draft.followUpSource = meeting
        followUpDraft = draft
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
        if recordSection == "Minutes", let meeting = viewModel.meeting, hasMinutes {
            if meeting.minutesNeedFinalization == true {
                Button {
                    meeting.minutesNeedFinalization = false
                    do { try modelContext.save() }
                    catch {
                        meeting.minutesNeedFinalization = true
                        deletionError = error.localizedDescription
                    }
                } label: {
                    Text("Finalize minutes").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.regularMaterial)
            } else {
                VStack(spacing: 6) {
                    Button { startSharing = true } label: {
                        Text("Share Minutes").frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(.white)
                            .background(Theme.Colors.manentAccent, in: Capsule())
                    }
                    Button("Continue Without Sharing") { showKeepPrivate = true }
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.manentAccent)
                .padding(.horizontal, 16)
                .background(.regularMaterial)
            }
        }
    }

    private var recordContent: some View {
        VStack(spacing: 0) {
            MeetingRecordHeader(
                viewModel: viewModel,
                section: $recordSection,
                keptPrivate: keptPrivate,
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

            if recordSection == "Decisions" {
                MeetingDecisionsList(viewModel: viewModel)
            } else {
                MeetingDetailTabContentView(
                    selectedTab: viewModel.selectedTab,
                    summary: viewModel.summary,
                    transcriptSegments: viewModel.transcriptSegments,
                    activeSegmentId: viewModel.activeSegmentId,
                    transcriptSearch: $transcriptSearch,
                    actionItems: viewModel.actionItems,
                    notes: viewModel.notes,
                    onSeekTranscript: { viewModel.tapToSeek(segment: $0) },
                    onEditTranscript: { viewModel.beginEditingTranscript(segment: $0) },
                    onReassignSpeaker: { showSpeakerReassign = $0 },
                    onToggleAction: { viewModel.toggleActionItemCompletion($0) },
                    onAddAction: { showActionItemModal = true },
                    onSyncReminders: {
                        Task {
                            do { try await viewModel.syncReviewedTasksToReminders() }
                            catch { deletionError = error.localizedDescription }
                        }
                    },
                    onAddNote: { showNoteSheet = true },
                    onSelectPhoto: { showPhotoModal = $0 }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
