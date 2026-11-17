import SwiftUI

/// Modal sheet for creating or editing meeting action items
public struct ActionItemEditModal: View {
    public let existingItem: ActionItem?
    public let onSave: (String, ActionPriority, Date?, String?) -> Void
    public let onDismiss: () -> Void
    
    @State private var title: String
    @State private var priority: ActionPriority
    @State private var dueDate: Date
    @State private var hasDueDate: Bool
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
        _dueDate = State(initialValue: existingItem?.dueDate ?? Date().addingTimeInterval(86400))
        _hasDueDate = State(initialValue: existingItem?.dueDate != nil)
        _assigneeName = State(initialValue: existingItem?.assignee?.name ?? "")
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Task Details") {
                    TextField("Action Item Title", text: $title)
                    TextField("Assignee Name", text: $assigneeName)
                    Picker("Priority", selection: $priority) {
                        ForEach(ActionPriority.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                }
                
                Section("Due Date") {
                    Toggle("Set Due Date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Date", selection: $dueDate, displayedComponents: [.date])
                    }
                }
            }
            .navigationTitle(existingItem == nil ? "New Action Item" : "Edit Action Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onDismiss) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onSave(trimmed, priority, hasDueDate ? dueDate : nil, assigneeName.isEmpty ? nil : assigneeName)
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
