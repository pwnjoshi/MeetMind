import SwiftUI

/// Modal sheet to create a new action item with title, priority, due date, and assignee
public struct CreateActionItemSheet: View {
    public let onSave: (String, ActionPriority, Date?, String?) -> Void
    public let onDismiss: () -> Void
    
    @State private var title: String = ""
    @State private var priority: ActionPriority = .medium
    @State private var dueDate: Date = Date().addingTimeInterval(86400)
    @State private var hasDueDate: Bool = false
    @State private var assignee: String = ""
    
    public init(onSave: @escaping (String, ActionPriority, Date?, String?) -> Void, onDismiss: @escaping () -> Void) {
        self.onSave = onSave
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Task Details") {
                    TextField("Action Item Title", text: $title)
                    TextField("Assignee", text: $assignee)
                    Picker("Priority", selection: $priority) {
                        ForEach(ActionPriority.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                }
                
                Section("Schedule") {
                    Toggle("Set Due Date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date])
                    }
                }
            }
            .navigationTitle("New Action Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onDismiss) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onSave(trimmed, priority, hasDueDate ? dueDate : nil, assignee.isEmpty ? nil : assignee)
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
