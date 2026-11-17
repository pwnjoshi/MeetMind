import SwiftUI
import SwiftData

/// Sheet for creating and assigning tags to a meeting
public struct TagAssignmentSheet: View {
    public let meeting: Meeting
    public var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var availableTags: [Tag]
    @State private var newTagName: String = ""
    @State private var selectedTagIDs: Set<UUID> = []
    
    public init(meeting: Meeting, onDismiss: (() -> Void)? = nil) {
        self.meeting = meeting
        self.onDismiss = onDismiss
        _selectedTagIDs = State(initialValue: Set(meeting.tags.map(\.id)))
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Add New Tag") {
                    HStack {
                        TextField("Tag Name", text: $newTagName)
                        Button("Add") {
                            let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            let tag = Tag(name: trimmed, colorHex: "#8B5CF6")
                            modelContext.insert(tag)
                            try? modelContext.save()
                            selectedTagIDs.insert(tag.id)
                            newTagName = ""
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                
                Section("Tags") {
                    if availableTags.isEmpty {
                        Text("No tags available. Create one above.")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    } else {
                        ForEach(availableTags, id: \.id) { tag in
                            let isSelected = selectedTagIDs.contains(tag.id)
                            HStack {
                                Text(tag.name)
                                    .font(Typography.body)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.Colors.liveBlue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isSelected {
                                    selectedTagIDs.remove(tag.id)
                                } else {
                                    selectedTagIDs.insert(tag.id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss?()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        meeting.tags = availableTags.filter { selectedTagIDs.contains($0.id) }
                        try? modelContext.save()
                        onDismiss?()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
