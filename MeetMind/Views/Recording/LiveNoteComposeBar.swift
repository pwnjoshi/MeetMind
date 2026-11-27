import SwiftUI

/// Inline compose bar shown above the keyboard while recording
/// ("Add a Note Â· Compose bar", Figma node 1871:338). Saves one timestamped note.
public struct LiveNoteComposeBar: View {
    public let timestamp: TimeInterval
    public let onSave: (String) -> Void
    public let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    public init(timestamp: TimeInterval, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.timestamp = timestamp
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public static func placeholder(for timestamp: TimeInterval) -> String {
        let total = max(0, Int(timestamp.isFinite ? timestamp : 0))
        let formatted = total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
        return "Note at \(formatted)"
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel note")

            TextField("", text: $text, prompt: Text(Self.placeholder(for: timestamp)).foregroundStyle(Color(hex: "#A9A2FF").opacity(0.75)))
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(save)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Color(hex: "#262151"), in: Capsule())
                .accessibilityLabel("Note")

            Button(action: save) {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color(hex: "#8B85FF").opacity(canSave ? 1 : 0.45), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .accessibilityLabel("Save note")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(hex: "#2C2C2E"))
        .onAppear { isFocused = true }
    }

    private func save() {
        guard canSave else { return }
        onSave(text)
    }
}
