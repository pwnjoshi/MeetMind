import SwiftUI

/// Sheet for adding or editing an action item from a meeting. Styled like the
/// Actions "New Action" sheet: title card, Due pill, owner, and priority rows.
public struct ActionItemEditModal: View {
    public let existingItem: ActionItem?
    public let onSave: (String, ActionPriority, Date?, String?) -> Void
    public let onDismiss: () -> Void

    @State private var title: String
    @State private var priority: ActionPriority
    @State private var dueDate: Date?
    @State private var assigneeName: String

    public init(
        existingItem: ActionItem? = nil,
        onSave: @escaping (String, ActionPriority, Date?, String?) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.existingItem = existingItem
        self.onSave = onSave
        self.onDismiss = onDismiss
        _title = State(initialValue: existingItem?.title ?? "")
        _priority = State(initialValue: existingItem?.priority ?? .medium)
        _dueDate = State(initialValue: existingItem?.dueDate)
        _assigneeName = State(initialValue: existingItem?.assignee?.name ?? "")
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ActionFormCard {
                        TextField("Title", text: $title)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                    ActionFormCard {
                        HStack {
                            Text("Due")
                            Spacer()
                            ActionDuePill(dueDate: $dueDate)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        Divider().padding(.leading, 16)
                        HStack {
                            Text("Assigned To")
                            Spacer()
                            TextField("Unassigned", text: $assigneeName)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        Divider().padding(.leading, 16)
                        HStack {
                            Text("Priority")
                            Spacer()
                            Picker("Priority", selection: $priority) {
                                ForEach(ActionPriority.allCases, id: \.self) { p in
                                    Text(p.displayName).tag(p)
                                }
                            }
                            .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(existingItem == nil ? "New Action" : "Edit Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", action: onDismiss)
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        if !trimmedTitle.isEmpty {
                            let owner = assigneeName.trimmingCharacters(in: .whitespacesAndNewlines)
                            onSave(trimmedTitle, priority, dueDate, owner.isEmpty ? nil : owner)
                        }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
