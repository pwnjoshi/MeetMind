import Foundation
import OfflineEngineKit

/// Turns the app's Sendable snapshots into the records Vidur's instant tiers search.
public enum VidurRecordAdapter {
    /// One record per meeting. Minutes come from `facts`, the transcript from `sources`; either may be missing.
    public static func records(facts: [VidurMeetingFacts], sources: [VidurSourceMeeting]) -> [VidurMeetingRecord] {
        var sourceByID: [UUID: VidurSourceMeeting] = [:]
        for source in sources { sourceByID[source.id] = source }
        var output: [VidurMeetingRecord] = []
        var used = Set<UUID>()
        for item in facts where used.insert(item.meetingID).inserted {
            output.append(record(facts: item, source: sourceByID[item.meetingID]))
        }
        for source in sources where used.insert(source.id).inserted {
            output.append(record(source: source))
        }
        return output
    }

    static func turns(_ source: VidurSourceMeeting?) -> [VidurMeetingTurn] {
        (source?.turns ?? []).map { VidurMeetingTurn(text: $0.text, start: $0.start, speaker: $0.speaker) }
    }

    static func record(facts: VidurMeetingFacts, source: VidurSourceMeeting?) -> VidurMeetingRecord {
        func line(_ fact: VidurFactLine) -> VidurMeetingLine {
            VidurMeetingLine(text: fact.text, timestamp: fact.timestamp, quote: fact.quote, speaker: fact.speaker)
        }
        let tasks = facts.tasks.map {
            VidurMeetingTask(title: $0.title, owner: $0.owner, dueDate: $0.dueDate, dueText: $0.dueText,
                             isCompleted: $0.isCompleted, isSuggestion: $0.isSuggestion, timestamp: $0.timestamp,
                             quote: $0.quote)
        }
        return VidurMeetingRecord(
            id: facts.meetingID, title: facts.title, date: facts.date, duration: facts.duration,
            attendees: facts.attendees, absent: facts.absent, attendanceRecorded: facts.attendanceRecorded,
            agenda: facts.agenda, summary: facts.summary, discussion: facts.discussion,
            decisions: facts.decisions.map(line), openIssues: facts.openIssues.map(line), tasks: tasks,
            turns: turns(source))
    }

    static func record(source: VidurSourceMeeting) -> VidurMeetingRecord {
        VidurMeetingRecord(id: source.id, title: source.title, date: source.date, turns: turns(source))
    }
}
