import SwiftUI
import SwiftData

/// Required review gate between generated/typed minutes and the final record.
@MainActor
public struct MinutesReviewChecklistView: View {
    public let meeting: Meeting

    @Environment(\.modelContext) private var modelContext
    @State private var store = ReviewStateStore.shared
    @State private var viewModel: MeetingDetailViewModel
    @State private var showsTranscript = false
    @State private var showsPeople = false
    @State private var showsTasks = false
    @State private var showsMinutesEditor = false
    @State private var errorMessage: String?

    public init(meeting: Meeting) {
        self.meeting = meeting
        _viewModel = State(initialValue: MeetingDetailViewModel(meeting: meeting, modelContext: meeting.modelContext))
    }

    private var content: MinutesReviewContentSnapshot {
        MinutesReviewContentSnapshot.make(from: meeting)
    }

    private var reviewState: ReviewStateRecord {
        do { return try store.record(for: meeting.id) }
        catch { return ReviewStateRecord() }
    }

    private var checklist: MinutesReviewChecklist {
        MinutesReviewChecklist.evaluate(
            content: content,
            acknowledgements: reviewState.acknowledgements(validFor: content.fingerprint)
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(meeting.title).font(.title.bold())
                    Text(checklist.canFinalize ? "Ready to finalize" : "Draft")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(checklist.canFinalize ? Color.green : Color.orange)
                    Text("Check the source, people, tasks and minutes before locking this version.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(checklist.checks.enumerated()), id: \.element.id) { index, check in
                        checklistRow(check)
                        if index < checklist.checks.count - 1 { Divider().padding(.leading, 56) }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text("Finalization applies to this exact content. Editing the agenda, attendance, transcript or notes, discussion, decisions, or actions returns it to Draft.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Review Minutes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            Button("Finalize Minutes") { finalize() }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(!checklist.canFinalize)
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(.regularMaterial)
        }
        .navigationDestination(isPresented: $showsTranscript) {
            MeetingTranscriptAudioPage(viewModel: viewModel, searchText: .constant("")) { _ in showsPeople = true }
        }
        .sheet(isPresented: $showsPeople) {
            MeetingPeopleSheet(meeting: meeting, viewModel: viewModel)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsTasks) {
            MeetingTaskReviewView(meeting: meeting)
        }
        .sheet(isPresented: $showsMinutesEditor) {
            if let summary = meeting.summary {
                EditSavedMinutesSheet(meeting: meeting, summary: summary)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            do { _ = try store.record(for: meeting.id) }
            catch { errorMessage = error.localizedDescription }
        }
        .alert("Review State Unavailable", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func checklistRow(_ check: MinutesReviewCheck) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: check.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(check.isComplete ? Color.green : Color.secondary)
                .frame(width: 28, height: 28)
                .accessibilityLabel(check.isComplete ? "Complete" : "Needs review")
            VStack(alignment: .leading, spacing: 5) {
                Text(check.title).font(.headline)
                Text(check.detail).font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Button(openTitle(for: check.item)) { open(check.item) }
                        .font(.subheadline.weight(.semibold))
                    if let acknowledgement = acknowledgement(for: check.item) {
                        Button(check.isComplete ? "Mark unchecked" : acknowledgementTitle(for: check.item)) {
                            setAcknowledgement(acknowledgement, accepted: !check.isComplete)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func openTitle(for item: MinutesReviewItem) -> String {
        switch item {
        case .source: return content.source == .typedNotes ? "Edit minutes" : "Open transcript"
        case .speakers: return "Open people"
        case .suggestedTasks: return "Review tasks"
        case .agenda, .decisions: return "Edit minutes"
        case .attendance: return "Open people"
        }
    }

    private func open(_ item: MinutesReviewItem) {
        switch item {
        case .source:
            if content.source == .typedNotes { showsMinutesEditor = true } else { showsTranscript = true }
        case .speakers, .attendance:
            showsPeople = true
        case .suggestedTasks:
            showsTasks = true
        case .agenda, .decisions:
            showsMinutesEditor = true
        }
    }

    private func acknowledgement(for item: MinutesReviewItem) -> ReviewAcknowledgement? {
        switch item {
        case .speakers where content.unknownVoiceCount > 0: return .acceptUnknownVoices
        case .agenda: return content.agenda.isEmpty ? .acceptNoAgenda : .reviewedAgenda
        case .attendance: return content.attendance.isEmpty ? .acceptNoAttendance : .reviewedAttendance
        case .decisions: return content.decisions.isEmpty ? .acceptNoDecisions : .reviewedDecisions
        default: return nil
        }
    }

    private func acknowledgementTitle(for item: MinutesReviewItem) -> String {
        switch item {
        case .speakers: return "Accept unknown voices"
        case .agenda: return content.agenda.isEmpty ? "Accept no agenda" : "Mark agenda reviewed"
        case .attendance: return content.attendance.isEmpty ? "Accept no attendance" : "Mark attendance reviewed"
        case .decisions: return content.decisions.isEmpty ? "Accept no decisions" : "Mark decisions reviewed"
        default: return "Mark reviewed"
        }
    }

    private func setAcknowledgement(_ acknowledgement: ReviewAcknowledgement, accepted: Bool) {
        do {
            try store.setAcknowledgement(acknowledgement, accepted: accepted, meetingID: meeting.id,
                                         contentFingerprint: content.fingerprint)
        }
        catch { errorMessage = error.localizedDescription }
    }

    private func finalize() {
        let currentContent = MinutesReviewContentSnapshot.make(from: meeting)
        let state: ReviewStateRecord
        do { state = try store.record(for: meeting.id) }
        catch { errorMessage = error.localizedDescription; return }
        guard MinutesReviewChecklist.evaluate(
            content: currentContent,
            acknowledgements: state.acknowledgements(validFor: currentContent.fingerprint)
        ).canFinalize else {
            errorMessage = "Complete every review item before finalizing."
            return
        }
        do {
            try store.finalize(meetingID: meeting.id, fingerprint: currentContent.fingerprint)
            meeting.minutesNeedFinalization = false
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
