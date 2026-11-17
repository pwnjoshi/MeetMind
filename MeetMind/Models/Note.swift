import Foundation
import SwiftData

@Model
public final class Note {
    @Attribute(.unique) public var id: UUID
    public var content: String
    public var timestamp: TimeInterval
    public var createdAt: Date
    public var imageAttachmentPath: String?
    public var isBookmark: Bool
    
    // Relationships
    public var meeting: Meeting?
    
    public init(
        id: UUID = UUID(),
        content: String,
        timestamp: TimeInterval = 0,
        createdAt: Date = Date(),
        imageAttachmentPath: String? = nil,
        isBookmark: Bool = false,
        meeting: Meeting? = nil
    ) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.createdAt = createdAt
        self.imageAttachmentPath = imageAttachmentPath
        self.isBookmark = isBookmark
        self.meeting = meeting
    }
    
    public var formattedTimestamp: String {
        let totalSeconds = Int(timestamp)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    public var hasImage: Bool {
        imageAttachmentPath != nil
    }
}
