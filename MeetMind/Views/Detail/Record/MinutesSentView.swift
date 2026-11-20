import SwiftUI

/// "Minutes Sent" (Delivery status → settled). Shown after the user finished sending from Mail or the share sheet.
/// It states what the user did. It does not claim anyone opened the minutes.
struct MinutesSentView: View {
    let recipients: [SharedMinutesRecipient]
    let message: String
    let meeting: Meeting?
    let onBackToMeetings: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false
    @State private var followUpDraft: MeetingSetupViewModel?
    @State private var showFollowUp = false

    private static let offsets: [CGSize] = [
        CGSize(width: -150, height: -70), CGSize(width: 110, height: -70),
        CGSize(width: -120, height: 92), CGSize(width: 96, height: 92)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.Colors.manentAccent.opacity(0.18))
                    .frame(width: 250, height: 250)
                    .blur(radius: 36)
                ForEach(Array(recipients.prefix(Self.offsets.count).enumerated()), id: \.offset) { entry in
                    Text(MeetingRecordInitials.initials(entry.element.name))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color(hex: entry.element.colorHex), in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .offset(Self.offsets[entry.offset])
                        .scaleEffect(settled ? 1 : 0.4)
                        .opacity(settled ? 1 : 0)
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 112, height: 112)
                    .background(Color(red: 0.2, green: 0.78, blue: 0.35), in: Circle())
                    .shadow(color: Color.green.opacity(0.35), radius: 18)
                    .scaleEffect(settled ? 1 : 0.6)
            }
            .frame(height: 300)
            .accessibilityHidden(true)
            Text("Minutes Sent").font(.title3.bold()).padding(.top, 8)
            Text(message)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 46).padding(.top, 8)
            Spacer()
            Button(action: planNextMeeting) {
                Text("Plan Next Meeting").frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(.white)
                    .background(Theme.Colors.manentAccent, in: Capsule())
            }
            .buttonStyle(.plain)
            Button("Back to Meetings", action: onBackToMeetings)
                .frame(minHeight: 54)
                .foregroundStyle(Theme.Colors.manentAccent)
        }
        .padding(.horizontal, 16)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .onAppear {
            if reduceMotion {
                settled = true
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { settled = true }
            }
        }
        .sheet(isPresented: $showFollowUp, onDismiss: { followUpDraft = nil }) {
            if let followUpDraft {
                ScheduleMeetingView(viewModel: followUpDraft)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func planNextMeeting() {
        let draft = MeetingSetupViewModel(modelContext: modelContext)
        if let meeting {
            draft.title = meeting.seriesName ?? "\(meeting.title) follow-up"
            draft.scheduledSeriesID = meeting.seriesID
            draft.scheduledSeriesName = meeting.seriesName
            draft.variant = .followUp
            draft.followUpSource = meeting
        }
        followUpDraft = draft
        showFollowUp = true
    }
}

enum MeetingRecordInitials {
    /// Two-letter initials of a person's name, skipping titles such as "Dr.".
    static func initials(_ name: String) -> String {
        let first = MeetingRecordFormatting.firstName(name)
        let parts = name.split(separator: " ").map(String.init)
        if let last = parts.last, parts.count > 1, last != first,
           let a = first.first, let b = last.first {
            return "\(a)\(b)".uppercased()
        }
        return String(first.prefix(2)).uppercased()
    }
}
