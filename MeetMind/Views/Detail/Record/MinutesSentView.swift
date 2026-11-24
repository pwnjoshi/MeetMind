import SwiftUI

/// Post-send screen (Figma B9 animating into B10 "Minutes Sent"). It is only shown after Mail reported `.sent`
/// or a share activity completed. With Reduce Motion it appears in its settled state.
/// Sequence: halo fades in, the green disc springs in, the check draws on with a soft haptic, the recipient
/// bubbles pop out one after another, then the text and buttons appear.
struct MinutesSentView: View {
    let state: MinutesSentState
    let meeting: Meeting?
    let onBackToMeetings: () -> Void
    var startsSettled: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage: MinutesSentStage = .initial
    @State private var followUpDraft: MeetingSetupViewModel?
    @State private var showFollowUp = false
    @State private var scheduledTitle: String?

    private var animated: Bool { !reduceMotion && !startsSettled }
    private var textVisible: Bool { stage >= .check }
    private var actionsVisible: Bool { stage >= .done }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            MinutesCelebrationView(recipients: state.recipients, stage: stage, animated: animated)
            textBlock
            Spacer(minLength: 0)
            actions
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .sensoryFeedback(.success, trigger: stage) { _, new in new == .check && animated }
        .sensoryFeedback(.success, trigger: scheduledTitle) { _, new in new != nil }
        .task { @MainActor in await runTimeline() }
        .sheet(isPresented: $showFollowUp, onDismiss: { followUpDraft = nil }) {
            if let followUpDraft {
                ScheduleMeetingView(viewModel: followUpDraft, onMeetingScheduled: { scheduled in
                    scheduledTitle = scheduled.title
                })
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Text

    private var textBlock: some View {
        VStack(spacing: 8) {
            Text(state.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(state.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .opacity(textVisible ? 1 : 0)
        .offset(y: textVisible || !animated ? 0 : 8)
        .animation(animated ? .easeOut(duration: 0.35) : nil, value: textVisible)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 10) {
            primaryAction
            Button("Back to Meetings", action: onBackToMeetings)
                .font(.body)
                .frame(minHeight: 44)
                .foregroundStyle(Theme.Colors.manentAccent)
        }
        .opacity(actionsVisible ? 1 : 0)
        .offset(y: actionsVisible || !animated ? 0 : 24)
        .animation(animated ? .easeOut(duration: 0.3) : nil, value: actionsVisible)
        .allowsHitTesting(actionsVisible)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if let scheduledTitle {
            Label("Next meeting scheduled: \(scheduledTitle)", systemImage: "calendar.badge.checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Colors.manentAccent)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.Colors.manentAccent.opacity(0.12), in: Capsule())
                .accessibilityElement(children: .combine)
        } else {
            Button(action: planNextMeeting) {
                Text("Plan Next Meeting")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.white)
                    .background(Theme.Colors.manentAccent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Behaviour

    private func runTimeline() async {
        if !animated {
            stage = .done
            announce()
            return
        }
        let steps: [(MinutesSentStage, Int)] = [(.halo, 60), (.disc, 280), (.check, 380), (.avatars, 450), (.done, 450)]
        for step in steps {
            try? await Task.sleep(for: .milliseconds(step.1))
            if Task.isCancelled { return }
            stage = step.0
        }
        announce()
    }

    private func announce() {
        AccessibilityNotification.Announcement("\(state.title). \(state.message)").post()
    }

    private func planNextMeeting() {
        followUpDraft = MinutesFollowUpDraft.make(from: meeting, modelContext: modelContext)
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
