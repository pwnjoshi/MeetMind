import Foundation

/// How the status line of a Recent row is tinted.
public enum RecentMeetingTone: Equatable, Sendable {
    case normal
    case active
    case attention
    case failure
}

/// The second line of a Recent row, for example "Processing… · 12 min".
public struct RecentMeetingLine: Equatable, Sendable {
    public let text: String
    public let tone: RecentMeetingTone
}

/// Builds the status subtitle of a Recent row from the meeting's own state. Pure, so it is unit tested.
public enum RecentMeetingPresenter {
    public static let untitled = "Untitled meeting"

    public static func title(for meeting: Meeting) -> String {
        let trimmed = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? untitled : trimmed
    }

    /// `reviewStatus` is `MeetingLifecycleResolver.reviewDisplayStatus` for the meeting
    /// ("Finalized", "Ready to finalize", "Draft" or nil).
    public static func line(for meeting: Meeting, reviewStatus: String?) -> RecentMeetingLine {
        let status = statusPart(for: meeting, reviewStatus: reviewStatus)
        var parts: [String] = [status.text]
        let open = meeting.actionItems.filter { !$0.isCompleted }.count
        if open > 0, status.allowsActions {
            let noun = open == 1 ? "action" : "actions"
            if status.text == "Finalized" {
                parts = ["\(open) open \(noun)"]
            } else {
                parts.append("\(open) open \(noun)")
            }
        }
        if let duration = durationText(meeting.duration) { parts.append(duration) }
        return RecentMeetingLine(text: parts.joined(separator: " \u{00B7} "), tone: status.tone)
    }

    public static func durationText(_ seconds: TimeInterval) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    private struct StatusPart {
        let text: String
        let tone: RecentMeetingTone
        let allowsActions: Bool
    }

    private static func statusPart(for meeting: Meeting, reviewStatus: String?) -> StatusPart {
        switch meeting.status {
        case .recording:
            return StatusPart(text: "Recording\u{2026}", tone: .active, allowsActions: false)
        case .processing:
            return processingPart(analysisState: meeting.analysisState)
        case .scheduled:
            return StatusPart(text: "Not recorded", tone: .normal, allowsActions: false)
        case .archived:
            return StatusPart(text: "Archived", tone: .normal, allowsActions: true)
        case .completed:
            return completedPart(meeting, reviewStatus: reviewStatus)
        }
    }

    private static func processingPart(analysisState: String?) -> StatusPart {
        switch analysisState {
        case "speakerReview":
            return StatusPart(text: "Needs speaker review", tone: .attention, allowsActions: false)
        case "failed":
            return StatusPart(text: "Processing needs attention", tone: .failure, allowsActions: false)
        case "paused":
            return StatusPart(text: "Processing paused", tone: .attention, allowsActions: false)
        default:
            return StatusPart(text: "Processing\u{2026}", tone: .active, allowsActions: false)
        }
    }

    private static func completedPart(_ meeting: Meeting, reviewStatus: String?) -> StatusPart {
        if reviewStatus == "Needs speaker review" || meeting.analysisState == "speakerReview" {
            return StatusPart(text: "Needs speaker review", tone: .attention, allowsActions: false)
        }
        if meeting.analysisState == "failed" {
            return StatusPart(text: "Processing needs attention", tone: .failure, allowsActions: false)
        }
        if reviewStatus == "Finalized" {
            return StatusPart(text: "Finalized", tone: .normal, allowsActions: true)
        }
        if reviewStatus == "Draft" || reviewStatus == "Ready to finalize" || meeting.minutesNeedFinalization == true {
            return StatusPart(text: "Draft minutes", tone: .attention, allowsActions: true)
        }
        if meeting.summary == nil, meeting.audioFileURL != nil {
            return StatusPart(text: "Minutes pending", tone: .attention, allowsActions: true)
        }
        if meeting.summary == nil {
            return StatusPart(text: "Saved", tone: .normal, allowsActions: true)
        }
        return StatusPart(text: "Finalized", tone: .normal, allowsActions: true)
    }
}
