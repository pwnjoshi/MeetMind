import Foundation
import SwiftData
import UserNotifications
import OfflineEngineKit

public enum SidecarStoreError: LocalizedError, Equatable {
    case corrupt(String)

    public var errorDescription: String? {
        switch self {
        case .corrupt(let name): return "\(name) is unreadable. It was preserved rather than partially deleting unrelated records."
        }
    }
}

/// Common lifecycle contract for per-meeting JSON/defaults stores.
@MainActor
public protocol MeetingSidecarStore: AnyObject {
    func remove(meetingID: UUID) throws
    func eraseAll() throws
}

extension MeetingRecordStore: MeetingSidecarStore {}
extension MeetingPrepStore: MeetingSidecarStore {}
extension MinutesApprovalStore: MeetingSidecarStore {}
extension MinutesStudioStore: MeetingSidecarStore {}

/// The allowlisted locations and defaults keys that can contain private user content.
/// `OfflineIntelligence/Models` is intentionally absent from every deletion list.
public struct UserContentInventory: Sendable {
    public let documentsRoot: URL
    public let applicationSupportRoot: URL
    public let temporaryRoot: URL
    public let journalURL: URL

    public init(documentsRoot: URL, applicationSupportRoot: URL, temporaryRoot: URL, journalURL: URL? = nil) {
        self.documentsRoot = documentsRoot
        self.applicationSupportRoot = applicationSupportRoot
        self.temporaryRoot = temporaryRoot
        self.journalURL = journalURL ?? applicationSupportRoot
            .appendingPathComponent("ManentDeletion", isDirectory: true)
            .appendingPathComponent("deletion-v1.json")
    }

    public static func live(fileManager: FileManager = .default) -> Self {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Self(documentsRoot: documents, applicationSupportRoot: support,
                    temporaryRoot: fileManager.temporaryDirectory)
    }

    public static let privateDefaultsKeys = [
        "MeetMind_UserProfile", "Manent.workspaceName", "MeetMind_IsOnboardingCompleted",
        "Manent_LocalInbox_ReadIDs", "manent.meetingPrep.v1", "manent.calendar.connected",
        "Manent_Vidur_AnswerLength", "Manent_Vidur_SearchScope", "Manent_Vidur_ShowSources",
        "Manent_Vidur_History", "MeetMind.pendingOfflineAnalysisIDs",
        "MeetMind.pendingOfflineAnalysisIDs.imported-v2", "Manent.dismissedFirstMeetingTip",
        "MeetMind_OnDeviceSpeechOnly", "MeetMind_ThemeMode", "MeetMind_AudioBitrate",
        "MeetMind_NoiseSuppression", "MeetMind_SpeechLocale", "MeetMind_SavedRecordingLanguage",
        "MeetMind_APIKey"
    ]

    var modelsRoot: URL {
        applicationSupportRoot.appendingPathComponent("OfflineIntelligence/Models", isDirectory: true)
    }

    func meetingDirectories(_ id: UUID) -> [URL] {
        [
            documentsRoot.appendingPathComponent("RecordingChunks/\(id.uuidString)", isDirectory: true),
            applicationSupportRoot.appendingPathComponent(
                "OfflineIntelligence/RecordingChunkPreparation-v2/\(id.uuidString)", isDirectory: true)
        ]
    }

    func meetingFiles(_ id: UUID) -> [URL] {
        [applicationSupportRoot.appendingPathComponent(
            "OfflineIntelligence/MeetingCheckpoints/\(id.uuidString).json")]
    }

    var eraseAllDirectories: [URL] {
        [
            documentsRoot.appendingPathComponent("Recordings", isDirectory: true),
            documentsRoot.appendingPathComponent("RecordingChunks", isDirectory: true),
            documentsRoot.appendingPathComponent("Attachments", isDirectory: true),
            documentsRoot.appendingPathComponent("BenchmarkMetrics", isDirectory: true),
            applicationSupportRoot.appendingPathComponent("OfflineIntelligence/AnalysisJobs", isDirectory: true),
            applicationSupportRoot.appendingPathComponent("OfflineIntelligence/MeetingCheckpoints", isDirectory: true),
            applicationSupportRoot.appendingPathComponent("OfflineIntelligence/RecordingChunkPreparation-v2", isDirectory: true),
            applicationSupportRoot.appendingPathComponent("MinutesStudio", isDirectory: true),
            applicationSupportRoot.appendingPathComponent("MeetMind", isDirectory: true),
            applicationSupportRoot.appendingPathComponent("Manent", isDirectory: true)
        ]
    }

    var eraseAllFiles: [URL] {
        [applicationSupportRoot.appendingPathComponent("MeetingRecords.json")]
    }
}

public struct DeletionFailure: Codable, Equatable, Sendable {
    public let artifact: String
    public let reason: String
}

public enum DeletionCoordinatorError: LocalizedError, Equatable {
    case journalCorrupt
    case incomplete([DeletionFailure])

    public var errorDescription: String? {
        switch self {
        case .journalCorrupt:
            return "The pending deletion record is unreadable. Private data was not reported as erased."
        case .incomplete(let failures):
            let detail = failures.map { "\($0.artifact): \($0.reason)" }.joined(separator: "\n")
            return "Some local data could not be erased. Manent will retry on next launch.\n\(detail)"
        }
    }
}

/// Coordinates idempotent, journaled deletion without removing the SwiftData store
/// or downloaded public models. The journal is written before any destructive work.
@MainActor
public final class DeletionCoordinator {
    public struct Report: Equatable, Sendable {
        public let meetingsDeleted: Int
        public let filesDeleted: Int
        public let bytesFreed: Int64
        public let resumed: Bool
    }

    private struct Journal: Codable, Equatable {
        enum Operation: String, Codable { case meeting, eraseAll }
        let version: Int
        let id: UUID
        let operation: Operation
        let meetingIDs: [UUID]
        let actionItemIDs: [UUID]
        let ownedFilePaths: [String]
        let ownedDirectoryPaths: [String]
        let createdAt: Date
    }

    private let context: ModelContext
    private let inventory: UserContentInventory
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let meetingRecords: MeetingRecordStore
    private let taskResponses: TaskResponseStore
    private let minutesStudio: MinutesStudioStore
    private let meetingPrep: MeetingPrepStore
    private let approvals: MinutesApprovalStore
    private let vidur: VidurPreferences
    private let jobs: AnalysisJobStore
    private let clearsSystemNotifications: Bool
    private let clearsLiveAnalysisPipeline: Bool
    private let interruptAfterJournalWrite: Bool

    public convenience init(modelContext: ModelContext) {
        self.init(context: modelContext, inventory: .live(), defaults: .standard,
                  meetingRecords: .shared, taskResponses: .shared, minutesStudio: .shared,
                  meetingPrep: .shared, approvals: .shared, vidur: .shared, jobs: .shared)
    }

    init(context: ModelContext, inventory: UserContentInventory, defaults: UserDefaults,
         meetingRecords: MeetingRecordStore, taskResponses: TaskResponseStore,
         minutesStudio: MinutesStudioStore, meetingPrep: MeetingPrepStore,
         approvals: MinutesApprovalStore, vidur: VidurPreferences, jobs: AnalysisJobStore,
         fileManager: FileManager = .default, clearsSystemNotifications: Bool = true,
         clearsLiveAnalysisPipeline: Bool = true, interruptAfterJournalWrite: Bool = false) {
        self.context = context
        self.inventory = inventory
        self.defaults = defaults
        self.meetingRecords = meetingRecords
        self.taskResponses = taskResponses
        self.minutesStudio = minutesStudio
        self.meetingPrep = meetingPrep
        self.approvals = approvals
        self.vidur = vidur
        self.jobs = jobs
        self.fileManager = fileManager
        self.clearsSystemNotifications = clearsSystemNotifications
        self.clearsLiveAnalysisPipeline = clearsLiveAnalysisPipeline
        self.interruptAfterJournalWrite = interruptAfterJournalWrite
    }

    public func deleteMeeting(_ meeting: Meeting) async throws -> Report {
        if let resumed = try await resumePendingDeletionIfNeeded() {
            let remains = try context.fetch(FetchDescriptor<Meeting>()).contains { $0.id == meeting.id }
            if !remains { return resumed }
        }
        let journal = try makeJournal(operation: .meeting, meetings: [meeting])
        try write(journal)
        if interruptAfterJournalWrite {
            throw DeletionCoordinatorError.incomplete([
                DeletionFailure(artifact: "deletion journal", reason: "Simulated interruption")
            ])
        }
        return try await execute(journal, resumed: false)
    }

    public func eraseAll() async throws -> Report {
        _ = try await resumePendingDeletionIfNeeded()
        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        let journal = try makeJournal(operation: .eraseAll, meetings: meetings)
        try write(journal)
        if interruptAfterJournalWrite {
            throw DeletionCoordinatorError.incomplete([
                DeletionFailure(artifact: "deletion journal", reason: "Simulated interruption")
            ])
        }
        return try await execute(journal, resumed: false)
    }

    @discardableResult
    public func resumePendingDeletionIfNeeded() async throws -> Report? {
        guard fileManager.fileExists(atPath: inventory.journalURL.path) else { return nil }
        let journal: Journal
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            journal = try decoder.decode(Journal.self, from: Data(contentsOf: inventory.journalURL))
            guard journal.version == 1 else { throw DeletionCoordinatorError.journalCorrupt }
        } catch let error as DeletionCoordinatorError {
            throw error
        } catch {
            throw DeletionCoordinatorError.journalCorrupt
        }
        return try await execute(journal, resumed: true)
    }

    private func makeJournal(operation: Journal.Operation, meetings: [Meeting]) throws -> Journal {
        var files: [URL] = []
        var directories: [URL] = []
        var actionIDs: [UUID] = []
        let selectedMeetingIDs = Set(meetings.map(\.id))
        for meeting in meetings {
            actionIDs.append(contentsOf: meeting.actionItems.map(\.id))
            files.append(contentsOf: [meeting.audioFileURL, meeting.resolvedAudioFileURL].compactMap { $0 })
            files.append(contentsOf: meeting.participants.compactMap { speaker in
                let ownerIDs = Set(speaker.meetings.map(\.id))
                return !ownerIDs.isEmpty && ownerIDs.isSubset(of: selectedMeetingIDs) ? speaker.voiceSampleURL : nil
            })
            files.append(contentsOf: meeting.notes.compactMap { note in
                note.imageAttachmentPath.map { URL(fileURLWithPath: $0) }
            })
            files.append(contentsOf: inventory.meetingFiles(meeting.id))
            directories.append(contentsOf: inventory.meetingDirectories(meeting.id))
        }
        if operation == .eraseAll {
            let speakers = try context.fetch(FetchDescriptor<Speaker>())
            files.append(contentsOf: speakers.compactMap(\.voiceSampleURL))
            files.append(contentsOf: inventory.eraseAllFiles)
            directories.append(contentsOf: inventory.eraseAllDirectories)
            files.append(contentsOf: try enumeratedLoosePrivateFiles())
            if let data = defaults.data(forKey: "MeetMind_UserProfile"),
               let profile = try? JSONDecoder().decode(UserProfile.self, from: data),
               let voice = profile.voiceProfileURL { files.append(voice) }
        }
        return Journal(version: 1, id: UUID(), operation: operation,
                       meetingIDs: meetings.map(\.id), actionItemIDs: unique(actionIDs),
                       ownedFilePaths: uniqueOwned(files).map(\.path),
                       ownedDirectoryPaths: uniqueOwned(directories).map(\.path), createdAt: Date())
    }

    private func execute(_ journal: Journal, resumed: Bool) async throws -> Report {
        var failures: [DeletionFailure] = []
        var filesDeleted = 0
        var bytesFreed: Int64 = 0

        func attempt(_ artifact: String, _ work: () throws -> Void) {
            do { try work() }
            catch { failures.append(DeletionFailure(artifact: artifact, reason: error.localizedDescription)) }
        }

        if clearsLiveAnalysisPipeline {
            for meetingID in journal.meetingIDs {
                do { try await MeetingAnalysisPipeline.shared.discardCheckpointAndWait(meetingID: meetingID) }
                catch { failures.append(.init(artifact: "analysis checkpoint \(meetingID)", reason: error.localizedDescription)) }
            }
            if !failures.isEmpty { throw DeletionCoordinatorError.incomplete(deduplicated(failures)) }
        }

        if journal.operation == .meeting {
            for meetingID in journal.meetingIDs {
                OfflineAnalysisBackgroundScheduler.remove(meetingID: meetingID)
                LocalInboxReadStore(defaults: defaults).remove(meetingID: meetingID,
                                                                  actionItemIDs: journal.actionItemIDs)
                if clearsSystemNotifications {
                    let identifier = "MeetMind.analysis.\(meetingID.uuidString)"
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
                }
                attempt("meeting record \(meetingID)") { try meetingRecords.remove(meetingID: meetingID) }
                attempt("meeting preparation \(meetingID)") { try meetingPrep.remove(meetingID: meetingID) }
                attempt("minutes configuration \(meetingID)") { try minutesStudio.remove(meetingID: meetingID) }
                attempt("approval history \(meetingID)") { try approvals.remove(meetingID: meetingID) }
                attempt("Vidur history \(meetingID)") { try vidur.remove(meetingID: meetingID) }
                do { try await jobs.remove(meetingID: meetingID) }
                catch { failures.append(DeletionFailure(artifact: "analysis job \(meetingID)", reason: error.localizedDescription)) }
            }
            attempt("task responses") { try taskResponses.remove(actionItemIDs: journal.actionItemIDs) }
        }

        for path in journal.ownedFilePaths {
            let url = URL(fileURLWithPath: path)
            guard isOwned(url), fileManager.fileExists(atPath: url.path) else { continue }
            let bytes = LocalRecordingStorage.fileSize(at: url, fileManager: fileManager)
            do {
                try fileManager.removeItem(at: url)
                filesDeleted += 1
                bytesFreed += bytes
            } catch {
                failures.append(DeletionFailure(artifact: url.lastPathComponent, reason: error.localizedDescription))
            }
        }
        for path in journal.ownedDirectoryPaths {
            let url = URL(fileURLWithPath: path)
            guard isOwned(url), fileManager.fileExists(atPath: url.path) else { continue }
            let contents = regularFiles(under: url)
            let bytes = contents.reduce(Int64(0)) { $0 + LocalRecordingStorage.fileSize(at: $1, fileManager: fileManager) }
            do {
                try fileManager.removeItem(at: url)
                filesDeleted += contents.count
                bytesFreed += bytes
            } catch {
                failures.append(DeletionFailure(artifact: url.lastPathComponent, reason: error.localizedDescription))
            }
        }

        if journal.operation == .eraseAll {
            for meetingID in journal.meetingIDs { OfflineAnalysisBackgroundScheduler.remove(meetingID: meetingID) }
            attempt("meeting records") { try meetingRecords.eraseAll() }
            attempt("task responses") { try taskResponses.eraseAll() }
            attempt("Minutes Studio library") { try minutesStudio.eraseAll() }
            meetingPrep.eraseAll()
            attempt("approval history") { try approvals.eraseAll() }
            vidur.eraseAll()
            do { try await jobs.eraseAll() }
            catch { failures.append(DeletionFailure(artifact: "analysis jobs", reason: error.localizedDescription)) }
            for key in UserContentInventory.privateDefaultsKeys where key != "Manent.vidurModel" {
                defaults.removeObject(forKey: key)
            }
            if clearsSystemNotifications {
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            }
            deleteAllSwiftData(&failures)
        } else {
            deleteMeetings(journal.meetingIDs, failures: &failures)
        }

        failures.append(contentsOf: await verify(journal))
        if !failures.isEmpty { throw DeletionCoordinatorError.incomplete(deduplicated(failures)) }
        do { try fileManager.removeItem(at: inventory.journalURL) }
        catch {
            throw DeletionCoordinatorError.incomplete([
                DeletionFailure(artifact: "deletion journal", reason: error.localizedDescription)
            ])
        }
        return Report(meetingsDeleted: journal.meetingIDs.count, filesDeleted: filesDeleted,
                      bytesFreed: bytesFreed, resumed: resumed)
    }

    private func deleteMeetings(_ ids: [UUID], failures: inout [DeletionFailure]) {
        do {
            let selected = try context.fetch(FetchDescriptor<Meeting>()).filter { ids.contains($0.id) }
            for meeting in selected { context.delete(meeting) }
            try context.save()
        } catch {
            context.rollback()
            failures.append(DeletionFailure(artifact: "SwiftData meetings", reason: error.localizedDescription))
        }
    }

    private func deleteAllSwiftData(_ failures: inout [DeletionFailure]) {
        do {
            for value in try context.fetch(FetchDescriptor<Meeting>()) { context.delete(value) }
            for value in try context.fetch(FetchDescriptor<TranscriptSegment>()) { context.delete(value) }
            for value in try context.fetch(FetchDescriptor<Summary>()) { context.delete(value) }
            for value in try context.fetch(FetchDescriptor<ActionItem>()) { context.delete(value) }
            for value in try context.fetch(FetchDescriptor<Note>()) { context.delete(value) }
            for value in try context.fetch(FetchDescriptor<Speaker>()) { context.delete(value) }
            for value in try context.fetch(FetchDescriptor<Tag>()) { context.delete(value) }
            for value in try context.fetch(FetchDescriptor<Folder>()) { context.delete(value) }
            try context.save()
        } catch {
            context.rollback()
            failures.append(DeletionFailure(artifact: "SwiftData content", reason: error.localizedDescription))
        }
    }

    private func verify(_ journal: Journal) async -> [DeletionFailure] {
        var failures: [DeletionFailure] = []
        for path in journal.ownedFilePaths + journal.ownedDirectoryPaths where fileManager.fileExists(atPath: path) {
            failures.append(DeletionFailure(artifact: URL(fileURLWithPath: path).lastPathComponent,
                                            reason: "Artifact remains on disk"))
        }
        do {
            let remaining = try context.fetch(FetchDescriptor<Meeting>())
            let ids = Set(journal.meetingIDs)
            if remaining.contains(where: { ids.contains($0.id) }) {
                failures.append(DeletionFailure(artifact: "SwiftData meetings", reason: "Deleted meeting rows remain"))
            }
            if journal.operation == .eraseAll {
                let counts = [remaining.count,
                              try context.fetchCount(FetchDescriptor<TranscriptSegment>()),
                              try context.fetchCount(FetchDescriptor<Summary>()),
                              try context.fetchCount(FetchDescriptor<ActionItem>()),
                              try context.fetchCount(FetchDescriptor<Note>()),
                              try context.fetchCount(FetchDescriptor<Speaker>()),
                              try context.fetchCount(FetchDescriptor<Tag>()),
                              try context.fetchCount(FetchDescriptor<Folder>())]
                if counts.contains(where: { $0 != 0 }) {
                    failures.append(DeletionFailure(artifact: "SwiftData content", reason: "Private rows remain"))
                }
            }
        } catch {
            failures.append(DeletionFailure(artifact: "SwiftData verification", reason: error.localizedDescription))
        }
        do {
            if !(try await jobs.isEmpty()) && journal.operation == .eraseAll {
                failures.append(DeletionFailure(artifact: "analysis jobs", reason: "Job records remain"))
            }
            for id in journal.meetingIDs where (try await jobs.get(id)) != nil {
                failures.append(DeletionFailure(artifact: "analysis job \(id)", reason: "Job record remains"))
            }
        } catch {
            failures.append(DeletionFailure(artifact: "analysis job verification", reason: error.localizedDescription))
        }
        if journal.operation == .eraseAll {
            if !meetingRecords.isEmpty { failures.append(.init(artifact: "meeting records", reason: "Records remain")) }
            if !taskResponses.isEmpty { failures.append(.init(artifact: "task responses", reason: "Responses remain")) }
            if !minutesStudio.isEmpty { failures.append(.init(artifact: "Minutes Studio", reason: "Library content remains")) }
            if !meetingPrep.isEmpty { failures.append(.init(artifact: "meeting preparation", reason: "Records remain")) }
            if !approvals.isEmpty { failures.append(.init(artifact: "approval history", reason: "Records remain")) }
            if !vidur.isEmpty { failures.append(.init(artifact: "Vidur history", reason: "History remains")) }
            for key in UserContentInventory.privateDefaultsKeys where defaults.object(forKey: key) != nil {
                failures.append(.init(artifact: "preference \(key)", reason: "Private value remains"))
            }
        } else {
            for id in journal.meetingIDs {
                if meetingRecords.record(for: id) != MeetingRecordData() {
                    failures.append(.init(artifact: "meeting record \(id)", reason: "Record remains"))
                }
                if !meetingPrep.record(for: id).isEmpty {
                    failures.append(.init(artifact: "meeting preparation \(id)", reason: "Record remains"))
                }
                if minutesStudio.config(for: id) != nil {
                    failures.append(.init(artifact: "minutes configuration \(id)", reason: "Configuration remains"))
                }
                if !approvals.records(for: id).isEmpty {
                    failures.append(.init(artifact: "approval history \(id)", reason: "Records remain"))
                }
                if !vidur.history(for: id).isEmpty {
                    failures.append(.init(artifact: "Vidur history \(id)", reason: "History remains"))
                }
            }
            for actionID in journal.actionItemIDs where taskResponses.response(for: actionID) != nil {
                failures.append(.init(artifact: "task response \(actionID)", reason: "Response remains"))
            }
            let readIDs = LocalInboxReadStore(defaults: defaults).readIDs
            let deletedSuffixes = Set(journal.meetingIDs.map(\.uuidString) + journal.actionItemIDs.map(\.uuidString))
            if readIDs.contains(where: { value in deletedSuffixes.contains(where: { value.hasSuffix($0) }) }) {
                failures.append(.init(artifact: "notification read state", reason: "Deleted meeting state remains"))
            }
        }
        if !fileManager.fileExists(atPath: inventory.modelsRoot.path) {
            // An absent model directory is valid. Its omission here is deliberate; never create or delete it.
        }
        return failures
    }

    private func write(_ journal: Journal) throws {
        var directory = inventory.journalURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(journal).write(to: inventory.journalURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func enumeratedLoosePrivateFiles() throws -> [URL] {
        var result: [URL] = []
        if fileManager.fileExists(atPath: inventory.documentsRoot.path) {
            let files = try fileManager.contentsOfDirectory(at: inventory.documentsRoot,
                                                             includingPropertiesForKeys: [.isRegularFileKey])
            result.append(contentsOf: files.filter {
                LocalRecordingStorage.audioExtensions.contains($0.pathExtension.lowercased())
            })
        }
        if fileManager.fileExists(atPath: inventory.temporaryRoot.path) {
            let files = try fileManager.contentsOfDirectory(at: inventory.temporaryRoot,
                                                             includingPropertiesForKeys: [.isRegularFileKey])
            result.append(contentsOf: files.filter {
                let name = $0.lastPathComponent
                return name.hasPrefix("Manent-") || name.hasPrefix("Minutes - ") ||
                    name.hasPrefix("mic-check-") || name.hasPrefix("voice_baseline_")
            })
        }
        result.append(inventory.temporaryRoot.appendingPathComponent("MeetMindAudioCache", isDirectory: true))
        return result
    }

    private func regularFiles(under root: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private func isOwned(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let roots = [inventory.documentsRoot, inventory.applicationSupportRoot, inventory.temporaryRoot]
            .map { $0.standardizedFileURL.path + "/" }
        guard roots.contains(where: { path.hasPrefix($0) }) else { return false }
        let models = inventory.modelsRoot.standardizedFileURL.path
        return path != models && !path.hasPrefix(models + "/") && path != inventory.journalURL.path
    }

    private func uniqueOwned(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { isOwned($0) && seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private func deduplicated(_ failures: [DeletionFailure]) -> [DeletionFailure] {
        var seen = Set<String>()
        return failures.filter { seen.insert("\($0.artifact)|\($0.reason)").inserted }
    }
}
