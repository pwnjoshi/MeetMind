import PhotosUI
import SwiftUI
import AVFoundation
import UIKit

/// "Attach Photo" sheet (Figma node 161:1234). The person chooses Take Photo (only
/// when a camera exists) or Choose from Library; nothing opens on its own. The
/// photo is pinned to the recording timecode and can carry a caption.
public struct LiveMediaCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let timestamp: TimeInterval
    public var onAttach: (Data, String) -> Void
    @State private var photoData: Data?
    @State private var previewImage: UIImage?
    @State private var caption = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var captureError: String?

    public init(timestamp: TimeInterval, onAttach: @escaping (Data, String) -> Void) {
        self.timestamp = timestamp
        self.onAttach = onAttach
    }

    public init(timestamp: TimeInterval, onCapturePhoto: @escaping (Data) -> Void) {
        self.timestamp = timestamp
        self.onAttach = { data, _ in onCapturePhoto(data) }
    }

    private var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    if previewImage == nil && !isCameraAvailable {
                        Text("No camera is available on this device. Choose a photo from your library.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let previewImage {
                        HStack(spacing: 12) {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 68, height: 68)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Photo")
                                Text("Taken at \(formattedTimecode(timestamp))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if isCameraAvailable {
                            Button("Retake Photo") { Task { await launchCamera() } }
                        }
                    } else {
                        if isCameraAvailable {
                            Button("Take Photo", systemImage: "camera") { Task { await launchCamera() } }
                        }
                    }
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                    }
                }
                Section("Caption") {
                    TextField("Caption", text: $caption)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: "#0B1426"))
            .navigationTitle("Attach Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if let photoData {
                            onAttach(photoData, caption.trimmingCharacters(in: .whitespacesAndNewlines))
                            dismiss()
                        }
                    } label: { Image(systemName: "checkmark") }
                    .disabled(photoData == nil)
                    .accessibilityLabel("Attach photo")
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    do {
                        guard let data = try await newItem.loadTransferable(type: Data.self),
                              let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) else {
                            captureError = "This photo could not be read. Choose another photo."
                            selectedPhotoItem = nil
                            return
                        }
                        setPhoto(jpeg)
                        selectedPhotoItem = nil
                    } catch {
                        captureError = error.localizedDescription
                        selectedPhotoItem = nil
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(hex: "#0B1426"))
        .fullScreenCover(isPresented: $isCameraPresented) {
            MeetingCameraPicker(onCapture: { data in
                isCameraPresented = false
                setPhoto(data)
            }, onCancel: { isCameraPresented = false })
            .ignoresSafeArea()
        }
        .alert("Photo unavailable", isPresented: Binding(get: { captureError != nil }, set: { if !$0 { captureError = nil } })) {
            Button("OK") { captureError = nil }
        } message: { Text(captureError ?? "") }
    }

    private func setPhoto(_ data: Data) {
        photoData = data
        previewImage = UIImage(data: data)
    }

    /// Opens the system camera. When there is no camera (or access is off) the
    /// photo library row stays available as the fallback.
    private func launchCamera() async {
        guard isCameraAvailable else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted {
            captureError = "Allow camera access for Manent in Settings, or choose a photo from the library."
            return
        }
        if status == .notDetermined {
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                captureError = "Allow camera access for Manent in Settings, or choose a photo from the library."
                return
            }
        }
        isCameraPresented = true
    }

    private func formattedTimecode(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.isFinite ? time : 0))
        return String(format: "%02d:%02d", total / 60, total % 60)
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
