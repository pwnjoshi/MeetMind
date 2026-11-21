import SwiftUI

/// The saved minutes tab. It renders the same categorized record as the Minutes segment
/// (`MeetingMinutesView`), so there is one reading surface and one source of content.
public struct MeetingSummaryTabView: View {
    public let summary: Summary?
    public let actionItems: [ActionItem]

    public init(summary: Summary?, actionItems: [ActionItem] = []) {
        self.summary = summary
        self.actionItems = actionItems
    }

    public var body: some View {
        if let meeting = summary?.meeting {
            MeetingMinutesView(meeting: meeting)
        }
    }
}
