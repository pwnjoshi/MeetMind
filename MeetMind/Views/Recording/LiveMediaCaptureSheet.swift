import PhotosUI
import SwiftUI
import AVFoundation
import UIKit

/// Sheet modal to capture or select whiteboard photos pinned to recording timecode
public struct LiveMediaCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let timestamp: TimeInterval
    public var onCapturePhoto: (Data) -> Void
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var captureError: String?
    
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
                        Task {
                            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                                captureError = "A camera is not available on this device. Choose a photo from the library."
                                return
                            }
                            if await AVCaptureDevice.requestAccess(for: .video) {
                                isCameraPresented = true
                            } else {
                                captureError = "Enable camera access for MeetMind in Settings, or choose a photo from the library."
                            }
                        }
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
                    do {
                        guard let data = try await newItem.loadTransferable(type: Data.self),
                              let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) else {
                            captureError = "This photo could not be read. Choose another photo."
                            return
                        }
                        onCapturePhoto(jpeg)
                        dismiss()
                    } catch { captureError = error.localizedDescription }
                }
            }
        }
        .presentationDetents([.medium])
        .fullScreenCover(isPresented: $isCameraPresented) {
            MeetingCameraPicker(onCapture: { data in
                isCameraPresented = false
                onCapturePhoto(data)
                dismiss()
            }, onCancel: { isCameraPresented = false })
            .ignoresSafeArea()
        }
        .alert("Photo unavailable", isPresented: Binding(get: { captureError != nil }, set: { if !$0 { captureError = nil } })) {
            Button("OK") { captureError = nil }
        } message: { Text(captureError ?? "") }
    }
    
    private func formattedTimecode(_ time: TimeInterval) -> String {
        let total = Int(time)
        return String(format: "%02d:%02d", (total % 3600) / 60, total % 60)
    }
}

private struct MeetingCameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    let onCancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MeetingCameraPicker
        init(parent: MeetingCameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.85) {
                parent.onCapture(data)
            } else { parent.onCancel() }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
    }
}
