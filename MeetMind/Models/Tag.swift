import Foundation
import SwiftData

@Model
public final class Tag: Identifiable {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var name: String
    public var colorHex: String
    
    // Relationships
    @Relationship(deleteRule: .nullify)
    public var meetings: [Meeting]
    
    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#8B5CF6"
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.meetings = []
    }
    
    public var meetingCount: Int {
        meetings.count
    }
}
