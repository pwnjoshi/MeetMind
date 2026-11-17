//
//  AudioImportViewModelTests.swift
//  MeetMindTests
//
//  Created by MeetMind Test Automation.
//

import XCTest
import Foundation
import SwiftData
@testable import MeetMind

final class AudioImportViewModelTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var context: ModelContext!
    private var sut: AudioImportViewModel!
    private var tempDirectoryURL: URL!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        context = ModelContext(modelContainer)
        sut = AudioImportViewModel(modelContext: context)
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }
    
    @MainActor
    override func tearDown() async throws {
        sut = nil
        context = nil
        modelContainer = nil
        if let temp = tempDirectoryURL {
            try? FileManager.default.removeItem(at: temp)
        }
        try await super.tearDown()
    }
    
    // MARK: - Tier 1: Feature 27 Tests
    
    func test_tier1_feature27_acceptedExtensions() throws {
        XCTAssertTrue(sut.isExtensionSupported("m4a"))
        XCTAssertTrue(sut.isExtensionSupported("mp3"))
        XCTAssertTrue(sut.isExtensionSupported("wav"))
        XCTAssertFalse(sut.isExtensionSupported("txt"))
        XCTAssertFalse(sut.isExtensionSupported("pdf"))
        XCTAssertFalse(sut.isExtensionSupported("docx"))
    }
    
    func test_tier1_feature27_validFileImportSucceeds() async throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("valid.m4a")
        try Data("audio_data_sample".utf8).write(to: fileURL)
        sut.simulatedDuration = 240.0
        
        let meeting = try await sut.importAudio(from: fileURL, title: "Executive Briefing")
        XCTAssertEqual(meeting.title, "Executive Briefing")
        XCTAssertEqual(meeting.status, .processing)
        XCTAssertEqual(meeting.duration, 240.0)
        XCTAssertEqual(meeting.audioFileURL, fileURL)
    }
    
    func test_tier1_feature27_defaultTitleFromFilename() async throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("weekly_sync.mp3")
        try Data("audio_bytes".utf8).write(to: fileURL)
        
        let meeting = try await sut.importAudio(from: fileURL)
        XCTAssertEqual(meeting.title, "weekly_sync")
        XCTAssertEqual(meeting.status, .processing)
    }
    
    func test_tier1_feature27_resetClearsState() throws {
        sut.isImporting = true
        sut.importProgress = 0.5
        sut.errorMessage = "Some error"
        sut.hasError = true
        
        sut.reset()
        XCTAssertFalse(sut.isImporting)
        XCTAssertEqual(sut.importProgress, 0.0)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.hasError)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases
    
    func test_tier2_feature27_unsupportedExtensionThrows() async throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("document.pdf")
        try Data("pdf_bytes".utf8).write(to: fileURL)
        
        do {
            _ = try await sut.importAudio(from: fileURL)
            XCTFail("Should throw unsupportedFormat")
        } catch {
            XCTAssertEqual(error as? AudioImportError, .unsupportedFormat)
            XCTAssertTrue(sut.hasError)
        }
    }
    
    func test_tier2_feature27_zeroByteFileThrowsEmptyFile() async throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("zero.wav")
        try Data().write(to: fileURL)
        
        do {
            _ = try await sut.importAudio(from: fileURL)
            XCTFail("Should throw emptyFile")
        } catch {
            XCTAssertEqual(error as? AudioImportError, .emptyFile)
            XCTAssertTrue(sut.hasError)
        }
    }
    
    func test_tier2_feature27_corruptedFileSimulationThrows() async throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("corrupt.m4a")
        try Data("bad_header".utf8).write(to: fileURL)
        sut.shouldSimulateCorruptFile = true
        
        do {
            _ = try await sut.importAudio(from: fileURL)
            XCTFail("Should throw corruptedFile")
        } catch {
            XCTAssertEqual(error as? AudioImportError, .corruptedFile)
            XCTAssertTrue(sut.hasError)
        }
    }
    
    func test_remediation_zeroOrNegativeDurationThrowsInvalidDuration() async throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("zero_len.m4a")
        try Data("audio_bytes".utf8).write(to: fileURL)
        sut.simulatedDuration = 0.0
        
        do {
            _ = try await sut.importAudio(from: fileURL)
            XCTFail("Should throw invalidDuration")
        } catch {
            XCTAssertEqual(error as? AudioImportError, .invalidDuration)
            XCTAssertTrue(sut.hasError)
        }
    }
    
    func test_remediation_nonExistentFileThrows() async throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("non_existent.m4a")
        
        do {
            _ = try await sut.importAudio(from: fileURL)
            XCTFail("Should throw file not found")
        } catch {
            XCTAssertEqual(error as? AudioImportError, .corruptedFile)
            XCTAssertTrue(sut.hasError)
        }
    }
}
