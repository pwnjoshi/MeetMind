import XCTest
import SwiftData
@testable import MeetMind

@MainActor
final class SettingsV5Tests: XCTestCase {
    func testOrganizationDetailsRoundTripAndErase() throws {
        let suite = "org-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OrganizationProfileStore()
        XCTAssertEqual(store.load(defaults: defaults), OrganizationDetails())
        var details = OrganizationDetails()
        details.address = "Bengaluru 560103"
        details.phone = "+91 80 0000 0000"
        details.email = "office@example.com"
        store.save(details, defaults: defaults)
        XCTAssertEqual(store.load(defaults: defaults), details)
        XCTAssertEqual(details.contactLine, "+91 80 0000 0000 \u{00B7} office@example.com")
        store.eraseAll(defaults: defaults)
        XCTAssertEqual(store.load(defaults: defaults), OrganizationDetails())
    }

    func testExportSelectionKeepsOnlyFinalizedMeetingsInRange() throws {
        let container = try ModelContainerFactory.createInMemoryContainer()
        let context = container.mainContext
        let recent = Meeting(title: "Recent", createdAt: Date().addingTimeInterval(-86_400), duration: 600, status: .completed)
        let old = Meeting(title: "Old", createdAt: Date().addingTimeInterval(-86_400 * 90), duration: 600, status: .completed)
        let notFinal = Meeting(title: "Draft", createdAt: Date(), duration: 600, status: .completed)
        context.insert(recent)
        context.insert(old)
        context.insert(notFinal)
        XCTAssertFalse(ExportAllSelection.isFinalized(notFinal))
        XCTAssertEqual(ExportAllRange.lastMonth.cutoff() != nil, true)
        XCTAssertNil(ExportAllRange.allTime.cutoff())
        // Without summaries nothing is finalized.
        XCTAssertTrue(ExportAllSelection.meetings(from: [recent, old, notFinal], range: .allTime).isEmpty)
    }

    func testContactsDirectoryExcludesVoiceLabelsAndDuplicates() throws {
        let container = try ModelContainerFactory.createInMemoryContainer()
        let context = container.mainContext
        let maya = Speaker(name: "Maya Rao", email: "maya@example.com")
        let mayaDuplicate = Speaker(name: "maya rao")
        let arjun = Speaker(name: "Arjun Mehta", role: "Finance")
        let voice = Speaker(name: "Speaker 1")
        for speaker in [maya, mayaDuplicate, arjun, voice] { context.insert(speaker) }
        let all = ContactsDirectory.people(from: [maya, mayaDuplicate, arjun, voice], query: "")
        XCTAssertEqual(all.map(\.name), ["Arjun Mehta", "Maya Rao"])
        XCTAssertEqual(ContactsDirectory.people(from: all, query: "financ").map(\.name), ["Arjun Mehta"])
        XCTAssertEqual(ContactsDirectory.people(from: all, query: "maya@").map(\.name), ["Maya Rao"])
    }

    func testPreferredMinutesFormatDefaultsToAutomaticAndReadsStoredChoice() throws {
        let suite = "format-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(MinutesFormat.preferred(defaults: defaults))
        defaults.set("", forKey: MinutesFormat.preferenceKey)
        XCTAssertNil(MinutesFormat.preferred(defaults: defaults))
        defaults.set(MinutesFormat.briefNote.rawValue, forKey: MinutesFormat.preferenceKey)
        XCTAssertEqual(MinutesFormat.preferred(defaults: defaults), .briefNote)
    }
}