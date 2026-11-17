import Foundation
import SwiftData

@Model
public final class Folder: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var iconName: String
    public var colorHex: String
    public var createdAt: Date
    
    // Relationships
    @Relationship(deleteRule: .nullify)
    public var meetings: [Meeting]
    
    public init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "folder.fill",
        colorHex: String = "#3B82F6",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.meetings = []
    }
    
    public var meetingCount: Int {
        meetings.count
    }
}
