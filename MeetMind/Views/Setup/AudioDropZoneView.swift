import SwiftUI

/// Drop zone button for selecting audio files
public struct AudioDropZoneView: View {
    public var selectedURL: URL?
    public var onSelect: () -> Void
    public var onClear: () -> Void
    
    public init(selectedURL: URL?, onSelect: @escaping () -> Void, onClear: @escaping () -> Void) {
        self.selectedURL = selectedURL
        self.onSelect = onSelect
        self.onClear = onClear
    }
    
    public var body: some View {
        if let url = selectedURL {
            HStack {
                Image(systemName: "doc.badge.waveform")
                    .font(.title2)
                    .foregroundStyle(Theme.Colors.liveBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(Typography.headline)
                        .lineLimit(1)
                    Text("Ready to process")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.Colors.mintGreenDark)
                }
                Spacer()
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .padding(Spacing.lg)
            .background(Theme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md))
        } else {
            Button(action: onSelect) {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.down.doc")
                        .font(.title)
                        .foregroundStyle(Theme.Colors.primarySlate)
                    Text("Choose Audio File")
                        .font(Typography.headline)
                        .foregroundStyle(Theme.Colors.primarySlate)
                    Text("Supported: M4A, MP3, WAV")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xxl)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.Radius.md)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                        .foregroundStyle(Theme.Colors.cardBorder)
                )
            }
            .buttonStyle(.plain)
        }
    }
}
