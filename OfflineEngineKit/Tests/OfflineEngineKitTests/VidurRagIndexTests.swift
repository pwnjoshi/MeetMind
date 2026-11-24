import XCTest
@testable import OfflineEngineKit

/// Shared helpers for the retrieval tests. "Today" is Friday 21 November 2025, 10:00 UTC.
enum VidurRagTestSupport {
    static func index(_ records: [VidurMeetingRecord] = VidurEvalFixtures.all) -> VidurRagIndex {
        VidurRagIndex.build(records: records, calendar: VidurEvalFixtures.calendar)
    }

    static func retrieve(_ question: String, history: [VidurChatTurn] = [], limit: Int = 6,
                         index: VidurRagIndex? = nil) -> VidurRagRetrieval {
        let query = VidurRagQuery(question: question, history: history, selfNames: VidurEvalFixtures.selfNames,
                                  now: VidurEvalFixtures.now, calendar: VidurEvalFixtures.calendar, limit: limit)
        return VidurRagRetriever.retrieve(query, index: index ?? Self.index())
    }

    /// The same meeting with a different summary.
    static func withSummary(_ record: VidurMeetingRecord, _ summary: String) -> VidurMeetingRecord {
        VidurMeetingRecord(
            id: record.id, title: record.title, date: record.date, duration: record.duration,
            attendees: record.attendees, absent: record.absent, attendanceRecorded: record.attendanceRecorded,
            agenda: record.agenda, summary: summary, discussion: record.discussion, decisions: record.decisions,
            openIssues: record.openIssues, tasks: record.tasks, turns: record.turns,
            nextMeetingText: record.nextMeetingText, seriesTitle: record.seriesTitle)
    }
}

final class VidurRagIndexTests: XCTestCase {
    private let calendar = VidurEvalFixtures.calendar

    func testEveryMeetingGetsAFactsBlockWithItsMetadata() throws {
        let index = VidurRagTestSupport.index()
        XCTAssertEqual(index.meetings.count, 4)
        XCTAssertEqual(index.meetings.map(\.title), ["Hiring review", "Launch readiness", "Weekly sync", "Design review"])
        let facts = try XCTUnwrap(index.facts(for: VidurEvalFixtures.launchID))
        XCTAssertEqual(facts.kind, .facts)
        XCTAssertEqual(facts.meetingTitle, "Launch readiness")
        XCTAssertTrue(facts.text.contains("Held Mon 10 Nov 2025 at 09:00, 40 min."), facts.text)
        XCTAssertTrue(facts.text.contains("Present: Neha Sharma, Pawan Kumar, Maya Rao."), facts.text)
        XCTAssertTrue(facts.text.contains("Absent: Arjun Mehta."), facts.text)
        XCTAssertTrue(facts.text.contains("Agenda: Launch date; Vendor selection; Budget."), facts.text)
        XCTAssertTrue(facts.text.contains("2 decisions, 4 actions (3 open), 1 open issue"), facts.text)
        XCTAssertTrue(facts.text.contains("Summary: The team fixed the launch date"), facts.text)
        for record in VidurEvalFixtures.all {
            XCTAssertNotNil(index.facts(for: record.id), record.title)
        }
    }

    func testSeriesAppearsInTheFactsBlock() throws {
        let record = VidurMeetingRecord(
            title: "Product weekly", date: VidurEvalFixtures.date(2025, 11, 18), duration: 600,
            attendees: ["Neha Sharma"], summary: "Roadmap check.", seriesTitle: "Product planning")
        let index = VidurRagTestSupport.index([record])
        let facts = try XCTUnwrap(index.facts(for: record.id))
        XCTAssertTrue(facts.text.contains("Series: Product planning."), facts.text)
        XCTAssertEqual(facts.seriesTitle, "Product planning")
    }

    func testDecisionsKeepSpeakerTimeAndWords() throws {
        let index = VidurRagTestSupport.index()
        let chunk = try XCTUnwrap(index.chunks.first {
            $0.kind == .decision && $0.meetingID == VidurEvalFixtures.launchID && $0.text.contains("Launch on 20 November")
        })
        XCTAssertEqual(chunk.speaker, "Neha Sharma")
        XCTAssertEqual(chunk.timestamp, 95)
        XCTAssertTrue(chunk.text.contains("(decided by Neha Sharma)"), chunk.text)
        XCTAssertTrue(chunk.text.contains("we launch on 20 November"), chunk.text)
        XCTAssertEqual(chunk.meetingTitle, "Launch readiness")
    }

    func testActionsKeepOwnerDueDateStatusAndContext() throws {
        let index = VidurRagTestSupport.index()
        let open = try XCTUnwrap(index.chunks.first { $0.kind == .action && $0.text.contains("Send the presentation") })
        XCTAssertTrue(open.text.contains("owner: Neha Sharma"), open.text)
        XCTAssertTrue(open.text.contains("due: Fri 21 Nov"), open.text)
        XCTAssertTrue(open.text.contains("status: open"), open.text)
        XCTAssertEqual(open.isCompleted, false)
        let done = try XCTUnwrap(index.chunks.first { $0.kind == .action && $0.text.contains("Book the launch venue") })
        XCTAssertTrue(done.text.contains("status: done"), done.text)
        XCTAssertTrue(done.text.contains("due: not set"), done.text)
        XCTAssertEqual(done.isCompleted, true)
        let withContext = try XCTUnwrap(index.chunks.first { $0.kind == .action && $0.text.contains("Revise onboarding") })
        XCTAssertTrue(withContext.text.contains("said: \u{201C}I will revise the onboarding copy by Tuesday\u{201D}"), withContext.text)
    }

    func testAttendanceAgendaOpenIssuesAndSummaryAreIndexed() {
        let index = VidurRagTestSupport.index()
        let launch = index.chunks.filter { $0.meetingID == VidurEvalFixtures.launchID }
        XCTAssertTrue(launch.contains { $0.kind == .attendance && $0.text.contains("Absent: Arjun Mehta") })
        XCTAssertTrue(launch.contains { $0.kind == .agenda && $0.text.contains("Vendor selection") })
        XCTAssertTrue(launch.contains { $0.kind == .summary && $0.text.contains("Pune vendor") })
        XCTAssertTrue(launch.contains { $0.kind == .discussion && $0.text.contains("Marketing budget needs a number") })
        let issue = launch.first { $0.kind == .openIssue }
        XCTAssertEqual(issue?.speaker, "Maya Rao")
        XCTAssertTrue(issue?.text.contains("raised by Maya Rao") == true)
    }

    func testTranscriptChunksCarryTheSpeakerAndTimecode() throws {
        let index = VidurRagTestSupport.index()
        let chunk = try XCTUnwrap(index.chunks.first {
            $0.kind == .transcript && $0.meetingID == VidurEvalFixtures.launchID
        })
        XCTAssertTrue(chunk.text.contains("Neha Sharma [00:00]: Hi everyone"), chunk.text)
        XCTAssertEqual(chunk.timestamp, 0)
        XCTAssertFalse(chunk.passages.isEmpty)
        XCTAssertTrue(chunk.people.contains("Pawan Kumar"))
    }

    func testTranscriptWindowsAreAboutSeventyFiveSecondsAndOverlap() {
        let turns = (0..<16).map { number in
            VidurMeetingTurn(text: "Turn \(number) about pricing.", start: TimeInterval(number * 20), speaker: "Asha")
        }
        let record = VidurMeetingRecord(title: "Long call", date: VidurEvalFixtures.date(2025, 11, 12), turns: turns)
        let index = VidurRagTestSupport.index([record])
        let windows = index.chunks.filter { $0.kind == .transcript }
        XCTAssertGreaterThan(windows.count, 3)
        for window in windows {
            let span = (window.endTimestamp ?? 0) - (window.timestamp ?? 0)
            XCTAssertLessThanOrEqual(span, VidurRagIndex.windowSeconds)
        }
        var covered = Set<TimeInterval>()
        for window in windows { for passage in window.passages { covered.insert(passage.start) } }
        XCTAssertEqual(covered.count, 16, "Every turn belongs to at least one window")
        for pair in zip(windows, windows.dropFirst()) {
            let first = Set(pair.0.passages.map(\.start))
            let second = Set(pair.1.passages.map(\.start))
            XCTAssertFalse(first.isDisjoint(with: second), "Neighbouring windows overlap")
        }
    }

    func testHindiIsSearchableInBothScripts() throws {
        let hindi = "\u{0935}\u{0947}\u{0902}\u{0921}\u{0930} \u{092A}\u{0947}\u{092E}\u{0947}\u{0902}\u{091F}"
        let combined = VidurRagFormat.withRoman(hindi)
        XCTAssertTrue(combined.hasPrefix(hindi))
        XCTAssertTrue(combined.unicodeScalars.contains { $0.isASCII && $0.properties.isAlphabetic },
                      "A Roman spelling is added: \(combined)")
        XCTAssertEqual(VidurRagFormat.withRoman("Plain English"), "Plain English")

        let index = VidurRagTestSupport.index()
        let weekly = index.chunks.filter { $0.meetingID == VidurEvalFixtures.weeklyID && $0.kind == .transcript }
        XCTAssertFalse(weekly.isEmpty)
        let keys = Set(weekly.flatMap(\.keys))
        XCTAssertTrue(keys.contains("cx:vendor"), "English vendor matches the Devanagari word")
        XCTAssertTrue(keys.contains("cx:payment"))
        XCTAssertTrue(Set(VidurScript.keys("vendor payment")).isSuperset(of: ["cx:vendor", "cx:payment"]))
    }

    func testFingerprintChangesOnlyWhenContentChanges() {
        let same = VidurRagIndex.fingerprint(of: VidurEvalFixtures.all, calendar: calendar)
        XCTAssertEqual(same, VidurRagIndex.fingerprint(of: VidurEvalFixtures.all.reversed(), calendar: calendar))
        var changed = VidurEvalFixtures.all
        changed[1] = VidurRagTestSupport.withSummary(changed[1], "A different summary.")
        XCTAssertNotEqual(same, VidurRagIndex.fingerprint(of: changed, calendar: calendar))
    }

    func testCacheRebuildsOnlyAfterAMeetingChanges() {
        VidurRagIndexCache.reset()
        let first = VidurRagIndexCache.index(for: VidurEvalFixtures.all, calendar: calendar)
        XCTAssertEqual(VidurRagIndexCache.cachedHash, first.contentHash)
        let again = VidurRagIndexCache.index(for: VidurEvalFixtures.all, calendar: calendar)
        XCTAssertEqual(again.contentHash, first.contentHash)
        XCTAssertEqual(again.chunks.count, first.chunks.count)
        var changed = VidurEvalFixtures.all
        changed[0] = VidurRagTestSupport.withSummary(changed[0], "Hiring plans changed.")
        let rebuilt = VidurRagIndexCache.index(for: changed, calendar: calendar)
        XCTAssertNotEqual(rebuilt.contentHash, first.contentHash)
        XCTAssertEqual(VidurRagIndexCache.cachedHash, rebuilt.contentHash)
        VidurRagIndexCache.reset()
        XCTAssertNil(VidurRagIndexCache.cachedHash)
    }

    func testEmptyRecordsMakeAnEmptyIndex() {
        let index = VidurRagIndex.build(records: [VidurMeetingRecord(title: "Empty", date: Date())])
        XCTAssertTrue(index.isEmpty)
        XCTAssertTrue(index.meetings.isEmpty)
        XCTAssertTrue(VidurRagRetriever.retrieve(VidurRagQuery(question: "anything"), index: index).isEmpty)
    }
}
