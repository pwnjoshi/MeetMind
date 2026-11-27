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
    
    
    /// Standard production container writing to disk Application Support
    public static func createProductionContainer() throws -> ModelContainer {
        // Exclude both current and newly created local meeting files from device
        // backups. Explicit user exports remain separate actions.
        for location in [FileManager.SearchPathDirectory.documentDirectory, .applicationSupportDirectory] {
            var directory = FileManager.default.urls(for: location, in: .userDomainMask)[0]
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
        }
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
