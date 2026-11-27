import SwiftUI
import UIKit
import ImageIO

/// Live "Notes & photos" list for the recording page. Photos appear in a grid with a
/// timecode overlay and notes in a list below it (newest first). Notes and captions
/// can be edited, items can be deleted, and a photo opens full screen.
struct LiveCapturesPanel: View {
    let items: [LiveCaptureItem]
    let onEdit: (UUID, String) -> Void
    let onDelete: (UUID) -> Void

    @State private var editingID: UUID?
    @State private var editText = ""
    @State private var viewingPhoto: LiveCaptureItem?

    private let gridColumns = [GridItem(.adaptive(minimum: 88), spacing: 8)]

    private var photos: [LiveCaptureItem] { items.filter { $0.kind == .photo && $0.photoURL != nil } }
    private var notes: [LiveCaptureItem] { items.filter { $0.kind == .note } }

    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Notes and photos you add appear here")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .accessibilityElement(children: .combine)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !photos.isEmpty {
                            LazyVGrid(columns: gridColumns, spacing: 8) {
                                ForEach(photos) { item in
                                    photoTile(for: item)
                                }
                            }
                        }
                        ForEach(notes) { item in
                            noteRow(for: item)
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

    private func photoTile(for item: LiveCaptureItem) -> some View {
        Button {
            viewingPhoto = item
        } label: {
            ZStack(alignment: .bottomLeading) {
                if let url = item.photoURL {
                    LiveCaptureThumbnail(url: url)
                }
                Text(LiveCaptureTime.format(item.timestamp))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(6)
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.75))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit Caption", systemImage: "pencil") { beginEditing(item) }
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete(item.id) }
        }
        .accessibilityLabel(item.text.isEmpty
            ? "Photo at \(LiveCaptureTime.format(item.timestamp))"
            : "Photo at \(LiveCaptureTime.format(item.timestamp)), \(item.text)")
        .accessibilityHint("Opens the photo full screen")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Edit caption") { beginEditing(item) }
        .accessibilityAction(named: "Delete") { onDelete(item.id) }
    }

    private func noteRow(for item: LiveCaptureItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                beginEditing(item)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Note \u{00B7} \(LiveCaptureTime.format(item.timestamp))")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#8CC8FF").opacity(0.85))
                    Text(item.text)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Edits the note")

            Menu {
                Button("Edit Note", systemImage: "pencil") { beginEditing(item) }
                Button("Delete", systemImage: "trash", role: .destructive) { onDelete(item.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Note options")
        }
        .padding(.leading, 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.75))
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
        Color.white.opacity(0.08)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(.white.opacity(0.5))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
        .task(id: url) {
            image = LiveCaptureImageLoader.load(url, maxPixel: 320)
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
