import BackgroundTasks
import Foundation
import OfflineEngineKit
import SwiftData
import UserNotifications
import OSLog

/// Resumes durable analysis jobs when iOS grants a processing window. The
/// scheduler is an adapter only; AnalysisCoordinator owns all production work.
@MainActor
enum OfflineAnalysisBackgroundScheduler {
    static let taskIdentifier = "com.meetmind.app.offline-analysis"
    private static let legacyPendingMeetingIDsKey = "MeetMind.pendingOfflineAnalysisIDs"
    private static let legacyImportKey = "MeetMind.pendingOfflineAnalysisIDs.imported-v2"
    private static var activeMeetingID: UUID?
    private static var activeStage: MeetingAnalysisStage?
    private static var applicationContainer: ModelContainer?
    private static var cachedJobs: [UUID: AnalysisJobRecord] = [:]
    private static let jobs = AnalysisJobStore.shared

    static func useApplicationContainer(_ container: ModelContainer?) {
        applicationContainer = container
        guard container != nil else { return }
        Task {
            await importLegacyQueueIfNeeded()
            await refreshCache()
        }
    }

    static func stage(for meetingID: UUID) -> MeetingAnalysisStage? {
        if ContinuedAnalysisRun.shared.isRunning(meetingID: meetingID) {
            return ContinuedAnalysisRun.shared.stage(for: meetingID)
        }
        return activeMeetingID == meetingID ? activeStage : nil
    }

    /// True while this meeting is processing anywhere: a run the person started
    /// (which continues after leaving its screen) or an iOS processing window.
    static func isRunning(meetingID: UUID) -> Bool {
        activeMeetingID == meetingID || ContinuedAnalysisRun.shared.isRunning(meetingID: meetingID)
    }

    static func status(for meetingID: UUID) -> String? {
        if ContinuedAnalysisRun.shared.isRunning(meetingID: meetingID) {
            switch ContinuedAnalysisRun.shared.stage(for: meetingID) {
            case .transcription: return "Transcribing"
            case .speakers: return "Identifying speakers"
            case .analysis: return "Writing minutes"
            case .completed: return "Saving minutes"
            case nil: return "Preparing on-device models"
            }
        }
        if activeMeetingID == meetingID {
            switch activeStage {
            case .transcription: return "Transcribing in background"
            case .speakers: return "Identifying speakers in background"
            case .analysis: return "Generating minutes in background"
            case .completed: return "Saving results in background"
            case nil: return "Preparing on-device models in background"
            }
        }
        guard let job = cachedJobs[meetingID] else { return nil }
        switch job.state {
        case .queued: return "Queued for background processing"
        case .needsModels: return "Queued until on-device models are ready"
        case .downloading: return "Downloading on-device models"
        case .verifying: return "Verifying on-device models"
        case .running: return "Processing in background"
        case .paused, .failed, .speakerReview, .completed: return nil
        }
    }

    /// Kept for app lifecycle compatibility. Model downloads now belong to a
    /// meeting job and never start only because the app entered background.
    static func scheduleInitialSetup() {
        Task {
            await refreshCache()
            if cachedJobs.values.contains(where: { $0.state == .queued }) { await submit() }
        }
    }

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in await handle(processingTask) }
        }
    }

    static func schedule(meetingID: UUID) {
        Task {
            guard let container = applicationContainer else {
                await persistSchedulerFailure(meetingID: meetingID)
                return
            }
            do {
                let coordinator = AnalysisCoordinator(context: container.mainContext, jobs: jobs)
                try await coordinator.enqueue(meetingID: meetingID,
                    languageCode: SettingsViewModel().savedRecordingLanguage.whisperCode,
                    model: VidurModel.selected)
                await refreshCache()
                await submit()
            } catch AnalysisJobStoreError.leaseConflict {
                // The foreground owner still has a live lease. Its cancellation
                // path will release the lease before a deliberate handoff.
                return
            } catch {
                await persistSchedulerFailure(meetingID: meetingID)
            }
        }
    }

    static func remove(meetingID: UUID) {
        // Removes the scheduler's presentation cache only. The durable job is
        // retained for recovery and diagnostics; a foreground claim changes its
        // state so it is no longer eligible for background execution.
        cachedJobs.removeValue(forKey: meetingID)
    }

    private static func submit() async {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = await queuedJobsRequireNetwork()
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // A second pending request already covers the same durable jobs.
            let nsError = error as NSError
            if nsError.code == BGTaskScheduler.Error.Code.tooManyPendingTaskRequests.rawValue { return }
            for record in cachedJobs.values where record.state == .queued {
                try? await jobs.setState(record.meetingID, state: .failed, stage: record.currentStage,
                                         failure: .stable(.schedulingFailed))
            }
            await refreshCache()
        }
    }

    private static func queuedJobsRequireNetwork() async -> Bool {
        let queued = cachedJobs.values.filter { $0.state == .queued || $0.state == .needsModels }
        guard !queued.isEmpty, let profiles = try? OfflineModelStore.profiles() else { return false }
        let IDs = Set(queued.flatMap { $0.requiredModels.map(\.id) })
        for profile in profiles where IDs.contains(profile.id) {
            if await OfflineModelStore.shared.readiness(profile) != .ready { return true }
        }
        return false
    }

    private static func handle(_ task: BGProcessingTask) async {
        var worker: Task<Void, Never>?
        task.expirationHandler = { worker?.cancel() }
        worker = Task { @MainActor in
            var succeeded = false
            defer {
                task.setTaskCompleted(success: succeeded)
                Task { @MainActor in
                    await refreshCache()
                    if cachedJobs.values.contains(where: { $0.state == .queued }) { await submit() }
                }
            }
            await importLegacyQueueIfNeeded()
            await refreshCache()
            // A run the person started is using the models; only one meeting runs at a time.
            guard !ContinuedAnalysisRun.shared.hasActiveRun else {
                succeeded = true
                return
            }
            guard let record = cachedJobs.values
                .filter({ $0.state == .queued })
                .sorted(by: { $0.createdAt < $1.createdAt }).first else {
                succeeded = true
                return
            }
            let meetingID = record.meetingID
            activeMeetingID = meetingID
            activeStage = nil
            defer { activeMeetingID = nil; activeStage = nil }
            do {
                guard let container = applicationContainer else {
                    throw AnalysisCoordinatorError.failed(.stable(.persistenceFailed))
                }
                let coordinator = AnalysisCoordinator(context: container.mainContext, jobs: jobs)
                let language = SettingsViewModel().savedRecordingLanguage.whisperCode
                let readiness = try await coordinator.modelStatus(meetingID: meetingID, model: VidurModel.selected)
                if readiness.contains(where: { $0.readiness != .ready }) {
                    try await coordinator.downloadAndVerify(meetingID: meetingID, model: VidurModel.selected,
                                                            progress: { _, _ in })
                }
                _ = try await coordinator.run(meetingID: meetingID, languageCode: language,
                    model: VidurModel.selected, owner: .background) { stage in activeStage = stage }
                succeeded = true
                let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingID })
                if let meeting = try container.mainContext.fetch(descriptor).first {
                    await postCompletionNotification(meetingID: meetingID, title: meeting.title)
                }
            } catch is CancellationError {
                do {
                    if let snapshot = try await jobs.get(meetingID) { _ = try await jobs.enqueue(snapshot) }
                } catch { }
            } catch {
                // Coordinator persists execution failures. Failures before a
                // coordinator claim still receive a stable scheduler record.
                do {
                    if let snapshot = try await jobs.get(meetingID), snapshot.state == .queued {
                        try await jobs.setState(meetingID, state: .failed, stage: snapshot.currentStage,
                                                failure: .stable(.schedulingFailed))
                    }
                } catch { }
            }
        }
        await worker?.value
    }

    static func legacyMeetingIDs(in defaults: UserDefaults) -> [UUID] {
        (defaults.stringArray(forKey: legacyPendingMeetingIDsKey) ?? []).compactMap(UUID.init(uuidString:))
    }

    private static func importLegacyQueueIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: legacyImportKey), let container = applicationContainer else { return }
        let ids = legacyMeetingIDs(in: .standard)
        let coordinator = AnalysisCoordinator(context: container.mainContext, jobs: jobs)
        var importedAll = true
        for id in ids {
            do {
                try await coordinator.enqueue(meetingID: id,
                    languageCode: SettingsViewModel().savedRecordingLanguage.whisperCode,
                    model: VidurModel.selected)
            } catch {
                importedAll = false
                await persistSchedulerFailure(meetingID: id)
            }
        }
        if importedAll {
            UserDefaults.standard.removeObject(forKey: legacyPendingMeetingIDsKey)
            UserDefaults.standard.set(true, forKey: legacyImportKey)
        }
    }

    private static func persistSchedulerFailure(meetingID: UUID) async {
        do {
            if let record = try await jobs.get(meetingID) {
                try await jobs.setState(meetingID, state: .failed, stage: record.currentStage,
                                        failure: .stable(.schedulingFailed))
            }
        } catch { }
        await refreshCache()
    }

    private static func refreshCache() async {
        do {
            let records = try await jobs.all()
            cachedJobs = Dictionary(uniqueKeysWithValues: records.map { ($0.meetingID, $0) })
        } catch {
            cachedJobs = [:]
            Logger(subsystem: "com.meetmind.app", category: "Analysis")
                .error("Analysis job store could not be read; code=jobStoreCorrupt")
        }
    }

    static func postCompletionNotification(meetingID: UUID, title: String) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Meeting ready"
        content.body = "\(title) has been transcribed and its minutes are ready to review."
        content.sound = .default
        content.userInfo = ["analysisMeetingID": meetingID.uuidString]
        let request = UNNotificationRequest(identifier: "MeetMind.analysis.\(meetingID.uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
