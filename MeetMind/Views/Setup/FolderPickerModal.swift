import SwiftUI
import SwiftData

/// Modal for choosing and assigning a Folder to a meeting
public struct FolderPickerModal: View {
    public let meeting: Meeting
    public var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var folders: [Folder]
    @State private var showingCreateSheet: Bool = false
    
    public init(meeting: Meeting, onDismiss: (() -> Void)? = nil) {
        self.meeting = meeting
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        meeting.folder = nil
                        try? modelContext.save()
                        onDismiss?()
                        dismiss()
                    } label: {
                        HStack {
                            Text("No Folder")
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            if meeting.folder == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.Colors.liveBlue)
                            }
                        }
                    }
                }
                
                Section("Your Folders") {
                    ForEach(folders, id: \.id) { folder in
                        Button {
                            meeting.folder = folder
                            try? modelContext.save()
                            onDismiss?()
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: folder.iconName)
                                    .foregroundStyle(Theme.Colors.liveBlue)
                                Text(folder.name)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Spacer()
                                if meeting.folder?.id == folder.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.Colors.liveBlue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss?()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                FolderCreationSheet { newFolder in
                    meeting.folder = newFolder
                    try? modelContext.save()
                    onDismiss?()
                    dismiss()
                }
            }
        }
    }
}
