import Foundation
import SwiftData

/// Every edit of the Minutes of Meeting document goes through here.
/// A material edit (topics, outcomes, attendance, closure) returns the minutes to Draft and removes the
/// signature, because a signature only covers the text the chairperson saw. Details such as venue or
/// the format change nothing that was reviewed, so they keep the status.
@MainActor
enum MoMEditor {
    static func edit(_ meeting: Meeting, context: ModelContext, store: MoMSidecarStore,
                     material: Bool, _ change: @escaping (inout MoMSidecar) -> Void) throws {
        let previousFlag = meeting.minutesNeedFinalization
        let previous = store.sidecar(for: meeting.id)
        let invalidates = material && (meeting.summary != nil || previous.isSigned)
        try store.update(meeting.id) { sidecar in
            change(&sidecar)
            if invalidates {
                sidecar.signaturePNG = nil
                sidecar.signedAt = nil
            }
        }
        guard invalidates else { return }
        meeting.minutesNeedFinalization = true
        do { try context.save() }
        catch {
            meeting.minutesNeedFinalization = previousFlag
            try? store.update(meeting.id) { $0 = previous }
            throw error
        }
    }

    /// Stores the chairperson's drawn signature. Signing never changes the reviewed text.
    static func sign(_ meeting: Meeting, signerName: String, place: String?, png: Data,
                     store: MoMSidecarStore, now: Date = Date()) throws {
        guard !png.isEmpty else { throw MoMEditError.emptySignature }
        let trimmed = place?.trimmingCharacters(in: .whitespacesAndNewlines)
        try store.update(meeting.id) {
            $0.signaturePNG = png
            $0.signedAt = now
            $0.signedByName = signerName
            $0.signedPlace = (trimmed?.isEmpty ?? true) ? nil : trimmed
        }
    }

    static func clearSignature(_ meeting: Meeting, store: MoMSidecarStore) throws {
        try store.update(meeting.id) {
            $0.signaturePNG = nil
            $0.signedAt = nil
        }
    }

    static func dismissMention(_ name: String, meeting: Meeting, store: MoMSidecarStore) throws {
        try store.update(meeting.id) {
            let key = name.lowercased()
            if !$0.dismissedMentions.contains(key) { $0.dismissedMentions.append(key) }
        }
    }

    /// Adds a person the engine heard named. Uses the same path as the People sheet.
    static func addMention(_ name: String, meeting: Meeting, context: ModelContext, store: MoMSidecarStore) throws {
        _ = try MeetingPeopleEditor.addNewAttendee(name: name, email: nil, role: nil, meeting: meeting, context: context)
        try edit(meeting, context: context, store: store, material: true) { _ in }
    }
}

enum MoMEditError: LocalizedError {
    case emptySignature

    var errorDescription: String? {
        switch self {
        case .emptySignature: return "Draw your signature first."
        }
    }
}
