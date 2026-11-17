import SwiftUI

/// Sheet modal to record timestamp-pinned notes during active recording
public struct LiveNoteTakingSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let timestamp: TimeInterval
    public var onSaveNote: (String) -> Void
    
    @State private var noteText: String = ""
    
    public init(timestamp: TimeInterval, onSaveNote: @escaping (String) -> Void) {
        self.timestamp = timestamp
        self.onSaveNote = onSaveNote
    }
    
    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(Theme.Colors.liveBlue)
                    Text("Pinned to \(formattedTimecode(timestamp))")
                        .font(Typography.timecode)
                        .foregroundStyle(Theme.Colors.liveBlue)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.Colors.liveBlueLight)
                .clipShape(Capsule())
                
                TextEditor(text: $noteText)
                    .font(Typography.body)
                    .frame(minHeight: 140)
                    .padding(8)
                    .background(Theme.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.cardBorder, lineWidth: 1))
                
                Spacer()
            }
            .padding(Spacing.lg)
            .navigationTitle("Add Live Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSaveNote(noteText)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private func formattedTimecode(_ time: TimeInterval) -> String {
        let total = Int(time)
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
