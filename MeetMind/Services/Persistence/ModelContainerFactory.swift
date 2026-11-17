import Foundation
import SwiftData

@MainActor
public final class ModelContainerFactory {
    
    /// Complete canonical schema defining all 8 persistence entities
    public static let schema: Schema = Schema([
        Meeting.self,
        TranscriptSegment.self,
        Speaker.self,
        Summary.self,
        ActionItem.self,
        Note.self,
        Tag.self,
        Folder.self
    ])
    
    /// In-memory container strictly for unit tests and deterministic isolation
    public static func createInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
    
    /// In-memory container pre-populated with realistic preview data for SwiftUI Previews
    public static func createInMemoryContainerWithSampleData() throws -> ModelContainer {
        let container = try createInMemoryContainer()
        SampleDataGenerator.populateSampleData(context: container.mainContext)
        try container.mainContext.save()
        return container
    }
    
    /// Standard production container writing to disk Application Support
    public static func createProductionContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
