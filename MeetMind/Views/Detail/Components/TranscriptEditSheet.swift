import SwiftUI

/// Modal sheet for correcting or editing transcript segment text inline
public struct TranscriptEditSheet: View {
    public let initialText: String
    public let onSave: (String) -> Void
    public let onDismiss: () -> Void
    
    @State private var editedText: String
    
    public init(initialText: String, onSave: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
        self.initialText = initialText
        self.onSave = onSave
        self.onDismiss = onDismiss
        _editedText = State(initialValue: initialText)
    }
    
    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Edit Spoken Transcript")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                TextEditor(text: $editedText)
                    .frame(minHeight: 140)
                    .padding(Spacing.sm)
                    .background(Theme.Colors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md))
                
                Spacer()
            }
            .padding(Spacing.lg)
            .navigationTitle("Edit Segment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { onSave(trimmed) }
                    }
                    .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.height(300)])
    }
}
