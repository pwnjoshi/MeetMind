import SwiftUI
import UIKit
import ImageIO

/// Live "Notes & photos" list for the recording page. It shows every note and photo
/// captured in this recording (newest first) with its recording timecode. Notes and
/// captions can be edited, items can be deleted, and a photo opens full screen.
struct LiveCapturesPanel: View {
    let items: [LiveCaptureItem]
    let onEdit: (UUID, String) -> Void
    let onDelete: (UUID) -> Void

    @State private var editingID: UUID?
    @State private var editText = ""
    @State private var viewingPhoto: LiveCaptureItem?

    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.58))
                    Text("No notes or photos yet")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.76))
                    Text("Notes and photos you add while recording appear here.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(items) { item in
                            row(for: item)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .alert(editTitle, isPresented: Binding(
            get: { editingID != nil },
            set: { if !$0 { editingID = nil } }
        )) {
            TextField("Text", text: $editText)
            Button("Cancel", role: .cancel) { editingID = nil }
            Button("Save") {
                if let id = editingID { onEdit(id, editText) }
                editingID = nil
            }
        }
        .fullScreenCover(item: $viewingPhoto) { item in
            LiveCapturePhotoViewer(item: item)
        }
    }

    private var editTitle: String {
        if let id = editingID, items.first(where: { $0.id == id })?.kind == .photo {
            return "Edit Caption"
        }
        return "Edit Note"
    }

    private func row(for item: LiveCaptureItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                if item.kind == .photo { viewingPhoto = item } else { beginEditing(item) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    leading(for: item)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(item.kind == .photo ? "Photo" : "Note") \u{00B7} \(LiveCaptureTime.format(item.timestamp))")
                            .font(.caption)
                            .foregroundStyle(Color(hex: "#8CC8FF").opacity(0.85))
                        Text(displayText(for: item))
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.92))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(item.kind == .photo ? "Opens the photo full screen" : "Edits the note")

            Menu {
                Button(item.kind == .photo ? "Edit Caption" : "Edit Note", systemImage: "pencil") {
                    beginEditing(item)
                }
                Button("Delete", systemImage: "trash", role: .destructive) { onDelete(item.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(item.kind == .photo ? "Photo options" : "Note options")
        }
    }

    @ViewBuilder
    private func leading(for item: LiveCaptureItem) -> some View {
        if item.kind == .photo, let url = item.photoURL {
            LiveCaptureThumbnail(url: url)
        } else {
            Image(systemName: "text.bubble")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: "#8CC8FF"))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func displayText(for item: LiveCaptureItem) -> String {
        if item.kind == .photo && item.text.isEmpty { return "Tap to view" }
        return item.text
    }

    private func beginEditing(_ item: LiveCaptureItem) {
        editText = item.text
        editingID = item.id
    }
}

private enum LiveCaptureTime {
    static func format(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.isFinite ? time : 0))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private enum LiveCaptureImageLoader {
    static func load(_ url: URL, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

private struct LiveCaptureThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.08)
                    .overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.5)))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
        .task(id: url) {
            image = LiveCaptureImageLoader.load(url, maxPixel: 200)
        }
    }
}

private struct LiveCapturePhotoViewer: View {
    let item: LiveCaptureItem
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(item.text.isEmpty ? "Photo" : item.text)
                } else {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                VStack(spacing: 4) {
                    if !item.text.isEmpty {
                        Text(item.text)
                            .font(.body)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                    Text("Photo \u{00B7} \(LiveCaptureTime.format(item.timestamp))")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(16)
            .accessibilityLabel("Close photo")
        }
        .preferredColorScheme(.dark)
        .task(id: item.id) {
            if let url = item.photoURL {
                image = LiveCaptureImageLoader.load(url, maxPixel: 2400)
            }
        }
    }
}
