import Foundation
import SwiftData

@Model
public final class Summary: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var executiveSummary: String
    public var keyPoints: [String]
    public var keyDecisions: [String]
    public var generatedAt: Date
    public var modelVersion: String
    
    // Relationships
    public var meeting: Meeting?
    
    public init(
        id: UUID = UUID(),
        executiveSummary: String,
        keyPoints: [String] = [],
        keyDecisions: [String] = [],
        generatedAt: Date = Date(),
        modelVersion: String = "Apple-NaturalLanguage-Extractive-v1",
        meeting: Meeting? = nil
    ) {
        self.id = id
        self.executiveSummary = executiveSummary
        self.keyPoints = keyPoints
        self.keyDecisions = keyDecisions
        self.generatedAt = generatedAt
        self.modelVersion = modelVersion
        self.meeting = meeting
    }
    
    public var keyPointsCount: Int {
        keyPoints.count
    }
    
    public var keyDecisionsCount: Int {
        keyDecisions.count
    }
    
    public var formattedGeneratedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: generatedAt)
    }
}
