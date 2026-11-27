import SwiftUI

/// Edits the text of every segment in one transcript card.
struct TranscriptCardEditSheet: View {
    let card: TranscriptCard
    let onSave: ([UUID: String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [UUID: String]

    init(card: TranscriptCard, onSave: @escaping ([UUID: String]) -> Void) {
        self.card = card
        self.onSave = onSave
        var initial: [UUID: String] = [:]
        for line in card.lines { initial[line.id] = line.text }
        _drafts = State(initialValue: initial)
    }

    private var canSave: Bool {
        var changed = false
        for line in card.lines {
            let draft = (drafts[line.id] ?? line.text).trimmingCharacters(in: .whitespacesAndNewlines)
            if draft.isEmpty { return false }
            if draft != line.text { changed = true }
        }
        return changed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ForEach(card.lines) { line in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            if card.lines.count > 1 {
                                Text(TranscriptClock.text(line.start))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            TextEditor(text: binding(for: line))
                                .frame(minHeight: 100)
                                .padding(Spacing.sm)
                                .scrollContentBackground(.hidden)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Theme.Colors.cardBackground)
                                )
                                .accessibilityLabel("Transcript text, \(card.speakerName), \(TranscriptClock.spoken(line.start))")
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Edit text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(drafts)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func binding(for line: TranscriptCardLine) -> Binding<String> {
        Binding(
            get: { drafts[line.id] ?? line.text },
            set: { drafts[line.id] = $0 }
        )
    }
}
