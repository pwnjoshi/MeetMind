import SwiftUI
import SwiftData
import OfflineEngineKit

struct MeetingAnalysisEvidenceView: View {
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

struct MeetingTaskReviewView: View {
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

struct SuggestedTaskEditor: View {
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

