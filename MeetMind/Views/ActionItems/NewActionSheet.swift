import SwiftUI

/// "New Action" sheet: title, notes, due popover, owner menu, and meeting menu.
struct NewActionSheet: View {
    let meetings: [Meeting]
    let localName: String
    let defaultMeetingID: UUID?
    let onSave: (ActionDraft) throws -> Void
    let onCancel: () -> Void

    @State private var draft: ActionDraft
    @State private var errorMessage: String?

    init(
        meetings: [Meeting],
        localName: String,
        defaultMeetingID: UUID? = nil,
        onSave: @escaping (ActionDraft) throws -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.meetings = meetings
        self.localName = localName
        self.defaultMeetingID = defaultMeetingID
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: ActionDraft(
            dueDate: Date(),
            ownerName: localName,
            meetingID: defaultMeetingID
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ActionFormCards(draft: $draft, meetings: meetings, localName: localName, dueFirst: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("New Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", action: onCancel)
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") { save() }
                        .labelStyle(.iconOnly)
                        .disabled(!draft.isValid)
                }
            }
            .alert("Could Not Save Action", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        do {
            try onSave(draft)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
