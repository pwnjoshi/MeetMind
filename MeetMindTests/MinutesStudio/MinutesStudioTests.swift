import XCTest
import Foundation
import PDFKit
@testable import MeetMind

@MainActor
final class MinutesStudioTests: XCTestCase {
    private var cachedRoot: URL?

    private var tempDirectory: URL {
        if let cachedRoot { return cachedRoot }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MinutesStudioTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        cachedRoot = url
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeStore() -> MinutesStudioStore {
        MinutesStudioStore(directory: tempDirectory.appendingPathComponent("store", isDirectory: true))
    }

    private func makeFile(named name: String, contents: String = "data") throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try contents.data(using: .utf8)?.write(to: url)
        return url
    }

    private func snapshot(
        participants: [MinutesParticipant] = [],
        absent: [UUID] = [],
        agenda: String? = nil
    ) -> MinutesMeetingSnapshot {
        MinutesMeetingSnapshot(
            meetingID: UUID(),
            title: "October planning",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            agenda: agenda,
            participants: participants,
            defaultAbsentIDs: absent,
            discussion: ["One", "Two", "Three", "Four"],
            decisions: ["Ship in October"],
            actionItems: [MinutesActionLine(title: "Book venue", owner: "Pawan Joshi", due: nil)],
            isFinalized: true
        )
    }

    // MARK: Config encoding

    func testConfigRoundTripsThroughJSON() throws {
        var config = MinutesStudioConfig.standard()
        config.meetingType = .society
        config.format = .briefNote
        config.letterheadID = UUID().uuidString
        config.organisationName = "Lake View RWA"
        config.attendance[UUID().uuidString] = .leaveGranted
        config.setEnabled(.signature, true)

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MinutesStudioConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testStandardConfigMatchesFigmaDefaults() {
        let config = MinutesStudioConfig.standard()
        XCTAssertEqual(config.templateID, "projectReview")
        XCTAssertEqual(config.format, .corporateStandard)
        XCTAssertEqual(config.enabledSections.count, 6)
        XCTAssertFalse(config.isEnabled(.previousMinutes))
        XCTAssertTrue(config.isEnabled(.participantNames))
    }

    // MARK: Section selection

    func testOrderedEnabledSectionsFollowsOrderAndSkipsDisabled() {
        var config = MinutesStudioConfig.standard()
        config.sectionOrder = [.decisions, .actionItems, .attendance]
        let ordered = config.orderedEnabledSections
        XCTAssertEqual(Array(ordered.prefix(3)), [.decisions, .actionItems, .attendance])
        XCTAssertFalse(ordered.contains(.signature))
        XCTAssertEqual(Set(ordered), Set(config.enabledSections))
    }

    func testSetEnabledDoesNotDuplicate() {
        var config = MinutesStudioConfig.standard()
        config.setEnabled(.signature, true)
        config.setEnabled(.signature, true)
        XCTAssertEqual(config.enabledSections.filter { $0 == .signature }.count, 1)
        config.setEnabled(.signature, false)
        XCTAssertFalse(config.isEnabled(.signature))
    }

    func testApplyTemplateKeepsLetterheadAndAttendance() {
        var config = MinutesStudioConfig.standard()
        config.letterheadID = "office"
        let id = UUID().uuidString
        config.attendance[id] = .presentByVideo
        let board = MinutesBuiltInTemplate.boardProceedings
        config.applyTemplate(id: board.rawValue, format: board.defaultFormat, sections: board.defaultSections)
        XCTAssertEqual(config.letterheadID, "office")
        XCTAssertEqual(config.attendance[id], .presentByVideo)
        XCTAssertTrue(config.isEnabled(.signature))
        XCTAssertTrue(config.isEnabled(.previousMinutes))
    }

    // MARK: Store

    func testStorePersistsConfigPerMeeting() {
        let meetingID = UUID()
        var config = MinutesStudioConfig.standard()
        config.format = .officeActionRecord
        let store = makeStore()
        XCTAssertNil(store.config(for: meetingID))
        store.save(config, for: meetingID)

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.config(for: meetingID)?.format, .officeActionRecord)
        XCTAssertNil(reloaded.config(for: UUID()))
    }

    func testSaveCurrentSetupStoresTemplateAndRejectsEmptyName() throws {
        let store = makeStore()
        var config = MinutesStudioConfig.standard()
        config.format = .briefNote
        let template = try store.saveCurrentSetup(named: "  Weekly sync  ", from: config)
        XCTAssertEqual(template.name, "Weekly sync")
        XCTAssertEqual(template.kind, .savedSetup)
        XCTAssertEqual(store.templateName(for: template.id.uuidString), "Weekly sync")
        XCTAssertEqual(makeStore().templates.count, 1)
        XCTAssertThrowsError(try store.saveCurrentSetup(named: "   ", from: config)) {
            XCTAssertEqual($0 as? MinutesStudioError, .emptyName)
        }
    }

    func testImportTemplatePDFCopiesFileAndUsesStandardStructure() throws {
        let store = makeStore()
        let source = try makeFile(named: "Board Format.pdf")
        let template = try store.importTemplatePDF(from: source)
        XCTAssertEqual(template.name, "Board Format")
        XCTAssertEqual(template.kind, .importedPDF)
        XCTAssertEqual(template.enabledSections, MinutesBuiltInTemplate.projectReview.defaultSections)
        let stored = try XCTUnwrap(store.templateFileURL(template))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path))

        store.deleteTemplate(id: template.id)
        XCTAssertTrue(store.templates.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.path))
    }

    func testImportTemplateRejectsNonPDF() throws {
        let store = makeStore()
        let source = try makeFile(named: "notes.txt")
        XCTAssertThrowsError(try store.importTemplatePDF(from: source)) {
            XCTAssertEqual($0 as? MinutesStudioError, .notAPDF)
        }
        XCTAssertTrue(store.templates.isEmpty)
    }

    func testLetterheadImportAndDelete() throws {
        let store = makeStore()
        let source = try makeFile(named: "header.png")
        let letterhead = try store.addLetterhead(from: source)
        XCTAssertEqual(letterhead.name, "header")
        XCTAssertFalse(letterhead.isPDF)
        XCTAssertEqual(store.letterheadName(for: letterhead.id.uuidString), "header")
        let stored = store.letterheadFileURL(letterhead)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path))

        let pdf = try store.addLetterhead(from: try makeFile(named: "head.pdf"))
        XCTAssertTrue(pdf.isPDF)

        store.deleteLetterhead(id: letterhead.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.path))
        XCTAssertEqual(store.letterheads.count, 1)
    }

    func testLetterheadFromImageDataRequiresNameAndData() throws {
        let store = makeStore()
        XCTAssertThrowsError(try store.addLetterhead(imageData: Data([1, 2]), fileExtension: "jpg", name: " "))
        XCTAssertThrowsError(try store.addLetterhead(imageData: Data(), fileExtension: "jpg", name: "Photo"))
        let added = try store.addLetterhead(imageData: Data([1, 2, 3]), fileExtension: "JPG", name: "Photo")
        XCTAssertTrue(added.fileName.hasSuffix(".jpg"))
    }

    func testBuiltInNamesFallBackWhenCustomItemMissing() {
        let store = makeStore()
        XCTAssertEqual(store.templateName(for: "boardProceedings"), "Board proceedings")
        XCTAssertEqual(store.templateName(for: UUID().uuidString), "Project review")
        XCTAssertEqual(store.letterheadName(for: UUID().uuidString), "Plain")
    }

    // MARK: Attendance and document

    func testAttendanceDefaultsFromMeetingAbsentList() {
        let absentID = UUID()
        let otherID = UUID()
        let config = MinutesStudioConfig.standard()
        XCTAssertEqual(MinutesDocumentBuilder.status(for: absentID, config: config, defaultAbsentIDs: [absentID]), .absent)
        XCTAssertEqual(MinutesDocumentBuilder.status(for: otherID, config: config, defaultAbsentIDs: [absentID]), .unconfirmed)
    }

    func testStoredStatusOverridesDefaultAndAbsentIDsFollowIt() {
        let a = MinutesParticipant(id: UUID(), name: "Asha", role: nil)
        let b = MinutesParticipant(id: UUID(), name: "Ben", role: nil)
        let c = MinutesParticipant(id: UUID(), name: "Chitra", role: nil)
        let data = snapshot(participants: [a, b, c], absent: [a.id])
        var config = MinutesStudioConfig.standard()
        config.attendance[a.id.uuidString] = .presentInPerson
        config.attendance[b.id.uuidString] = .leaveGranted
        config.attendance[c.id.uuidString] = .apologyReceived

        XCTAssertEqual(Set(MinutesDocumentBuilder.absentIDs(snapshot: data, config: config)), [b.id, c.id])
        XCTAssertEqual(MinutesDocumentBuilder.confirmedCount(snapshot: data, config: config), 3)
        XCTAssertEqual(MinutesDocumentBuilder.confirmedCount(snapshot: data, config: .standard()), 1)
    }

    func testDocumentListsPresentAndAbsentPeople() throws {
        let a = MinutesParticipant(id: UUID(), name: "Dr. Sachin Ghai", role: nil)
        let b = MinutesParticipant(id: UUID(), name: "Pawan Joshi", role: nil)
        let c = MinutesParticipant(id: UUID(), name: "Garima Pant", role: "Invitee")
        var config = MinutesStudioConfig.standard()
        config.attendance[a.id.uuidString] = .presentInPerson
        config.attendance[b.id.uuidString] = .presentByVideo
        let doc = MinutesDocumentBuilder.build(
            snapshot: snapshot(participants: [a, b, c], agenda: "Launch timing and budget"),
            config: config,
            templateName: "Project review",
            documentHeading: "Minutes of meeting"
        )
        XCTAssertEqual(doc.setupLine, "Project review · Corporate standard")
        XCTAssertEqual(doc.statusLabel, "Finalized")
        XCTAssertEqual(doc.blocks.first?.heading, "Agenda")
        let present = try XCTUnwrap(doc.blocks.first { $0.id == "attendance" })
        XCTAssertEqual(present.lines, ["Dr. Sachin Ghai · Present in person", "Pawan Joshi · Present by video"])
        let absences = try XCTUnwrap(doc.blocks.first { $0.id == "absences" })
        XCTAssertEqual(absences.lines, ["No confirmed absences or leave recorded."])
    }

    func testDisabledSectionsAreOmittedAndNamesCanBeHidden() throws {
        let a = MinutesParticipant(id: UUID(), name: "Asha", role: nil)
        var config = MinutesStudioConfig.standard()
        config.attendance[a.id.uuidString] = .presentInPerson
        config.setEnabled(.decisions, false)
        config.setEnabled(.participantNames, false)
        let doc = MinutesDocumentBuilder.build(
            snapshot: snapshot(participants: [a]),
            config: config,
            templateName: "Project review",
            documentHeading: "Minutes of meeting"
        )
        XCTAssertNil(doc.blocks.first { $0.id == "decisions" })
        XCTAssertNil(doc.blocks.first { $0.id == "participantNames" })
        let present = try XCTUnwrap(doc.blocks.first { $0.id == "attendance" })
        XCTAssertEqual(present.lines, ["1 present"])
        XCTAssertFalse(doc.blocks.contains { $0.lines.contains { $0.contains("Asha") } })
    }

    func testBriefNoteLimitsDiscussionAndActionRecordNumbersDirections() throws {
        var config = MinutesStudioConfig.standard()
        config.format = .briefNote
        let brief = MinutesDocumentBuilder.build(
            snapshot: snapshot(), config: config, templateName: "T", documentHeading: "H"
        )
        XCTAssertEqual(brief.blocks.first { $0.id == "discussion" }?.lines.count, 3)

        config.format = .officeActionRecord
        let record = MinutesDocumentBuilder.build(
            snapshot: snapshot(), config: config, templateName: "T", documentHeading: "H"
        )
        let actions = try XCTUnwrap(record.blocks.first { $0.id == "actionItems" })
        XCTAssertEqual(actions.heading, "Directions")
        XCTAssertEqual(actions.lines, ["1. Book venue", "Owner: Pawan Joshi · Deadline: No deadline"])
    }

    func testBlocksFollowCustomSectionOrder() {
        var config = MinutesStudioConfig.standard()
        config.sectionOrder = [.actionItems, .decisions]
        let doc = MinutesDocumentBuilder.build(
            snapshot: snapshot(), config: config, templateName: "T", documentHeading: "H"
        )
        let ids = doc.blocks.map(\.id)
        XCTAssertEqual(Array(ids.prefix(2)), ["actionItems", "decisions"])
    }

    func testHeaderLinesDependOnLetterhead() {
        var config = MinutesStudioConfig.standard()
        config.organisationName = "Acme Ltd"
        config.organisationAddress = "1 Main Road"
        XCTAssertTrue(MinutesDocumentBuilder.headerLines(config: config).isEmpty)
        config.letterheadID = "company"
        XCTAssertEqual(MinutesDocumentBuilder.headerLines(config: config), ["Acme Ltd", "1 Main Road"])
        config.letterheadID = "office"
        XCTAssertEqual(MinutesDocumentBuilder.headerLines(config: config), ["Acme Ltd"])
    }

    func testRenderedDocumentIsAParseablePDF() throws {
        let document = MinutesDocumentBuilder.build(
            snapshot: snapshot(), config: .standard(), templateName: "Project review", documentHeading: "Minutes"
        )
        let data = try MinutesPDFRenderer.render(document: document, letterhead: nil)
        XCTAssertTrue(data.starts(with: Data("%PDF-".utf8)))
        XCTAssertGreaterThan(try XCTUnwrap(PDFDocument(data: data)).pageCount, 0)
    }
}
