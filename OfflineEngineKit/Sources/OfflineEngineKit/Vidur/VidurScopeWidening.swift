import Foundation

/// The short line that tells the user Vidur looked beyond the meeting they opened it from.
public enum VidurScopeNote {
    public static let notHappened = "This meeting hasn\u{2019}t happened yet, so I looked at your other meetings."
    public static let notCovered = "This meeting doesn\u{2019}t cover that, so I looked at your other meetings."
    public static let notCoveredSeries = "This meeting doesn\u{2019}t cover that, so I looked at its series."

    /// True when none of the records has a transcript, notes or minutes (a scheduled meeting that was not held).
    public static func isUnrecorded(_ records: [VidurMeetingRecord]) -> Bool {
        records.allSatisfy { record in
            record.turns.isEmpty && record.summary.isEmpty && record.discussion.isEmpty && record.decisions.isEmpty
                && record.openIssues.isEmpty && record.tasks.isEmpty
        }
    }

    public static func note(unrecorded: Bool, isSeries: Bool) -> String {
        if unrecorded { return notHappened }
        return isSeries ? notCoveredSeries : notCovered
    }

    public static func prefixed(_ text: String, note: String) -> String {
        note + "\n\n" + text
    }

    /// The answer without a leading scope note, for chat history that should start with the answer itself.
    public static func strip(_ text: String) -> String {
        for note in [notHappened, notCovered, notCoveredSeries] where text.hasPrefix(note) {
            return String(text.dropFirst(note.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
