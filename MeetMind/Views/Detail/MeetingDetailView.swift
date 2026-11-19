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
    @State private var showPeople = false
    @State private var showMinutesEditor = false
    @State private var followUpDraft: MeetingSetupViewModel?
    @State private var showFollowUp = false
    @State private var recordSection = "Minutes"
    
    public init(viewModel: MeetingDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            recordHeader
            if recordSection == "Minutes", let meeting = viewModel.meeting,
               meeting.resolvedAudioFileURL != nil || !meeting.transcriptSegments.isEmpty {
                Button(action: openTranscript) {
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
                List {
                    let decisions = viewModel.summary?.keyDecisions ?? []
                    if decisions.isEmpty { Text("No decisions recorded").foregroundStyle(.secondary) }
                    ForEach(Array(decisions.enumerated()), id: \.offset) { entry in
                        NavigationLink {
                            MeetingDecisionDetail(viewModel: viewModel, index: entry.offset)
                        } label: {
                            Text(entry.element)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                MeetingDetailTabContentView(
                selectedTab: viewModel.selectedTab,
                summary: viewModel.summary,
                transcriptSegments: viewModel.transcriptSegments,
                activeSegmentId: viewModel.activeSegmentId,
                transcriptSearch: $transcriptSearch,
                actionItems: viewModel.actionItems,
                notes: viewModel.notes,
                onDocumentFormat: { showExportSheet = true },
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
            
            if recordSection == "Transcript", let duration = viewModel.meeting?.duration, duration > 0 {
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
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .tint(Theme.Colors.manentAccent)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            if recordSection == "Minutes", let meeting = viewModel.meeting,
               meeting.minutesNeedFinalization == true, meeting.summary != nil {
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
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Vidur", systemImage: "sparkles") { showAskAISheet = true }.labelStyle(.iconOnly)
                Menu {
                    Button("Rename Meeting", systemImage: "pencil") {
                        renameText = viewModel.headerTitle
                        showRenameAlert = true
                    }
                    if let meeting = viewModel.meeting, meeting.status == .completed {
                        Button("Schedule Follow-Up", systemImage: "calendar") {
                            let draft = MeetingSetupViewModel(modelContext: modelContext)
                            draft.title = meeting.seriesName ?? "\(meeting.title) follow-up"
                            draft.scheduledSeriesID = meeting.seriesID
                            draft.scheduledSeriesName = meeting.seriesName
                            followUpDraft = draft
                            showFollowUp = true
                        }
                    }
                    Button("Show Transcript", systemImage: "doc.text", action: openTranscript)
                    Button("Notes & Media", systemImage: "photo") {
                        recordSection = "Notes & Media"
                        viewModel.selectTab(.notesMedia)
                    }
                    Button("Share Minutes", systemImage: "square.and.arrow.up") { showExportSheet = true }
                    if viewModel.summary != nil {
                        Button("Edit Minutes", systemImage: "pencil.line") { showMinutesEditor = true }
                    }
                    if viewModel.meeting?.offlineAnalysis != nil {
                        Button("Review Evidence") { showAnalysisEvidence = true }
                    }
                    Button("Delete Meeting", systemImage: "trash", role: .destructive) { showDeleteConfirmation = true }
                } label: {
                    Label("Meeting options", systemImage: "ellipsis").labelStyle(.iconOnly)
                }
            }
        }
        .sheet(isPresented: $showPeople) {
            NavigationStack {
                List(viewModel.meeting?.participants ?? [], id: \.id) { person in
                    let absent = viewModel.meeting?.absentParticipantIDs?.contains(person.id) == true
                    LabeledContent(person.name, value: absent ? "Absent" : "Present")
                }
                    .navigationTitle("People")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPeople = false } } }
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
            renameText: $renameText
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
    
    private func openTranscript() {
        recordSection = "Transcript"
        viewModel.selectTab(.transcript)
    }

    private var recordHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.headerTitle).font(.title.bold())
            if let meeting = viewModel.meeting {
                Text((meeting.scheduledStartTime ?? meeting.createdAt).formatted(date: .long, time: .shortened))
                    .font(.footnote).foregroundStyle(.secondary)
                MeetingSeriesMenu(meeting: meeting) { deletionError = $0 }
                MeetingPeopleRow(meeting: meeting) { showPeople = true }
            }
            Picker("Meeting section", selection: $recordSection) {
                ForEach(["Minutes", "Actions", "Decisions"], id: \.self) { Text($0) }
                if recordSection == "Transcript" || recordSection == "Notes & Media" {
                    Text(recordSection).tag(recordSection)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: recordSection) { _, section in
                if section == "Minutes" { viewModel.selectTab(.summary) }
                if section == "Actions" { viewModel.selectTab(.actionItems) }
                if section != "Transcript" { viewModel.stopPlayback() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
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

private struct MeetingDecisionDetail: View {
    let viewModel: MeetingDetailViewModel
    let index: Int
    @Environment(\.modelContext) private var context
    @State private var draft = ""
    @State private var editing = false
    @State private var saveError: String?
    @State private var playingTurnID: String?

    var body: some View {
        List {
            if let summary = viewModel.summary, summary.keyDecisions.indices.contains(index) {
                let decision = summary.keyDecisions[index]
                Section(viewModel.headerTitle) {
                    Text(decision).font(.title2.bold())
                }
                if let result = viewModel.meeting?.offlineAnalysis,
                   let point = result.analysis.lazy.flatMap(\.decisions).first(where: { $0.text == decision }) {
                    Section("How It Was Decided") {
                        ForEach(Array(point.evidence.enumerated()), id: \.offset) { entry in
                            if let turn = result.turns.first(where: { $0.id == entry.element.turnID }) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(turn.speaker ?? "Speaker") · \(Duration.seconds(turn.start).formatted(.time(pattern: .minuteSecond)))")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Text(entry.element.quote).textSelection(.enabled)
                                    if viewModel.meeting?.resolvedAudioFileURL != nil {
                                        let isPlaying = playingTurnID == turn.id && viewModel.isPlaying
                                        Button(isPlaying ? "Pause Supporting Audio" : "Play Supporting Audio",
                                               systemImage: isPlaying ? "pause.circle" : "play.circle") {
                                            if isPlaying {
                                                viewModel.stopPlayback()
                                                playingTurnID = nil
                                            } else {
                                                viewModel.seek(to: turn.start)
                                                if !viewModel.isPlaying { viewModel.togglePlayPause() }
                                                playingTurnID = turn.id
                                            }
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Decision Unavailable", systemImage: "doc.text")
            }
        }
        .navigationTitle("Decision")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let summary = viewModel.summary, summary.keyDecisions.indices.contains(index) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit Decision", systemImage: "pencil") {
                        draft = summary.keyDecisions[index]
                        editing = true
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                Form { TextField("Decision", text: $draft, axis: .vertical) }
                    .navigationTitle("Edit Decision")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { save() }
                                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .alert("Could Not Save Decision", isPresented: Binding(
                        get: { saveError != nil }, set: { if !$0 { saveError = nil } }
                    )) {
                        Button("OK") { saveError = nil }
                    } message: { Text(saveError ?? "") }
            }
        }
        .onDisappear { viewModel.stopPlayback() }
    }

    private func save() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let summary = viewModel.summary, summary.keyDecisions.indices.contains(index) else { return }
        let previous = summary.keyDecisions
        summary.keyDecisions[index] = text
        do {
            try context.save()
            editing = false
        } catch {
            summary.keyDecisions = previous
            saveError = error.localizedDescription
        }
    }
}

private struct EditSavedMinutesSheet: View {
    let meeting: Meeting
    let summary: Summary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var discussion: String
    @State private var decisions: String
    @State private var agenda: String
    @State private var absentIDs: Set<UUID>
    @State private var saveError: String?

    init(meeting: Meeting, summary: Summary) {
        self.meeting = meeting
        self.summary = summary
        _agenda = State(initialValue: meeting.agendaText ?? "")
        _absentIDs = State(initialValue: Set(meeting.absentParticipantIDs ?? []))
        _discussion = State(initialValue: summary.executiveSummary)
        _decisions = State(initialValue: summary.keyDecisions.joined(separator: "\n"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Agenda") {
                    TextField("Agenda", text: $agenda, axis: .vertical)
                }
                if !meeting.participants.isEmpty {
                    attendanceSection("Present", absent: false)
                    attendanceSection("Absent", absent: true)
                }
                Section("Discussion") {
                    TextEditor(text: $discussion)
                        .frame(minHeight: 110)
                        .accessibilityLabel("Discussion")
                }
                Section {
                    TextEditor(text: $decisions)
                        .frame(minHeight: 110)
                        .accessibilityLabel("Decisions")
                } header: {
                    Text("Decisions")
                } footer: {
                    Text("Enter one decision per line.")
                }
            }
            .navigationTitle("Edit Minutes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Minutes", systemImage: "checkmark") { save() }.labelStyle(.iconOnly)
                }
            }
            .alert("Could Not Save Minutes", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") { saveError = nil }
            } message: { Text(saveError ?? "") }
        }
    }

    private func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func attendanceSection(_ title: String, absent: Bool) -> some View {
        Section(title) {
            let people = meeting.participants.filter { absentIDs.contains($0.id) == absent }
            if people.isEmpty { Text("No participants").foregroundStyle(.secondary) }
            ForEach(people, id: \.id) { person in
                Button {
                    if absent { absentIDs.remove(person.id) }
                    else { absentIDs.insert(person.id) }
                } label: {
                    Label(person.name, systemImage: absent ? "plus.circle.fill" : "minus.circle.fill")
                }
                .accessibilityLabel("Mark \(person.name) \(absent ? "present" : "absent")")
            }
        }
    }

    private func save() {
        let previous = (summary.executiveSummary, summary.keyPoints, summary.keyDecisions)
        let previousMeeting = (meeting.agendaText, meeting.absentParticipantIDs)
        meeting.agendaText = agenda.trimmingCharacters(in: .whitespacesAndNewlines)
        meeting.absentParticipantIDs = absentIDs.sorted { $0.uuidString < $1.uuidString }
        if discussion != previous.0 {
            summary.executiveSummary = discussion.trimmingCharacters(in: .whitespacesAndNewlines)
            summary.keyPoints = lines(discussion)
        }
        summary.keyDecisions = lines(decisions)
        do {
            try context.save()
            dismiss()
        } catch {
            (summary.executiveSummary, summary.keyPoints, summary.keyDecisions) = previous
            (meeting.agendaText, meeting.absentParticipantIDs) = previousMeeting
            saveError = error.localizedDescription
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

struct MeetingPeopleRow: View {
    let meeting: Meeting
    let openPeople: () -> Void

    var body: some View {
        let absentIDs = Set(meeting.absentParticipantIDs ?? [])
        let people = meeting.participants.filter { $0.name != $0.recordingVoiceLabel }
        let present = people.filter { !absentIDs.contains($0.id) }
        Button(action: openPeople) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("People")
                    Text("\(present.count) present · \(people.count - present.count) absent")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: -6) {
                    ForEach(present.prefix(4), id: \.id) { person in
                        Text(person.initials)
                            .font(.caption2.bold()).foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color(hex: person.colorHex), in: Circle())
                            .overlay(Circle().strokeBorder(.background, lineWidth: 1))
                    }
                }
                .accessibilityHidden(true)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }
}
