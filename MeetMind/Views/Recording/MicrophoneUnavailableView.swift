import SwiftUI
import UIKit

/// "Microphone Unavailable" (Figma node 161:1151). Offers local alternatives to
/// recording: writing notes without audio, or importing audio saved in Files.
public struct MicrophoneUnavailableView: View {
    @Environment(\.openURL) private var openURL

    public let onBack: () -> Void
    public let onTryAgain: () -> Void
    public let onTakeNotes: () -> Void
    public let onImportRecording: (() -> Void)?

    public init(
        onBack: @escaping () -> Void,
        onTryAgain: @escaping () -> Void,
        onTakeNotes: @escaping () -> Void,
        onImportRecording: (() -> Void)? = nil
    ) {
        self.onBack = onBack
        self.onTryAgain = onTryAgain
        self.onTakeNotes = onTakeNotes
        self.onImportRecording = onImportRecording
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
            }
            .accessibilityLabel("Back")
            .padding(.top, 8)

            VStack(spacing: 12) {
                Image(systemName: "mic.slash")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Microphone Unavailable")
                    .font(.title3.weight(.bold))
                Text("Allow microphone access in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 28)

            Text("Other Options")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 56)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                optionRow("Take Notes Instead", "Write minutes without recording audio", action: onTakeNotes)
                if let onImportRecording {
                    Divider().padding(.leading, 16)
                    optionRow("Import a Recording", "Use audio saved in Files", action: onImportRecording)
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            Spacer(minLength: 24)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Text("Open Settings").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Theme.Colors.manentAccent)

            Button("Try Again", action: onTryAgain)
                .foregroundStyle(Theme.Colors.manentAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    private func optionRow(_ title: String, _ subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundStyle(.primary)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
