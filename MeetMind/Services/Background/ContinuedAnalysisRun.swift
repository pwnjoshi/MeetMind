import BackgroundTasks
import Foundation
import OfflineEngineKit
import OSLog
import UIKit

/// Owns a meeting analysis the person started, for the life of the app rather than
/// the life of a screen. Leaving the processing screen never stops it.
///
/// On iOS 26 and later the run is also registered as a continued-processing task, so
/// iOS keeps it running after the person leaves the app and shows its progress in a
/// system Live Activity, where it can also be stopped. iPhone apps get no GPU in the
/// background, so the engine moves model work to the CPU and Neural Engine there
/// (see `ComputeEnvironment`). On earlier iOS versions the run gets the short UIKit
/// background grace period and, if that expires, resumes in an iOS processing window.
@MainActor
final class ContinuedAnalysisRun {
    static let shared = ContinuedAnalysisRun()

    private struct Active {
        let meetingID: UUID
        let title: String
        let token: UUID
        let task: Task<Void, Never>
        var stage: MeetingAnalysisStage?
        /// `BGContinuedProcessingTask` once iOS starts it (iOS 26+).
        var systemTask: AnyObject?
        var requestIdentifier: String?
        var expired = false
    }

    private var active: Active?
    private var ticker: Task<Void, Never>?
    private var graceTask: UIBackgroundTaskIdentifier = .invalid
    private let log = Logger(subsystem: "com.meetmind.app", category: "Analysis")

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ContinuedAnalysisRun.shared.didEnterBackground() }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ContinuedAnalysisRun.shared.endGracePeriod() }
        }
    }

    func isRunning(meetingID: UUID) -> Bool { active?.meetingID == meetingID }

    var hasActiveRun: Bool { active != nil }

    func stage(for meetingID: UUID) -> MeetingAnalysisStage? {
        active?.meetingID == meetingID ? active?.stage : nil
    }

    /// Starts `work`, which returns true when the meeting finished successfully.
    /// Returns nil when another meeting is already running; only one runs at a time
    /// because each stage needs most of the device's memory.
    @discardableResult
    func start(meetingID: UUID, title: String, work: @escaping @MainActor () async -> Bool) -> Task<Void, Never>? {
        guard active == nil else { return nil }
        let token = UUID()
        let task = Task { @MainActor in
            let succeeded = await work()
            ContinuedAnalysisRun.shared.finish(token: token, succeeded: succeeded)
        }
        active = Active(meetingID: meetingID, title: title, token: token, task: task)
        if #available(iOS 26.0, *) { submitContinuedTask(token: token, title: title) }
        if UIApplication.shared.applicationState == .background { didEnterBackground() }
        return task
    }

    func report(_ stage: MeetingAnalysisStage, meetingID: UUID) {
        guard var run = active, run.meetingID == meetingID else { return }
        run.stage = stage
        active = run
        updateSystemProgress()
    }

    func cancel(meetingID: UUID) {
        guard let run = active, run.meetingID == meetingID else { return }
        run.task.cancel()
    }

    // MARK: Finishing

    private func finish(token: UUID, succeeded: Bool) {
        guard let run = active, run.token == token else { return }
        active = nil
        ticker?.cancel()
        ticker = nil
        if #available(iOS 26.0, *) {
            if let task = run.systemTask as? BGContinuedProcessingTask {
                if succeeded { task.progress.completedUnitCount = task.progress.totalUnitCount }
                task.setTaskCompleted(success: succeeded && !run.expired)
            } else if let identifier = run.requestIdentifier {
                // iOS never started the request; withdraw it.
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            }
        }
        endGracePeriod()
        log.notice("Continued analysis finished succeeded=\(succeeded, privacy: .public) expired=\(run.expired, privacy: .public) app_active=\(UIApplication.shared.applicationState == .active, privacy: .public)")
        if succeeded, UIApplication.shared.applicationState != .active {
            let meetingID = run.meetingID, title = run.title
            Task { await OfflineAnalysisBackgroundScheduler.postCompletionNotification(meetingID: meetingID, title: title) }
        }
        if run.expired, !succeeded {
            // Stopped by iOS or from the Live Activity. Completed stages are saved;
            // the rest resumes in the next iOS processing window or on Resume.
            let meetingID = run.meetingID
            Task { @MainActor in
                await run.task.value
                OfflineAnalysisBackgroundScheduler.schedule(meetingID: meetingID)
            }
        }
    }

    // MARK: iOS 26 continued processing

    /// Identifier for one run, prefixed by a pattern listed under
    /// BGTaskSchedulerPermittedIdentifiers. Registering an unlisted identifier is a
    /// programming error that iOS raises as an exception, so it is checked first.
    nonisolated static func continuedTaskIdentifier(bundleIdentifier: String?, permitted: [String], suffix: String) -> String? {
        let name = "continued-analysis.\(suffix)"
        let candidates = [bundleIdentifier.map { "\($0).\(name)" }, "com.meetmind.app.\(name)"].compactMap { $0 }
        return candidates.first { candidate in
            permitted.contains { pattern in
                pattern.hasSuffix("*") ? candidate.hasPrefix(String(pattern.dropLast())) : pattern == candidate
            }
        }
    }

    @available(iOS 26.0, *)
    private func submitContinuedTask(token: UUID, title: String) {
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        guard let identifier = Self.continuedTaskIdentifier(bundleIdentifier: Bundle.main.bundleIdentifier,
                                                            permitted: permitted,
                                                            suffix: token.uuidString.lowercased()) else {
            log.error("Continued analysis unavailable: no permitted identifier")
            return
        }
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated {
                guard let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                ContinuedAnalysisRun.shared.attach(task, token: token)
            }
        }
        guard registered else {
            log.error("Continued analysis unavailable: registration refused")
            return
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title,
                                                       subtitle: Self.subtitle(for: nil))
        // Start now or not at all; a queued request would start after the work is done.
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
            active?.requestIdentifier = identifier
        } catch {
            log.error("Continued analysis submit failed: \((error as NSError).code, privacy: .public)")
        }
    }

    @available(iOS 26.0, *)
    private func attach(_ task: BGContinuedProcessingTask, token: UUID) {
        guard var run = active, run.token == token else {
            // The run finished before iOS started the task.
            task.setTaskCompleted(success: true)
            return
        }
        task.expirationHandler = {
            Task { @MainActor in ContinuedAnalysisRun.shared.systemExpired(token: token) }
        }
        task.progress.totalUnitCount = 100
        run.systemTask = task
        active = run
        endGracePeriod()
        updateSystemProgress()
        startTicker()
    }

    private func systemExpired(token: UUID) {
        guard var run = active, run.token == token else { return }
        run.expired = true
        active = run
        log.notice("Continued analysis expired; pausing at the last saved step")
        run.task.cancel()
    }

    /// Stage bands of the 0-100 progress shown by iOS. Within a stage progress moves
    /// slowly toward the band's end while work continues, so iOS does not treat a
    /// long transcription as stuck. It never reaches the next stage early.
    private static func band(for stage: MeetingAnalysisStage?) -> ClosedRange<Int64> {
        switch stage {
        case nil: return 0...5
        case .transcription: return 5...40
        case .speakers: return 40...55
        case .analysis: return 55...97
        case .completed: return 97...100
        }
    }

    private static func subtitle(for stage: MeetingAnalysisStage?) -> String {
        switch stage {
        case nil: return "Preparing on-device models"
        case .transcription: return "Transcribing the recording"
        case .speakers: return "Identifying speakers"
        case .analysis: return "Writing minutes"
        case .completed: return "Saving minutes"
        }
    }

    private func updateSystemProgress() {
        guard #available(iOS 26.0, *) else { return }
        guard let run = active, let task = run.systemTask as? BGContinuedProcessingTask else { return }
        let band = Self.band(for: run.stage)
        let current = task.progress.completedUnitCount
        task.progress.completedUnitCount = min(max(current, band.lowerBound), band.upperBound)
        task.updateTitle(run.title, subtitle: Self.subtitle(for: run.stage))
    }

    private func startTicker() {
        guard #available(iOS 26.0, *) else { return }
        ticker?.cancel()
        ticker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let run = ContinuedAnalysisRun.shared.active,
                      let task = run.systemTask as? BGContinuedProcessingTask else { continue }
                let band = ContinuedAnalysisRun.band(for: run.stage)
                if task.progress.completedUnitCount < band.upperBound - 1 {
                    task.progress.completedUnitCount += 1
                }
            }
        }
    }

    // MARK: Earlier iOS versions, or when iOS declined the continued task

    private func didEnterBackground() {
        guard let run = active, run.systemTask == nil, graceTask == .invalid else { return }
        let token = run.token
        graceTask = UIApplication.shared.beginBackgroundTask(withName: "Meeting analysis") {
            MainActor.assumeIsolated { ContinuedAnalysisRun.shared.gracePeriodExpired(token: token) }
        }
    }

    private func gracePeriodExpired(token: UUID) {
        if var run = active, run.token == token {
            run.expired = true
            active = run
            run.task.cancel()
        }
        endGracePeriod()
    }

    private func endGracePeriod() {
        guard graceTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(graceTask)
        graceTask = .invalid
    }
}
