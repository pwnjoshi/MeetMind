import Foundation
import MessageUI
import SwiftData

/// What the system reported when the user handed the minutes to Mail or the share sheet.
/// Only `.mailSent` may be described as "Sent". A generic activity can only be described as "Shared".
enum MinutesShareOutcome: Equatable {
    case mailSent
    case mailSaved
    case shared
    case cancelled
    case failed(String)

    static func fromMail(_ result: MFMailComposeResult, error: Error?) -> MinutesShareOutcome {
        if let error { return .failed(error.localizedDescription) }
        switch result {
        case .sent: return .mailSent
        case .saved: return .mailSaved
        case .cancelled: return .cancelled
        case .failed: return .failed("Mail could not send the minutes.")
        @unknown default: return .cancelled
        }
    }

    static func fromActivity(completed: Bool) -> MinutesShareOutcome {
        completed ? .shared : .cancelled
    }

    /// The history channel to record. Cancelled, saved-as-draft and failed attempts record nothing.
    var recordedChannel: SharedMinutesEntry.Channel? {
        switch self {
        case .mailSent: return .mail
        case .shared: return .shareSheet
        case .mailSaved, .cancelled, .failed: return nil
        }
    }

    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Copy and avatars for the animated post-share screen. Wording never says anyone received or read the minutes.
struct MinutesSentState: Equatable {
    let title: String
    let handoffText: String
    let settledText: String
    let settledSymbol: String
    let message: String
    let recipients: [SharedMinutesRecipient]

    /// Returns nil when nothing was sent or shared, so no success screen is shown.
    static func make(outcome: MinutesShareOutcome, recipients: [SharedMinutesRecipient]) -> MinutesSentState? {
        switch outcome {
        case .mailSent:
            let names = MeetingRecordFormatting.joinedNames(recipients.map { MeetingRecordFormatting.firstName($0.name) })
            let who = names.isEmpty ? "" : " to \(names)"
            return MinutesSentState(
                title: "Minutes Sent",
                handoffText: "Handing off to Mail\u{2026}",
                settledText: "Sent from Mail",
                settledSymbol: "paperplane.fill",
                message: "Mail sent the minutes and their action items\(who). Manent cannot see whether they arrived or were opened.",
                recipients: recipients
            )
        case .shared:
            return MinutesSentState(
                title: "Minutes Shared",
                handoffText: "Handing off to the share sheet\u{2026}",
                settledText: "Shared",
                settledSymbol: "square.and.arrow.up",
                message: "You completed an activity from the share sheet. Manent cannot tell whether it was sent, saved, copied, or exported.",
                recipients: []
            )
        case .mailSaved, .cancelled, .failed:
            return nil
        }
    }
}

/// Builds the follow-up draft used by "Schedule Next Meeting", prefilled from the meeting that was just shared.
enum MinutesFollowUpDraft {
    @MainActor
    static func make(from meeting: Meeting?, modelContext: ModelContext) -> MeetingSetupViewModel {
        let draft = MeetingSetupViewModel(modelContext: modelContext)
        guard let meeting else { return draft }
        draft.title = meeting.seriesName ?? "\(meeting.title) follow-up"
        draft.scheduledSeriesID = meeting.seriesID
        draft.scheduledSeriesName = meeting.seriesName
        draft.variant = .followUp
        draft.followUpSource = meeting
        draft.carryOverOpenActions = !draft.openActionsToCarry.isEmpty
        for person in meeting.namedAttendees {
            let copy = Speaker(name: person.name, email: person.email, role: person.role,
                               avatarColorHex: person.avatarColorHex)
            draft.addParticipant(copy)
        }
        return draft
    }
}
