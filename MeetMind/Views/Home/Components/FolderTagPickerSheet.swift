import SwiftUI
import SwiftData

public struct FolderTagPickerSheet: View {
    public let meeting: Meeting
    public var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var availableFolders: [Folder]
    @Query private var availableTags: [Tag]
    @State private var selectedFolder: Folder?
    @State private var selectedTags: Set<UUID> = []
    @State private var newFolderName: String = ""
    
    public init(meeting: Meeting, onSave: @escaping () -> Void) {
        self.meeting = meeting
        self.onSave = onSave
        _selectedFolder = State(initialValue: meeting.folder)
        _selectedTags = State(initialValue: Set(meeting.tags.map(\.id)))
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Assign to Folder") {
                    Picker("Folder", selection: $selectedFolder) {
                        Text("None").tag(nil as Folder?)
                        ForEach(availableFolders, id: \.id) { folder in
                            HStack {
                                Image(systemName: folder.iconName)
                                Text(folder.name)
                            }.tag(folder as Folder?)
                        }
                    }
                    HStack {
                        TextField("New Folder Name", text: $newFolderName)
                        Button("Add") {
                            let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            let f = Folder(name: trimmed)
                            modelContext.insert(f)
                            try? modelContext.save()
                            selectedFolder = f
                            newFolderName = ""
                        }
                        .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section("Meeting Tags") {
                    ForEach(availableTags, id: \.id) { tag in
                        let isSelected = selectedTags.contains(tag.id)
                        HStack {
                            Text(tag.name)
                            Spacer()
                            if isSelected { Image(systemName: "checkmark").foregroundStyle(Theme.Colors.primarySlate) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelected { selectedTags.remove(tag.id) } else { selectedTags.insert(tag.id) }
                        }
                    }
                }
            }
            .navigationTitle("Organize Meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        meeting.folder = selectedFolder
                        meeting.tags = availableTags.filter { selectedTags.contains($0.id) }
                        try? modelContext.save()
                        onSave()
                        dismiss()
                    }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
