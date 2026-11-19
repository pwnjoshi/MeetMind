import SwiftUI
import SwiftData
import OfflineEngineKit

/// Master meeting cockpit displaying segmented tabs, audio synchronization, and action extraction
public struct MeetingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @State public var viewModel: MeetingDetailViewModel
    
    @State private var transcriptSearch: String = ""
    @State private var showRenameAlert: Bool = false
    @State private var renameText: String = ""
    @State private var showExportSheet: Bool = false
    @State private var showAskAISheet: Bool = false
    @State private var showActionItemModal: Bool = false
    @State private var showPhotoModal: String? = nil
    @State private var showSpeakerReassign: TranscriptSegment? = nil
    @State private var showDeleteConfirmation = false
    @State private var deletionError: String?
    @State private var showNoteSheet = false
    @State private var showTaskReview = false
    @State private var showAnalysisEvidence = false
    
    public init(viewModel: MeetingDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            MeetingDetailHeaderView(
                title: viewModel.headerTitle,
                durationText: viewModel.headerDurationText,
                statusTitle: viewModel.statusBadgeTitle,
                onRename: { renameText = viewModel.headerTitle; showRenameAlert = true },
                onExport: { showExportSheet = true },
                onAskAI: { showAskAISheet = true },
                onDelete: { showDeleteConfirmation = true }
            )
            MeetingDetailTabBarView(selectedTab: viewModel.selectedTab) { viewModel.selectTab($0) }
            if let meeting = viewModel.meeting, !meeting.pendingTaskSuggestions.isEmpty {
                Button("Review \(meeting.pendingTaskSuggestions.count) suggested tasks") { showTaskReview = true }
                    .buttonStyle(.borderedProminent).padding(.vertical, 8)
            }
            if viewModel.selectedTab == .summary, viewModel.meeting?.offlineAnalysis != nil {
                Button("Review summary evidence") { showAnalysisEvidence = true }
                    .font(.subheadline).padding(.vertical, 4)
            }
            if let meeting = viewModel.meeting, meeting.status == .scheduled || meeting.status == .processing || meeting.status == .recording {
                Button(meeting.status == .scheduled ? "Start recording" : "Process saved audio") {
                    if meeting.status == .scheduled {
                        meeting.status = .recording
                        do {
                            try modelContext.save()
                            router.navigate(to: .liveRecording(id: meeting.id), in: .home)
                        } catch { deletionError = error.localizedDescription }
                    } else {
                        router.navigate(to: .meetingProcessing(id: meeting.id), in: .home)
                    }
                }
                .buttonStyle(.borderedProminent).padding(.vertical, 8)
            }
            
            MeetingDetailTabContentView(
                selectedTab: viewModel.selectedTab,
                summary: viewModel.summary,
                transcriptSegments: viewModel.transcriptSegments,
                activeSegmentId: viewModel.activeSegmentId,
                transcriptSearch: $transcriptSearch,
                actionItems: viewModel.actionItems,
                notes: viewModel.notes,
                onCopySummary: { UIPasteboard.general.string = viewModel.generateCopyableSummaryText() },
                onRegenerateSummary: {
                    if let meeting = viewModel.meeting {
                        Task {
                            do {
                                try await MeetingAnalysisPipeline.shared.removeCheckpoint(meetingID: meeting.id)
                                router.navigate(to: .meetingProcessing(id: meeting.id), in: .home)
                            } catch { deletionError = error.localizedDescription }
                        }
                    }
                },
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
            
            if let duration = viewModel.meeting?.duration, duration > 0 {
                StickyAudioPlayerBar(
                    currentTime: viewModel.currentPlayheadTime,
                    totalDuration: duration,
                    isPlaying: viewModel.isPlaying,
                    playbackRate: viewModel.playbackRate,
                    onTogglePlayPause: { viewModel.togglePlayPause() },
                    onSeek: { viewModel.seek(to: $0) },
                    onSkipBackward: { viewModel.seek(to: max(0, viewModel.currentPlayheadTime - 15)) },
                    onSkipForward: { viewModel.seek(to: min(duration, viewModel.currentPlayheadTime + 15)) },
                    onCycleRate: { cyclePlaybackRate() }
                )
            }
        }
        .background(Color(hex: "#F7F7FC").ignoresSafeArea())
        .tint(Color(hex: "#4B3FF0"))
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
            renameText: $renameText
        ))
        .sheet(isPresented: $showActionItemModal) {
            ActionItemEditModal(onSave: { title, priority, dueDate, assignee in
                if let meeting = viewModel.meeting {
                    meeting.addActionItem(ActionItem(title: title, assigneeName: assignee, dueDate: dueDate, priority: priority))
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
                viewModel.reassignSpeaker(segment: segment, newSpeaker: speaker)
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
    
    private func cyclePlaybackRate() {
        let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]
        let current = viewModel.playbackRate
        if let idx = rates.firstIndex(where: { abs($0 - current) < 0.05 }) {
            viewModel.setPlaybackRate(rates[(idx + 1) % rates.count])
        } else {
            viewModel.setPlaybackRate(1.0)
        }
    }
}

private struct MeetingAnalysisEvidenceView: View {
    let result: MeetingAnalysisCheckpoint
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                evidenceSection("Discussion", points: result.analysis.flatMap(\.discussion))
                evidenceSection("Decisions", points: result.analysis.flatMap(\.decisions))
            }
            .navigationTitle("Summary evidence")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func evidenceSection(_ title: String, points: [SupportedPoint]) -> some View {
        Section(title) {
            if points.isEmpty { Text("No supported points extracted.").foregroundStyle(.secondary) }
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                VStack(alignment: .leading, spacing: 8) {
                    Text(point.text).font(.headline)
                    ForEach(Array(point.evidence.enumerated()), id: \.offset) { _, source in
                        if let turn = result.turns.first(where: { $0.id == source.turnID }) {
                            Text(String(format: "[%02d:%02d] ", Int(turn.start) / 60, Int(turn.start) % 60) + source.quote)
                                .font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}

private struct MeetingTaskReviewView: View {
    let meeting: Meeting
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("These are AI suggestions. Confirm the task, owner, category, and deadline against the quoted transcript before adding it. Speaker labels do not establish a person's identity.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(meeting.pendingTaskSuggestions) { suggestion in
                    NavigationLink {
                        SuggestedTaskEditor(meeting: meeting, suggestion: suggestion)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(suggestion.task.title)
                            Text(suggestion.task.category).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if meeting.pendingTaskSuggestions.isEmpty { Text("All suggestions reviewed.") }
            }
            .navigationTitle("Review tasks")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct SuggestedTaskEditor: View {
    let meeting: Meeting
    let suggestion: MeetingTaskSuggestion
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var owner: String
    @State private var category: String
    @State private var priority: String
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var errorMessage: String?

    init(meeting: Meeting, suggestion: MeetingTaskSuggestion) {
        self.meeting = meeting
        self.suggestion = suggestion
        _title = State(initialValue: suggestion.task.title)
        _owner = State(initialValue: suggestion.task.owner ?? "")
        _category = State(initialValue: suggestion.task.category)
        _priority = State(initialValue: suggestion.task.priority ?? "")
    }

    var body: some View {
        Form {
            Section("Task") {
                TextField("Title", text: $title, axis: .vertical)
                TextField("Owner (optional)", text: $owner)
                Picker("Category", selection: $category) {
                    ForEach(["Follow-up", "Research", "Create/Update", "Review/Approve", "Coordination", "Other"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                Picker("Priority", selection: $priority) {
                    Text("Unspecified").tag("")
                    ForEach(ActionPriority.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
                }
                if let deadline = suggestion.task.deadlineText {
                    Text("Spoken deadline: \(deadline)")
                    Text("Meeting date: \((meeting.scheduledStartTime ?? meeting.createdAt).formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Toggle("Set confirmed due date", isOn: $hasDueDate)
                if hasDueDate { DatePicker("Due date", selection: $dueDate, displayedComponents: .date) }
            }
            Section("Transcript evidence") {
                ForEach(Array(suggestion.task.evidence.enumerated()), id: \.offset) { _, source in
                    VStack(alignment: .leading, spacing: 6) {
                        if let turn = meeting.offlineAnalysis?.turns.first(where: { $0.id == source.turnID }) {
                            Text("\(Int(turn.start) / 60):\(String(format: "%02d", Int(turn.start) % 60)) · \(turn.speaker ?? "Unassigned speaker")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(source.quote).textSelection(.enabled)
                    }
                }
            }
            Section {
                Button("Confirm and add task") { save(accept: true) }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Discard suggestion", role: .destructive) { save(accept: false) }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle("Confirm task")
    }

    private func save(accept: Bool) {
        do {
            try meeting.reviewTask(suggestion, title: title, owner: owner, category: category,
                priority: priority, dueDate: hasDueDate ? Calendar.current.startOfDay(for: dueDate) : nil, accept: accept, context: context)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
