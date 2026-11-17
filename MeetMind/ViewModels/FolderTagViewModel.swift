import Foundation
import SwiftData
import Observation

/// ViewModel managing folder and tag organization, CRUD operations, and meeting categorization
@Observable
@MainActor
public final class FolderTagViewModel {
    public var folders: [Folder] = []
    public var tags: [Tag] = []
    
    public var newFolderName: String = ""
    public var newFolderColorHex: String = "#3B82F6"
    public var newFolderIconName: String = "folder.fill"
    
    public var newTagName: String = ""
    public var newTagColorHex: String = "#8B5CF6"
    
    public var errorMessage: String? = nil
    
    private var modelContext: ModelContext?
    
    public init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        if modelContext == nil {
            if let container = try? ModelContainerFactory.createInMemoryContainer() {
                self.modelContext = container.mainContext
            }
        }
        fetchFoldersAndTags()
    }
    
    public func fetchFoldersAndTags() {
        guard let context = modelContext else { return }
        
        let folderDescriptor = FetchDescriptor<Folder>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        if let fetchedFolders = try? context.fetch(folderDescriptor) {
            self.folders = fetchedFolders
        }
        
        let tagDescriptor = FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.name, order: .forward)])
        if let fetchedTags = try? context.fetch(tagDescriptor) {
            self.tags = fetchedTags
        }
    }
    
    @discardableResult
    public func createFolder(name: String, iconName: String = "folder.fill", colorHex: String = "#3B82F6") -> Folder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = folders.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        
        let folder = Folder(name: trimmed, iconName: iconName, colorHex: colorHex)
        if let context = modelContext {
            context.insert(folder)
            try? context.save()
        }
        folders.append(folder)
        newFolderName = ""
        return folder
    }
    
    public func deleteFolder(_ folder: Folder) {
        for m in folder.meetings {
            m.folder = nil
        }
        folder.meetings.removeAll()
        
        if let context = modelContext {
            context.delete(folder)
            try? context.save()
        }
        folders.removeAll { $0.id == folder.id }
    }
    
    @discardableResult
    public func createTag(name: String, colorHex: String = "#8B5CF6") -> Tag {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = tags.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        
        let tag = Tag(name: trimmed, colorHex: colorHex)
        if let context = modelContext {
            context.insert(tag)
            try? context.save()
        }
        tags.append(tag)
        newTagName = ""
        return tag
    }
    
    public func deleteTag(_ tag: Tag) {
        for m in tag.meetings {
            m.tags.removeAll { $0.id == tag.id }
        }
        tag.meetings.removeAll()
        
        if let context = modelContext {
            context.delete(tag)
            try? context.save()
        }
        tags.removeAll { $0.id == tag.id }
    }
    
    public func assignFolder(_ folder: Folder?, to meeting: Meeting) {
        if let oldFolder = meeting.folder {
            oldFolder.meetings.removeAll { $0.id == meeting.id }
        }
        meeting.folder = folder
        if let folder = folder, !folder.meetings.contains(where: { $0.id == meeting.id }) {
            folder.meetings.append(meeting)
        }
        try? modelContext?.save()
    }
    
    public func addTag(_ tag: Tag, to meeting: Meeting) {
        if !meeting.tags.contains(where: { $0.id == tag.id }) {
            meeting.tags.append(tag)
        }
        if !tag.meetings.contains(where: { $0.id == meeting.id }) {
            tag.meetings.append(meeting)
        }
        try? modelContext?.save()
    }
    
    public func removeTag(_ tag: Tag, from meeting: Meeting) {
        meeting.tags.removeAll { $0.id == tag.id }
        tag.meetings.removeAll { $0.id == meeting.id }
        try? modelContext?.save()
    }
    
    public func toggleTag(_ tag: Tag, for meeting: Meeting) {
        if meeting.tags.contains(where: { $0.id == tag.id }) {
            removeTag(tag, from: meeting)
        } else {
            addTag(tag, to: meeting)
        }
    }
}
