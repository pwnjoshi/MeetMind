import SwiftUI
import SwiftData

/// The only UUID-to-screen resolver. Call sites open a meeting ID and this
/// container derives the canonical destination from persisted meeting content.
@MainActor
public struct MeetingDetailContainerView: View {
    @Environment(\.modelContext) private var modelContext
    public let meetingId: UUID

    @Query private var meetings: [Meeting]
    @State private var reviewStore = ReviewStateStore.shared
    @State private var reviewError: String?

    public init(meetingId: UUID) {
        self.meetingId = meetingId
    }

    private var meeting: Meeting? {
        meetings.first(where: { $0.id == meetingId })
    }

    private var reviewState: ReviewStateRecord? {
        try? reviewStore.record(for: meetingId)
    }

    private var resolution: MeetingLifecycleResolution? {
        meeting.map { MeetingLifecycleResolver.resolve(meeting: $0, reviewState: reviewState) }
    }

    public var body: some View {
        Group {
            if let reviewError {
                ContentUnavailableView {
                    Label("Review State Unavailable", systemImage: "doc.badge.exclamationmark")
                } description: {
                    Text(reviewError)
                } actions: {
                    Button("Try Again") { loadReviewState() }
                        .buttonStyle(.borderedProminent)
                }
            } else if let meeting, let resolution {
                destination(resolution.destination, meeting: meeting)
            } else {
                ContentUnavailableView(
                    "Meeting Unavailable",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("This meeting may have been deleted or its local record could not be loaded.")
                )
            }
        }
        .task(id: meeting?.id) { loadReviewState() }
    }

    private func loadReviewState() {
        guard let meeting else { return }
        do {
            let state = try reviewStore.record(for: meeting.id)
            reviewError = nil
            let current = MeetingLifecycleResolver.resolve(meeting: meeting, reviewState: state)
            if current.isLegacyFinalized {
                try reviewStore.bootstrapFinalization(
                    meetingID: meeting.id,
                    fingerprint: MinutesReviewContentSnapshot.make(from: meeting).fingerprint
                )
            }
        } catch {
            reviewError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func destination(_ destination: MeetingDestination, meeting: Meeting) -> some View {
        switch destination {
        case .plan, .captureSetup:
            ScheduledMeetingDetailView(meeting: meeting)
        case .recording:
            LiveRecordingView(
                meetingId: meetingId,
                viewModel: LiveRecordingViewModel(meeting: meeting, meetingId: meetingId, modelContext: modelContext)
            )
        case .processing:
            MeetingProcessingView(meetingId: meetingId)
        case .reviewChecklist:
            MinutesReviewChecklistView(meeting: meeting)
        case .finalMinutes:
            MeetingDetailView(
                viewModel: MeetingDetailViewModel(meeting: meeting, meetingId: meetingId, modelContext: modelContext)
            )
        }
    }
}
