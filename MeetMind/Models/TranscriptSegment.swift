import Foundation
import SwiftData

@Model
public final class TranscriptSegment {
    @Attribute(.unique) public var id: UUID
    public var text: String
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var confidence: Float
    public var isEdited: Bool
    
    // Relationships
    public var meeting: Meeting?
    
    @Relationship(deleteRule: .nullify, inverse: \Speaker.transcriptSegments)
    public var speaker: Speaker?
    
    public init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float = 1.0,
        isEdited: Bool = false,
        speaker: Speaker? = nil,
        meeting: Meeting? = nil
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.isEdited = isEdited
        self.speaker = speaker
        self.meeting = meeting
    }
    
    public var duration: TimeInterval {
        max(0, endTime - startTime)
    }
    
    public var formattedStartTime: String {
        let totalSeconds = Int(startTime)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    public var formattedEndTime: String {
        let totalSeconds = Int(endTime)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    public var formattedTimeRange: String {
        "\(formattedStartTime) - \(formattedEndTime)"
    }
    
    public var speakerDisplayName: String {
        speaker?.name ?? "Unknown Speaker"
    }
    
    public var speakerName: String {
        speaker?.name ?? "Speaker 1"
    }
    
    public func updateText(_ newText: String) {
        self.text = newText
        self.isEdited = true
    }
}
