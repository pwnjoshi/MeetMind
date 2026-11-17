//
//  FolderTagViewModelTests.swift
//  MeetMindTests
//
//  Created by MeetMind Test Automation.
//

import XCTest
import Foundation
import SwiftData
@testable import MeetMind

@MainActor
final class FolderTagViewModelTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var context: ModelContext!
    private var sut: FolderTagViewModel!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        context = ModelContext(modelContainer)
        sut = FolderTagViewModel(modelContext: context)
    }
    
    @MainActor
    override func tearDown() async throws {
        sut = nil
        context = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    // MARK: - Tier 1: Feature 28 Tests
    
    func test_tier1_feature28_createFolder() throws {
        let folder = sut.createFolder(name: "Engineering", iconName: "folder.fill", colorHex: "#3B82F6")
        XCTAssertEqual(folder.name, "Engineering")
        XCTAssertEqual(folder.colorHex, "#3B82F6")
        XCTAssertTrue(sut.folders.contains(where: { $0.id == folder.id }))
    }
    
    func test_tier1_feature28_createTag() throws {
        let tag = sut.createTag(name: "Sprint 42", colorHex: "#10B981")
        XCTAssertEqual(tag.name, "Sprint 42")
        XCTAssertEqual(tag.colorHex, "#10B981")
        XCTAssertTrue(sut.tags.contains(where: { $0.id == tag.id }))
    }
    
    func test_tier1_feature28_assignFolderToMeeting() throws {
        let folder = sut.createFolder(name: "Marketing")
        let meeting = Meeting(title: "Brand Review")
        context.insert(meeting)
        try? context.save()
        
        sut.assignFolder(folder, to: meeting)
        XCTAssertEqual(meeting.folder?.id, folder.id)
        XCTAssertEqual(folder.meetingCount, 1)
    }
    
    func test_tier1_feature28_addAndRemoveTag() throws {
        let tag = sut.createTag(name: "Urgent")
        let meeting = Meeting(title: "Emergency Sync")
        context.insert(meeting)
        try? context.save()
        
        sut.addTag(tag, to: meeting)
        XCTAssertTrue(meeting.tags.contains(where: { $0.id == tag.id }))
        XCTAssertEqual(tag.meetingCount, 1)
        
        sut.removeTag(tag, from: meeting)
        XCTAssertFalse(meeting.tags.contains(where: { $0.id == tag.id }))
        XCTAssertEqual(tag.meetingCount, 0)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases
    
    func test_tier2_feature28_duplicateFolderNamePrevention() throws {
        let f1 = sut.createFolder(name: "Finance")
        let f2 = sut.createFolder(name: "Finance")
        XCTAssertEqual(f1.id, f2.id)
        XCTAssertEqual(sut.folders.filter { $0.name == "Finance" }.count, 1)
    }
    
    func test_tier2_feature28_duplicateTagNamePrevention() throws {
        let t1 = sut.createTag(name: "Design")
        let t2 = sut.createTag(name: "Design")
        XCTAssertEqual(t1.id, t2.id)
        XCTAssertEqual(sut.tags.filter { $0.name == "Design" }.count, 1)
    }
    
    func test_tier2_feature28_deleteFolderNullifiesChildMeetings() throws {
        let folder = sut.createFolder(name: "Ephemeral")
        let meeting = Meeting(title: "Survivor Meeting")
        context.insert(meeting)
        sut.assignFolder(folder, to: meeting)
        XCTAssertEqual(meeting.folder?.id, folder.id)
        
        sut.deleteFolder(folder)
        XCTAssertNil(meeting.folder)
        XCTAssertFalse(sut.folders.contains(where: { $0.id == folder.id }))
    }
    
    func test_tier2_feature28_deleteTagNullifiesMeetingAssociation() throws {
        let tag = sut.createTag(name: "TemporaryTag")
        let meeting = Meeting(title: "Tagged Meeting")
        context.insert(meeting)
        sut.addTag(tag, to: meeting)
        XCTAssertTrue(meeting.tags.contains(where: { $0.id == tag.id }))
        
        sut.deleteTag(tag)
        XCTAssertFalse(meeting.tags.contains(where: { $0.id == tag.id }))
        XCTAssertFalse(sut.tags.contains(where: { $0.id == tag.id }))
    }
}
