import SwiftUI

/// Notes & Media tab displaying timestamped notes and whiteboard photo attachments
public struct MeetingNotesMediaTabView: View {
    public let notes: [Note]
    public let onAddNote: () -> Void
    public let onSelectPhoto: (String) -> Void
    
    public init(notes: [Note], onAddNote: @escaping () -> Void, onSelectPhoto: @escaping (String) -> Void) {
        self.notes = notes
        self.onAddNote = onAddNote
        self.onSelectPhoto = onSelectPhoto
    }
    
    private var photoNotes: [Note] { notes.filter { $0.imageAttachmentPath != nil } }
    private var textNotes: [Note] { notes.filter { $0.imageAttachmentPath == nil } }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack {
                    Text("Session Notes & Captures").font(Typography.headline)
                    Spacer()
                    Button(action: onAddNote) {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Note")
                        }
                        .font(Typography.caption)
                    }
                }
                
                if !photoNotes.isEmpty { photoGallerySection }
                
                if textNotes.isEmpty && photoNotes.isEmpty {
                    emptyNotesView
                } else {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(textNotes) { note in
                            noteCard(note)
                        }
                    }
                }
            }
            .padding(Spacing.lg)
        }
    }
    
    private var photoGallerySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Whiteboard & Slide Photos").font(Typography.subheadline).foregroundStyle(Theme.Colors.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(photoNotes) { note in
                        if let path = note.imageAttachmentPath {
                            RoundedRectangle(cornerRadius: Spacing.Radius.md)
                                .fill(Theme.Colors.secondaryBackground)
                                .frame(width: 120, height: 90)
                                .overlay(Image(systemName: "photo").font(.system(size: 28)).foregroundStyle(Theme.Colors.liveBlue))
                                .onTapGesture { onSelectPhoto(path) }
                        }
                    }
                }
            }
        }
    }
    
    private func noteCard(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack {
                if note.isBookmark {
                    Label("Bookmark", systemImage: "bookmark.fill")
                        .font(Typography.caption2).foregroundStyle(Theme.Colors.warmAmber)
                }
                Spacer()
                Text(note.formattedTimestamp).font(Typography.timecode).foregroundStyle(Theme.Colors.textTertiary)
            }
            Text(note.content).font(Typography.body).foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(Spacing.md)
        .background(Theme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md))
    }
    
    private var emptyNotesView: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "note.text").font(.system(size: 32)).foregroundStyle(Theme.Colors.textTertiary)
            Text("No notes or whiteboard photos captured").font(Typography.body)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
