import PhotosUI
import SwiftUI

/// Sheet modal to capture or select whiteboard photos pinned to recording timecode
public struct LiveMediaCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let timestamp: TimeInterval
    public var onCapturePhoto: (Data) -> Void
    @State private var selectedPhotoItem: PhotosPickerItem?
    
    public init(timestamp: TimeInterval, onCapturePhoto: @escaping (Data) -> Void) {
        self.timestamp = timestamp
        self.onCapturePhoto = onCapturePhoto
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                    Text("Timecode: \(formattedTimecode(timestamp))").font(Typography.timecode)
                }
                .foregroundStyle(Theme.Colors.mintGreen)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.Colors.mintGreenLight)
                .clipShape(Capsule())
                
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.Colors.cardBackground)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.cardBorder, lineWidth: 1))
                        .frame(height: 150)
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder").font(.system(size: 40)).foregroundStyle(Theme.Colors.textSecondary)
                        Text("Attach a Whiteboard or Slide Photo").font(Typography.subheadline).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, Spacing.md)
                
                VStack(spacing: Spacing.sm) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text("Choose from Library")
                        }
                        .font(Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.Colors.liveBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Button {
                        let sampleData = "MEETMIND_WHITEBOARD_SNAPSHOT".data(using: .utf8) ?? Data()
                        onCapturePhoto(sampleData)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Capture Camera Snapshot")
                        }
                        .font(Typography.subheadline)
                        .foregroundStyle(Theme.Colors.liveBlue)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.Colors.liveBlueLight)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, Spacing.md)
                Spacer()
            }
            .padding(.top, Spacing.lg)
            .navigationTitle("Whiteboard Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        await MainActor.run { onCapturePhoto(data); dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private func formattedTimecode(_ time: TimeInterval) -> String {
        let total = Int(time)
        return String(format: "%02d:%02d", (total % 3600) / 60, total % 60)
    }
}
