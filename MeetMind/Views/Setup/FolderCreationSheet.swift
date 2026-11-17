import SwiftUI
import SwiftData

/// Modal sheet for creating a new custom folder
public struct FolderCreationSheet: View {
    public var onCreated: ((Folder) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var folderName: String = ""
    @State private var selectedColorHex: String = "#3B82F6"
    
    private let availableColors = ["#3B82F6", "#10B981", "#8B5CF6", "#F59E0B", "#EF4444"]
    
    public init(onCreated: ((Folder) -> Void)? = nil) {
        self.onCreated = onCreated
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Folder Details") {
                    TextField("Folder Name", text: $folderName)
                        .font(Typography.body)
                }
                
                Section("Color") {
                    HStack(spacing: Spacing.md) {
                        ForEach(availableColors, id: \.self) { colorHex in
                            Circle()
                                .fill(Color(hex: colorHex))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColorHex == colorHex ? 2 : 0)
                                )
                                .onTapGesture {
                                    selectedColorHex = colorHex
                                }
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                }
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let folder = Folder(name: trimmed, colorHex: selectedColorHex)
                        modelContext.insert(folder)
                        try? modelContext.save()
                        onCreated?(folder)
                        dismiss()
                    }
                    .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
