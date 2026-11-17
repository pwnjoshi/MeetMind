import SwiftUI
import SwiftData

/// Dynamic container routing to LiveRecordingView if recording or MeetingDetailView if completed/scheduled
public struct MeetingDetailContainerView: View {
    @Environment(\.modelContext) private var modelContext
    public let meetingId: UUID
    
    @Query private var meetings: [Meeting]
    
    public init(meetingId: UUID) {
        self.meetingId = meetingId
    }
    
    private var targetMeeting: Meeting? {
        meetings.first(where: { $0.id == meetingId })
    }
    
    public var body: some View {
        Group {
            if let meeting = targetMeeting, meeting.status == .recording, meeting.audioFileURL == nil {
                LiveRecordingView(meetingId: meetingId, viewModel: LiveRecordingViewModel(meeting: meeting, meetingId: meetingId, modelContext: modelContext))
            } else {
                MeetingDetailView(viewModel: MeetingDetailViewModel(meeting: targetMeeting, meetingId: meetingId, modelContext: modelContext))
            }
        }
    }
}
