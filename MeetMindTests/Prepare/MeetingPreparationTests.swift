import XCTest
import Foundation
import SwiftData
@testable import MeetMind

@MainActor
private final class FakeCalendarService: CalendarServicing {
    var access: CalendarAccess = .fullAccess
    var isConnected: Bool = true
    var upserted: [String] = []
    var shouldFail = false

    func requestFullAccess() async -> CalendarAccess { access }

    func upsertEvent(for meeting: Meeting, existingIdentifier: String?) throws -> String {
        if shouldFail { throw CalendarServiceError.notAuthorized }
        upserted.append(meeting.title)
        return existingIdentifier ?? "event-\(upserted.count)"
    }
}

@MainActor
final class MeetingPreparationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: MeetingPrepStore!
    private var container: ModelContainer!
    private var calendar: Calendar!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "MeetingPreparationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = MeetingPrepStore(defaults: defaults, key: "prep")
        container = try ModelContainerFactory.createInMemoryContainer()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar = cal
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 17, _ min: Int = 30) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) ?? Date()
    }

    private func makeViewModel() -> MeetingSetupViewModel {
        let vm = MeetingSetupViewModel(modelContext: container.mainContext)
        vm.prepStore = store
        vm.calendarService = FakeCalendarService()
        return vm
    }

    // MARK: Recurrence

    func testWeeklyNextOccurrenceIsSevenDaysLater() {
        let base = date(2026, 11, 18)
        let next = MeetingRecurrence.weekly.nextOccurrence(after: base, now: date(2026, 11, 1), calendar: calendar)
        XCTAssertEqual(next, date(2026, 11, 25))
    }

    func testNextOccurrenceSkipsPastSlots() {
        let base = date(2026, 11, 4)
        let next = MeetingRecurrence.weekly.nextOccurrence(after: base, now: date(2026, 11, 20), calendar: calendar)
        XCTAssertEqual(next, date(2026, 11, 25))
    }

    func testBiweeklyAndMonthlyAndCustom() {
        let base = date(2026, 1, 31)
        let now = date(2026, 1, 1)
        XCTAssertEqual(MeetingRecurrence.biweekly.nextOccurrence(after: base, now: now, calendar: calendar), date(2026, 2, 14))
        XCTAssertEqual(MeetingRecurrence(unit: .day, interval: 3).nextOccurrence(after: base, now: now, calendar: calendar), date(2026, 2, 3))
        XCTAssertTrue(MeetingRecurrence.monthly.nextOccurrence(after: base, now: now, calendar: calendar) > base)
    }

    func testTitlesAndSummaries() {
        XCTAssertEqual(MeetingRecurrence.title(for: nil), "Never")
        XCTAssertEqual(MeetingRecurrence.weekly.title, "Every Week")
        XCTAssertEqual(MeetingRecurrence.biweekly.title, "Every 2 Weeks")
        XCTAssertEqual(MeetingRecurrence.weekly.summaryText, "Repeats weekly")
        XCTAssertEqual(MeetingRecurrence(unit: .day, interval: 3).summaryText, "Repeats every 3 days")
        XCTAssertEqual(MeetingRecurrence(unit: .week, interval: 0).interval, 1)
    }

    func testStoreRoundTripsAcrossInstances() {
        let id = UUID()
        let coordinator = UUID()
        store.update(id) {
            $0.recurrence = .weekly
            $0.coordinatorID = coordinator
        }
        let reloaded = MeetingPrepStore(defaults: defaults, key: "prep")
        XCTAssertEqual(reloaded.recurrence(for: id), .weekly)
        XCTAssertEqual(reloaded.coordinatorID(for: id), coordinator)
        XCTAssertEqual(reloaded.repeatSummary(for: id), "Repeats weekly")
        reloaded.update(id) {
            $0.recurrence = nil
            $0.coordinatorID = nil
        }
        XCTAssertTrue(reloaded.repeatingMeetingIDs.isEmpty)
        XCTAssertNil(MeetingPrepStore(defaults: defaults, key: "prep").repeatSummary(for: id))
    }

    func testSavingRepeatingMeetingCreatesNextOccurrenceOnce() throws {
        let vm = makeViewModel()
        vm.title = "Product planning"
        vm.startDate = Date().addingTimeInterval(3600)
        vm.endDate = vm.startDate.addingTimeInterval(1800)
        vm.recurrence = .weekly
        let meeting = try vm.saveScheduledMeeting()

        let all = try container.mainContext.fetch(FetchDescriptor<Meeting>())
        XCTAssertEqual(all.count, 2)
        let next = try XCTUnwrap(all.first { $0.id != meeting.id })
        XCTAssertEqual(next.title, "Product planning")
        XCTAssertEqual(next.status, .scheduled)
        XCTAssertEqual(next.seriesID, meeting.seriesID)
        XCTAssertNotNil(meeting.seriesID)
        XCTAssertEqual(store.recurrence(for: meeting.id), .weekly)
        XCTAssertEqual(store.recurrence(for: next.id), .weekly)

        let again = try MeetingOccurrenceScheduler.scheduleNext(after: meeting, recurrence: .weekly, context: container.mainContext, store: store)
        XCTAssertEqual(again.id, next.id)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Meeting>()), 2)
    }

    func testNeverRepeatingMeetingCreatesNoExtraMeetingOrRecord() throws {
        let vm = makeViewModel()
        vm.title = "One off"
        vm.startDate = Date().addingTimeInterval(3600)
        vm.endDate = vm.startDate.addingTimeInterval(1800)
        let meeting = try vm.saveScheduledMeeting()
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Meeting>()), 1)
        XCTAssertNil(store.recurrence(for: meeting.id))
    }

    func testGenerateDueOccurrencesAfterMeetingStarted() throws {
        let context = container.mainContext
        let past = Date().addingTimeInterval(-3 * 86_400)
        let meeting = Meeting(title: "Standup", createdAt: past, scheduledStartTime: past, duration: 900, status: .completed)
        context.insert(meeting)
        try context.save()
        store.update(meeting.id) { $0.recurrence = .daily }

        let created = try MeetingOccurrenceScheduler.generateDueOccurrences(context: context, store: store)
        XCTAssertEqual(created.count, 1)
        XCTAssertTrue((created.first?.scheduledStartTime ?? .distantPast) > Date())
        let repeated = try MeetingOccurrenceScheduler.generateDueOccurrences(context: context, store: store)
        XCTAssertTrue(repeated.isEmpty)
    }

    // MARK: Discard detection

    func testDiscardDetectionTracksEditsAgainstBaseline() {
        let vm = makeViewModel()
        vm.prepareForEditing()
        XCTAssertFalse(vm.hasUnsavedChanges)
        XCTAssertEqual(vm.agendaText, "")

        vm.title = "Finance review"
        XCTAssertTrue(vm.hasUnsavedChanges)
        vm.title = ""
        XCTAssertFalse(vm.hasUnsavedChanges)

        vm.recurrence = .weekly
        XCTAssertTrue(vm.hasUnsavedChanges)
        vm.recurrence = nil
        XCTAssertFalse(vm.hasUnsavedChanges)

        vm.agendaText = "Budget"
        XCTAssertTrue(vm.hasUnsavedChanges)
        vm.captureDraftBaseline()
        XCTAssertFalse(vm.hasUnsavedChanges)

        vm.addParticipant(name: "Pawan Joshi", email: "pawan@studio.example")
        XCTAssertTrue(vm.hasUnsavedChanges)
    }

    func testChangingStartKeepsMeetingLength() {
        let vm = makeViewModel()
        vm.startDate = date(2026, 11, 18)
        vm.endDate = date(2026, 11, 18, 18, 30)
        vm.setStart(date(2026, 11, 19, 9, 0))
        XCTAssertEqual(vm.endDate, date(2026, 11, 19, 10, 0))
        XCTAssertTrue(vm.areDatesValid)
    }

    // MARK: Calendar

    func testConnectedCalendarReceivesSavedMeetingAndEventIDIsStored() throws {
        let fake = FakeCalendarService()
        let vm = makeViewModel()
        vm.calendarService = fake
        vm.title = "Launch readiness"
        vm.startDate = Date().addingTimeInterval(3600)
        vm.endDate = vm.startDate.addingTimeInterval(1800)
        let meeting = try vm.saveScheduledMeeting()
        XCTAssertEqual(fake.upserted, ["Launch readiness"])
        XCTAssertNotNil(store.record(for: meeting.id).calendarEventID)
        XCTAssertNil(vm.calendarSyncMessage)
    }

    func testDisconnectedCalendarIsNotTouched() throws {
        let fake = FakeCalendarService()
        fake.isConnected = false
        let vm = makeViewModel()
        vm.calendarService = fake
        vm.startDate = Date().addingTimeInterval(3600)
        vm.endDate = vm.startDate.addingTimeInterval(1800)
        _ = try vm.saveScheduledMeeting()
        XCTAssertTrue(fake.upserted.isEmpty)
    }

    func testCalendarFailureKeepsMeetingAndReportsMessage() throws {
        let fake = FakeCalendarService()
        fake.shouldFail = true
        let vm = makeViewModel()
        vm.calendarService = fake
        vm.startDate = Date().addingTimeInterval(3600)
        vm.endDate = vm.startDate.addingTimeInterval(1800)
        _ = try vm.saveScheduledMeeting()
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Meeting>()), 1)
        XCTAssertNotNil(vm.calendarSyncMessage)
    }

    func testCalendarAccessLabels() {
        XCTAssertEqual(CalendarAccess.notDetermined.label, "Not Allowed")
        XCTAssertEqual(CalendarAccess.fullAccess.label, "Allowed")
        XCTAssertTrue(CalendarAccess.writeOnly.isGranted)
        XCTAssertFalse(CalendarAccess.denied.isGranted)
    }
}
