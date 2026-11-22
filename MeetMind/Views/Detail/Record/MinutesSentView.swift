import SwiftUI

/// Animated post-share screen (Figma 161:1912 "Delivery status" to 1925:12 "Minutes Sent settled").
/// It is only shown after Mail reported `.sent` or a share activity completed, and it never claims that a
/// recipient received or opened the minutes. With Reduce Motion it appears in its settled state.
struct MinutesSentView: View {
    let state: MinutesSentState
    let entry: SharedMinutesEntry?
    let meeting: Meeting?
    let onBackToMeetings: () -> Void
    var startsSettled: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: MinutesSentPhase = .handoff
    @State private var followUpDraft: MeetingSetupViewModel?
    @State private var showFollowUp = false
    @State private var scheduledTitle: String?
    @State private var openedEntry: SharedMinutesEntry?

    private var animated: Bool { !reduceMotion }
    private var headline: String { phase == .handoff ? state.handoffText : state.title }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            MinutesCelebrationView(recipients: state.recipients, phase: phase, animated: animated)
            textBlock
            Spacer(minLength: 0)
            actions
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .sensoryFeedback(.success, trigger: phase) { old, new in old == .handoff && new != .handoff }
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
        .navigationDestination(item: $openedEntry) { shared in
            SharedMinutesView(entry: shared)
        }
    }

    // MARK: - Text

    private var textBlock: some View {
        VStack(spacing: 8) {
            Text(headline)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .id(headline)
                .transition(.opacity)
            if phase.isDone {
                statusChip.transition(.opacity.combined(with: .scale(scale: 0.9)))
                Text(state.message)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(animated ? .easeOut(duration: 0.3) : .easeInOut(duration: 0.2), value: phase)
        .accessibilityElement(children: .combine)
    }

    private var statusChip: some View {
        Label(state.settledText, systemImage: state.settledSymbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.Colors.manentAccent)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.Colors.manentAccent.opacity(0.12), in: Capsule())
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 10) {
            primaryAction
            if let entry {
                Button { openedEntry = entry } label: {
                    HStack {
                        Label("View Shared Minutes", systemImage: "doc.text")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                    }
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                    .background(.background, in: RoundedRectangle(cornerRadius: 24))
                }
                .buttonStyle(.plain)
            }
            Button("Back to Meetings", action: onBackToMeetings)
                .font(.body)
                .frame(minHeight: 44)
                .foregroundStyle(Theme.Colors.manentAccent)
        }
        .opacity(phase.isDone ? 1 : 0)
        .offset(y: phase.isDone || !animated ? 0 : 24)
        .animation(animated ? .easeOut(duration: 0.3).delay(0.25) : nil, value: phase.isDone)
        .allowsHitTesting(phase.isDone)
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

    /// Figma: hand-off beat, then the check lands with the burst, then everything is settled at 2.9 s.
    private func runTimeline() async {
        if startsSettled || reduceMotion {
            phase = .settled
            announce()
            return
        }
        try? await Task.sleep(for: .milliseconds(900))
        phase = .celebrating
        announce()
        try? await Task.sleep(for: .milliseconds(2000))
        phase = .settled
    }

    private func announce() {
        AccessibilityNotification.Announcement("\(state.title). \(state.settledText).").post()
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
