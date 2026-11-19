import BackgroundTasks
import Foundation
import SwiftData
import UserNotifications

/// Resumes a saved offline-analysis checkpoint when iOS grants a processing
/// window. This is deliberately opportunistic: iOS may defer or decline a
/// request, so foreground analysis remains the fast path and checkpoints make
/// either path safe to resume.
@MainActor
enum OfflineAnalysisBackgroundScheduler {
    static let taskIdentifier = "com.meetmind.app.offline-analysis"
    private static let pendingMeetingIDsKey = "MeetMind.pendingOfflineAnalysisIDs"

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
        var ids = pendingMeetingIDs
        if !ids.contains(meetingID.uuidString) { ids.append(meetingID.uuidString) }
        UserDefaults.standard.set(ids, forKey: pendingMeetingIDsKey)

        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        // Begin promptly if iOS has thermal and battery headroom; there is no
        // promise of an exact start time under iOS background scheduling.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { /* An equivalent queued request is normal; saved IDs remain. */ }
    }

    static func remove(meetingID: UUID) {
        UserDefaults.standard.set(pendingMeetingIDs.filter { $0 != meetingID.uuidString }, forKey: pendingMeetingIDsKey)
    }

    private static var pendingMeetingIDs: [String] {
        UserDefaults.standard.stringArray(forKey: pendingMeetingIDsKey) ?? []
    }

    private static func handle(_ task: BGProcessingTask) async {
        var worker: Task<Void, Never>?
        task.expirationHandler = { worker?.cancel() }
        worker = Task { @MainActor in
            var succeeded = false
            defer { task.setTaskCompleted(success: succeeded) }
            guard let rawID = pendingMeetingIDs.first, let meetingID = UUID(uuidString: rawID) else { return }
            do {
                let container = try ModelContainerFactory.createProductionContainer()
                let context = container.mainContext
                var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingID })
                descriptor.fetchLimit = 1
                guard let meeting = try context.fetch(descriptor).first else { remove(meetingID: meetingID); return }
                let viewModel = ProcessingPipelineViewModel(meeting: meeting, modelContext: context)
                try viewModel.prepareForProduction(context: context, settings: SettingsViewModel())
                guard try await viewModel.missingOfflineModels().isEmpty else { return }
                try await viewModel.startPipeline()
                guard viewModel.pipelineStatus == .completed else { return }
                remove(meetingID: meetingID)
                succeeded = true
                await postCompletionNotification(for: meeting.title)
            } catch is CancellationError {
                // The engine wrote a checkpoint before interruption. Leave it
                // queued so the user or a later iOS window can resume safely.
            } catch {
                // Keep the checkpoint/queue; a malformed or missing recording
                // remains visible in the app and is never silently discarded.
            }
        }
        await worker?.value
    }

    private static func postCompletionNotification(for title: String) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Meeting ready"
        content.body = "\(title) has been transcribed and its minutes are ready to review."
        content.sound = .default
        content.userInfo = ["meetingTitle": title]
        let request = UNNotificationRequest(identifier: "MeetMind.analysis.\(UUID().uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
