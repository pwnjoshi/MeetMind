import Foundation
import Observation
import OSLog
import SwiftData
import UIKit

public struct RecoveredRecordingNotice: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let meetingID: UUID
    public let duration: TimeInterval

    public init(meetingID: UUID, duration: TimeInterval) {
        self.id = UUID()
        self.meetingID = meetingID
        self.duration = duration
    }
}

public enum PendingRecordingRecoveryReason: String, Sendable, Equatable {
    case meetingMissing
    case audioMissing
    case invalidAudio

    public var message: String {
        switch self {
        case .meetingMissing:
            return "A recording survived, but its meeting was deleted. You can recover it as a new meeting or delete it."
        case .audioMissing:
            return "A recording recovery record remains, but its audio file is missing. You can keep the record for support or delete it."
        case .invalidAudio:
            return "An interrupted audio file could not be opened. It was moved to quarantine instead of being deleted."
        }
    }
}

public struct PendingRecordingRecovery: Identifiable, Sendable, Equatable {
    public var id: UUID { journal.meetingID }
    public let journal: RecordingTakeJournal
    public let reason: PendingRecordingRecoveryReason

    public init(journal: RecordingTakeJournal, reason: PendingRecordingRecoveryReason) {
        self.journal = journal
        self.reason = reason
    }
}

public struct RecordingRecoveryReport: Sendable, Equatable {
    public let recovered: [RecoveredRecordingNotice]
    public let pending: [PendingRecordingRecovery]

    public init(recovered: [RecoveredRecordingNotice], pending: [PendingRecordingRecovery]) {
        self.recovered = recovered
        self.pending = pending
    }
}

@MainActor
public final class RecordingRecoveryCoordinator {
    private let context: ModelContext
    public let store: RecordingTakeJournalStore
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.meetmind.app", category: "RecordingRecovery")

    public init(
        modelContext: ModelContext,
        store: RecordingTakeJournalStore = .live(),
        fileManager: FileManager = .default
    ) {
        self.context = modelContext
        self.store = store
        self.fileManager = fileManager
    }

    public func recoverInterruptedRecordings() throws -> RecordingRecoveryReport {
        var recovered: [RecoveredRecordingNotice] = []
        var pending: [PendingRecordingRecovery] = []

        for originalJournal in try store.loadAll() {
            var journal = originalJournal
            let audioURL = try store.audioURL(for: journal)
            let meeting = try fetchMeeting(journal.meetingID)

            if let meeting, meetingOwns(meeting, journal: journal, audioURL: audioURL) {
                try store.remove(meetingID: journal.meetingID)
                logger.notice("Cleared a completed recording recovery journal")
                continue
            }

            guard fileManager.fileExists(atPath: audioURL.path) else {
                let reason: PendingRecordingRecoveryReason = journal.failureCode == "audio_unreadable"
                    || journal.failureCode == "audio_empty"
                    || journal.failureCode == "audio_duration_invalid"
                    || journal.failureCode == "audio_invalid" ? .invalidAudio : .audioMissing
                pending.append(PendingRecordingRecovery(journal: journal, reason: reason))
                continue
            }

            let info: CanonicalRecordingInfo
            do {
                info = try CanonicalRecordingValidator.validate(audioURL, fileManager: fileManager)
            } catch {
                _ = try store.quarantineInvalidAudio(for: journal, validationCode: validationCode(for: error))
                journal = try store.load(meetingID: journal.meetingID) ?? journal
                pending.append(PendingRecordingRecovery(journal: journal, reason: .invalidAudio))
                continue
            }

            if journal.state != .persisted {
                journal = try store.transition(
                    meetingID: journal.meetingID,
                    to: .validated,
                    duration: info.duration,
                    failureCode: journal.failureCode
                )
            }
            guard let meeting else {
                pending.append(PendingRecordingRecovery(journal: journal, reason: .meetingMissing))
                continue
            }

            try attach(audioURL: audioURL, info: info, journal: journal, to: meeting)
            recovered.append(RecoveredRecordingNotice(meetingID: meeting.id, duration: info.duration))
            logger.notice("Recovered an interrupted recording; duration=\(info.duration, privacy: .public)")
        }

        return RecordingRecoveryReport(recovered: recovered, pending: pending)
    }

    public func recoverAsNewMeeting(_ pending: PendingRecordingRecovery) throws -> RecoveredRecordingNotice {
        guard pending.reason == .meetingMissing else {
            throw RecordingRecoveryError.recoveryRequired
        }
        let journal = try store.load(meetingID: pending.journal.meetingID) ?? pending.journal
        let audioURL = try store.audioURL(for: journal)
        let info = try CanonicalRecordingValidator.validate(audioURL, fileManager: fileManager)
        if journal.state != .persisted {
            _ = try store.transition(
                meetingID: journal.meetingID,
                to: .validated,
                duration: info.duration,
                failureCode: journal.failureCode
            )
        }
        let meeting = Meeting(
            id: journal.meetingID,
            title: "Recovered recording",
            createdAt: journal.startedAt,
            duration: info.duration,
            status: .processing
        )
        context.insert(meeting)
        do {
            try attach(audioURL: audioURL, info: info, journal: journal, to: meeting)
        } catch {
            context.rollback()
            throw error
        }
        logger.notice("Recovered an interrupted recording as a new meeting; duration=\(info.duration, privacy: .public)")
        return RecoveredRecordingNotice(meetingID: meeting.id, duration: info.duration)
    }

    public func deletePendingRecovery(_ pending: PendingRecordingRecovery) throws {
        let journal = try store.load(meetingID: pending.journal.meetingID) ?? pending.journal
        try store.deleteAudioAndJournal(journal)
        logger.notice("Deleted an interrupted recording after confirmation")
    }

    private func attach(
        audioURL: URL,
        info: CanonicalRecordingInfo,
        journal: RecordingTakeJournal,
        to meeting: Meeting
    ) throws {
        meeting.setAudioFileURL(audioURL)
        meeting.duration = info.duration
        meeting.status = .processing
        meeting.analysisState = "ready"
        try context.save()

        guard let saved = try fetchMeeting(meeting.id),
              meetingOwns(saved, journal: journal, audioURL: audioURL),
              saved.duration == info.duration,
              saved.status == .processing,
              saved.analysisState == "ready" else {
            throw RecordingSaveError.persistenceFailed("Saved recording ownership could not be verified.")
        }
        _ = try store.transition(meetingID: journal.meetingID, to: .persisted, duration: info.duration)
        try store.remove(meetingID: journal.meetingID)
    }

    private func fetchMeeting(_ id: UUID) throws -> Meeting? {
        var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func meetingOwns(_ meeting: Meeting, journal: RecordingTakeJournal, audioURL: URL) -> Bool {
        if meeting.audioRelativePath == journal.relativeAudioPath { return true }
        if meeting.audioFileURL?.standardizedFileURL == audioURL.standardizedFileURL { return true }
        return meeting.resolvedAudioFileURL?.standardizedFileURL == audioURL.standardizedFileURL
    }

    private func validationCode(for error: Error) -> String {
        switch error as? CanonicalRecordingValidationError {
        case .fileMissing: return "audio_missing"
        case .unreadableAudio: return "audio_unreadable"
        case .emptyAudio: return "audio_empty"
        case .invalidDuration: return "audio_duration_invalid"
        case nil: return "audio_invalid"
        }
    }
}

@Observable
@MainActor
public final class RecordingRecoveryCenter {
    public private(set) var notice: RecoveredRecordingNotice?
    public private(set) var pending: PendingRecordingRecovery?
    public private(set) var pendingCount = 0
    public var isPresentingPending = false
    public private(set) var isDeferredUntilProtectedData = false
    public var isShowingDeleteConfirmation = false
    public var errorMessage: String?

    private let store: RecordingTakeJournalStore

    public init(store: RecordingTakeJournalStore = .live()) {
        self.store = store
    }

    public func run(modelContext: ModelContext) {
        guard UIApplication.shared.isProtectedDataAvailable else {
            isDeferredUntilProtectedData = true
            return
        }
        isDeferredUntilProtectedData = false
        do {
            let report = try RecordingRecoveryCoordinator(modelContext: modelContext, store: store)
                .recoverInterruptedRecordings()
            if let firstRecovered = report.recovered.first { notice = firstRecovered }
            pending = report.pending.first
            pendingCount = report.pending.count
            if pending != nil { isPresentingPending = true }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func recoverPendingAsNew(modelContext: ModelContext) {
        guard let pending else { return }
        do {
            notice = try RecordingRecoveryCoordinator(modelContext: modelContext, store: store)
                .recoverAsNewMeeting(pending)
            self.pending = nil
            pendingCount = max(0, pendingCount - 1)
            isPresentingPending = false
            errorMessage = nil
            run(modelContext: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func confirmDeletePending(modelContext: ModelContext) {
        guard let pending else { return }
        do {
            try RecordingRecoveryCoordinator(modelContext: modelContext, store: store)
                .deletePendingRecovery(pending)
            self.pending = nil
            pendingCount = max(0, pendingCount - 1)
            isPresentingPending = false
            isShowingDeleteConfirmation = false
            errorMessage = nil
            run(modelContext: modelContext)
        } catch {
            isShowingDeleteConfirmation = false
            errorMessage = error.localizedDescription
        }
    }

    public func presentPendingPrompt() {
        isPresentingPending = pending != nil
    }

    public func dismissPendingPrompt() {
        isPresentingPending = false
    }

    public func dismissNotice() {
        notice = nil
    }
}
