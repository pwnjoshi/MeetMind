import SwiftUI
import SwiftData

/// "Notes Only" (Figma node 161:1372). The user writes minutes without recording
/// audio. The typed notes become the only source of the minutes, saved as a draft.
public struct NotesOnlyView: View {
    @Environment(\.modelContext) private var modelContext

    public let meetingTitle: String
    public let existingMeeting: Meeting?
    public let onBack: () -> Void
    public let onSaved: (Meeting) -> Void

    @State private var discussion = ""
    @State private var decisions: [DecisionLine] = []
    @State private var actions: [NotesOnlyActionDraft] = []
    @State private var isAddingAction = false
    @State private var saveError: String?
    @FocusState private var focusedDecision: UUID?

    struct DecisionLine: Identifiable, Equatable {
        let id: UUID
        var text: String
        init(id: UUID = UUID(), text: String = "") {
            self.id = id
            self.text = text
        }
    }

    public init(
        meetingTitle: String = NotesOnlyMinutesBuilder.defaultTitle,
        existingMeeting: Meeting? = nil,
        onBack: @escaping () -> Void,
        onSaved: @escaping (Meeting) -> Void
    ) {
        self.meetingTitle = meetingTitle
        self.existingMeeting = existingMeeting
        self.onBack = onBack
        self.onSaved = onSaved
    }

    private var draft: NotesOnlyDraft {
        NotesOnlyDraft(discussion: discussion, decisions: decisions.map(\.text), actions: actions)
    }

    private var displayTitle: String { existingMeeting?.title ?? meetingTitle }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                }
                .accessibilityLabel("Back")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes").font(.largeTitle.bold())
                    Text("\(displayTitle) \u{00B7} No audio")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }

                section("Discussion") {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $discussion)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 96)
                            .accessibilityLabel("Discussion")
                        if discussion.isEmpty {
                            Text("What was discussed?")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                }

                section("Decisions") {
                    ForEach($decisions) { $line in
                        HStack(spacing: 8) {
                            TextField("Decision", text: $line.text, axis: .vertical)
                                .focused($focusedDecision, equals: line.id)
                            Button {
                                removeDecision(line.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove decision")
                        }
                    }
                    Button("Add Decision") {
                        let line = DecisionLine()
                        decisions.append(line)
                        focusedDecision = line.id
                    }
                    .foregroundStyle(Theme.Colors.manentAccent)
                    .frame(minHeight: 44, alignment: .leading)
                }

                section("Actions") {
                    ForEach(actions) { action in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title)
                                if let detail = actionDetail(action) {
                                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Button {
                                actions.removeAll { $0.id == action.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove action")
                        }
                    }
                    Button("Add Action") { isAddingAction = true }
                        .foregroundStyle(Theme.Colors.manentAccent)
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button {
                save()
            } label: {
                Text("Review Minutes").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Theme.Colors.manentAccent)
            .disabled(!draft.hasContent)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .sheet(isPresented: $isAddingAction) {
            NotesOnlyActionSheet { actions.append($0) }
        }
        .alert("Couldn\u{2019}t save notes", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func removeDecision(_ id: UUID) {
        decisions.removeAll { $0.id == id }
    }

    private func actionDetail(_ action: NotesOnlyActionDraft) -> String? {
        var parts: [String] = []
        let owner = action.owner.trimmingCharacters(in: .whitespacesAndNewlines)
        if !owner.isEmpty { parts.append(owner) }
        if let due = action.dueDate {
            parts.append(due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private func save() {
        do {
            let meeting = try NotesOnlyMinutesBuilder.save(
                draft: draft,
                title: meetingTitle,
                existingMeeting: existingMeeting,
                context: modelContext
            )
            onSaved(meeting)
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// Collects one action for the Notes Only screen.
struct NotesOnlyActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (NotesOnlyActionDraft) -> Void

    @State private var title = ""
    @State private var owner = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Action", text: $title, axis: .vertical)
                    TextField("Owner (optional)", text: $owner)
                        .textInputAutocapitalization(.words)
                }
                Section {
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Add Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(NotesOnlyActionDraft(title: title, owner: owner, dueDate: hasDueDate ? dueDate : nil))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
