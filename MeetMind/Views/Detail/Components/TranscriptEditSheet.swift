import SwiftUI

/// Modal sheet for correcting or editing transcript segment text inline
public struct TranscriptEditSheet: View {
    public let initialText: String
    public let onSave: (String) throws -> Void
    public let onDismiss: () -> Void
    
    @State private var saveError: String?
    @State private var editedText: String
    
    public init(initialText: String, onSave: @escaping (String) throws -> Void, onDismiss: @escaping () -> Void) {
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
                        do { try onSave(trimmed) }
                        catch { saveError = error.localizedDescription }
                    }
                    .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .alert("Could Not Save Transcript", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "") }
        .presentationDetents([.height(300)])
    }
}
