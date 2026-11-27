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

/// Copy and avatars for the post-send screen (Figma B9/B10). Only Mail's `.sent` names people, because only then
/// did the user finish sending a message addressed to them. A generic share never names anyone.
struct MinutesSentState: Equatable {
    let title: String
    let message: String
    let recipients: [SharedMinutesRecipient]

    /// Returns nil when nothing was sent or shared, so no success screen is shown.
    static func make(outcome: MinutesShareOutcome, recipients: [SharedMinutesRecipient]) -> MinutesSentState? {
        switch outcome {
        case .mailSent:
            let names = recipients.map { MeetingRecordFormatting.firstName($0.name) }
            return MinutesSentState(title: "Minutes Sent", message: sentMessage(firstNames: names),
                                    recipients: recipients)
        case .shared:
            return MinutesSentState(
                title: "Minutes Shared",
                message: "You shared the minutes from this iPhone. Manent cannot see where they went.",
                recipients: []
            )
        case .mailSaved, .cancelled, .failed:
            return nil
        }
    }

    /// "Maya, Arjun, Pawan and Garima have the minutes and their action items."
    static func sentMessage(firstNames: [String]) -> String {
        if firstNames.isEmpty { return "The minutes and their action items are on their way." }
        if firstNames.count == 1 { return "\(firstNames[0]) has the minutes and the action items." }
        return "\(nameList(firstNames)) have the minutes and their action items."
    }

    /// Up to four names are listed. Longer lists show three names and a count.
    static func nameList(_ firstNames: [String]) -> String {
        guard firstNames.count > 4 else { return MeetingRecordFormatting.joinedNames(firstNames) }
        let rest = firstNames.count - 3
        return MeetingRecordFormatting.joinedNames(Array(firstNames.prefix(3)) + ["\(rest) others"])
    }
}

extension MinutesShareOutcome {
    /// The honest note shown in the Send Minutes sheet when the attempt did not send anything.
    func sendSheetNotice(viaMail: Bool) -> String? {
        switch self {
        case .mailSaved:
            return "Saved as a draft in Mail. The minutes have not been sent."
        case .cancelled:
            return viaMail ? "Not sent. Tap Send to try again." : nil
        case .failed(let message):
            return "\(message) Nothing was sent."
        case .mailSent, .shared:
            return nil
        }
    }
}

/// Who can receive the minutes and how the Send button reads. Kept free of views so it can be tested.
enum MinutesSendPlan {
    /// Attendees other than the user, with an email address, one per address.
    static func candidates(from attendees: [Speaker], userName: String?) -> [Speaker] {
        var seen = Set<String>()
        return attendees.filter { person in
            guard person.name != userName,
                  let email = person.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !email.isEmpty else { return false }
            return seen.insert(email).inserted
        }
    }

    /// Everyone with an email starts selected.
    static func defaultSelection(_ people: [Speaker]) -> Set<UUID> {
        Set(people.map { $0.id })
    }

    static func buttonTitle(count: Int, mailAvailable: Bool = true) -> String {
        if !mailAvailable { return "Share PDF" }
        switch count {
        case 0: return "Send Minutes"
        case 1: return "Send to 1 Person"
        default: return "Send to \(count) People"
        }
    }

    static func accessibilityLabel(count: Int, mailAvailable: Bool = true) -> String {
        if !mailAvailable { return "Share PDF" }
        switch count {
        case 0: return "Send minutes"
        case 1: return "Send to 1 person"
        default: return "Send to \(count) people"
        }
    }

    /// Why the primary button is disabled, or nil when it can be used.
    static func disabledReason(candidateCount: Int, selectedCount: Int, isPreparing: Bool,
                               mailAvailable: Bool = true) -> String? {
        if isPreparing { return "Preparing the PDF\u{2026}" }
        if !mailAvailable { return nil }
        if candidateCount == 0 { return "No attendee has an email address. Add someone to send by Mail." }
        if selectedCount == 0 { return "Select at least one person." }
        return nil
    }
}
/// Builds the follow-up draft used by "Plan Next Meeting", prefilled from the meeting that was just shared.
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
