import SwiftUI

/// Folder and Tag manager view
public struct FolderManagerView: View {
    @State private var viewModel: FolderTagViewModel
    public var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    
    public init(viewModel: FolderTagViewModel? = nil, onDismiss: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel ?? FolderTagViewModel())
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Create Folder") {
                    HStack {
                        TextField("Folder Name", text: $viewModel.newFolderName)
                        Button("Create") { viewModel.createFolder(name: viewModel.newFolderName) }
                            .disabled(viewModel.newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section("Existing Folders") {
                    if viewModel.folders.isEmpty {
                        Text("No custom folders created yet.").font(Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                    } else {
                        ForEach(viewModel.folders, id: \.id) { folder in
                            HStack {
                                Image(systemName: folder.iconName).foregroundStyle(Theme.Colors.liveBlue)
                                Text(folder.name)
                                Spacer()
                                Text("\(folder.meetingCount) meetings").font(Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                        .onDelete { for i in $0 { viewModel.deleteFolder(viewModel.folders[i]) } }
                    }
                }
                Section("Create Tag") {
                    HStack {
                        TextField("Tag Name", text: $viewModel.newTagName)
                        Button("Create") { viewModel.createTag(name: viewModel.newTagName) }
                            .disabled(viewModel.newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section("Existing Tags") {
                    if viewModel.tags.isEmpty {
                        Text("No custom tags created yet.").font(Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                    } else {
                        ForEach(viewModel.tags, id: \.id) { tag in
                            HStack {
                                Circle().fill(Theme.Colors.aiPurple).frame(width: 8, height: 8)
                                Text(tag.name)
                                Spacer()
                                Text("\(tag.meetingCount) meetings").font(Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                        .onDelete { for i in $0 { viewModel.deleteTag(viewModel.tags[i]) } }
                    }
                }
            }
            .navigationTitle("Folders & Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss?()
                        dismiss()
                    }
                }
            }
        }
    }
}
