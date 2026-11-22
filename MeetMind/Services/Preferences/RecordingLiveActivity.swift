import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Attributes shared with a future Widget Extension (L1-L3).
public struct RecordingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var isPaused: Bool
        /// Start of the running timer, shifted forward by paused time.
        public var timerStart: Date
        public var pausedElapsed: TimeInterval

        public init(isPaused: Bool, timerStart: Date, pausedElapsed: TimeInterval) {
            self.isPaused = isPaused
            self.timerStart = timerStart
            self.pausedElapsed = pausedElapsed
        }
    }

    public var meetingTitle: String

    public init(meetingTitle: String) {
        self.meetingTitle = meetingTitle
    }
}

/// Starts, updates, and ends the recording Live Activity. Fails silently when
/// the app has no widget extension or Live Activities are disabled.
@MainActor
public final class RecordingLiveActivityController {
    public static let shared = RecordingLiveActivityController()
    private var activity: Activity<RecordingActivityAttributes>?

    public init() {}

    public func start(title: String, elapsed: TimeInterval) {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = RecordingActivityAttributes.ContentState(
            isPaused: false,
            timerStart: Date().addingTimeInterval(-elapsed),
            pausedElapsed: elapsed
        )
        activity = try? Activity.request(
            attributes: RecordingActivityAttributes(meetingTitle: title),
            content: .init(state: state, staleDate: nil)
        )
    }

    public func update(isPaused: Bool, elapsed: TimeInterval) {
        guard let activity else { return }
        let state = RecordingActivityAttributes.ContentState(
            isPaused: isPaused,
            timerStart: Date().addingTimeInterval(-elapsed),
            pausedElapsed: elapsed
        )
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    public func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
#else
@MainActor
public final class RecordingLiveActivityController {
    public static let shared = RecordingLiveActivityController()
    public init() {}
    public func start(title: String, elapsed: TimeInterval) {}
    public func update(isPaused: Bool, elapsed: TimeInterval) {}
    public func end() {}
}
#endif
