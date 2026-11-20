import SwiftUI
import SwiftData
import UIKit

/// One question and its answer as shown in the Vidur conversation.
private struct VidurConversationItem: Identifiable {
    let id = UUID()
    let prompt: String
    let answerText: String
    let citations: [VidurCitation]
    let kind: VidurAnswerKind?
    let notice: String?
}

/// Vidur: the local, on-device assistant that answers from saved transcripts.
///
/// Without `meeting` the sheet behaves as before and forwards questions to `onAsk`.
/// With `meeting` it answers itself for the chosen scope (this meeting, its series, all meetings).
public struct AskAIAssistantSheet: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    public let meetingTitle: String
    public let history: [(prompt: String, response: AIAnswerResponse)]
    public let onAsk: (String) -> Void
    public let onSeekToCitation: (AICitation) -> Void
    public let onDismiss: () -> Void
    public let isBusy: Bool
    public let meeting: Meeting?

    @State private var queryText: String = ""
    @State private var scope: VidurSearchScope = .thisMeeting
    @State private var localItems: [VidurConversationItem] = []
    @State private var isLocalBusy = false
    @State private var answerTask: Task<Void, Never>?

    public init(
        history: [(prompt: String, response: AIAnswerResponse)],
        onAsk: @escaping (String) -> Void,
        onSeekToCitation: @escaping (AICitation) -> Void,
        onDismiss: @escaping () -> Void,
        meetingTitle: String = "this meeting",
        isBusy: Bool = false,
        meeting: Meeting? = nil
    ) {
        self.meetingTitle = meetingTitle
        self.history = history
        self.onAsk = onAsk
        self.onSeekToCitation = onSeekToCitation
        self.onDismiss = onDismiss
        self.isBusy = isBusy
        self.meeting = meeting
    }

    private var busy: Bool { isBusy || isLocalBusy }

    private var items: [VidurConversationItem] {
        let legacy = history.map { pair in
            VidurConversationItem(
                prompt: pair.prompt,
                answerText: pair.response.answer,
                citations: pair.response.citations.map {
                    VidurCitation(meetingID: nil, meetingTitle: meetingTitle, timestamp: $0.timestamp, quote: $0.snippet)
                },
                kind: nil, notice: nil)
        }
        return legacy + localItems
    }

    private var subtitle: String {
        guard meeting != nil else { return meetingTitle }
        switch scope {
        case .thisMeeting: return meetingTitle
        case .thisMeetingAndSeries:
            return meeting?.seriesID == nil ? "\(meetingTitle) \u{00B7} not in a series" : "\(meetingTitle) and series"
        case .allMeetings: return "All meetings"
        }
    }

    public var body: some View {
        VStack(spacing: Spacing.sm) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.md) {
                    if items.isEmpty { emptyStateView }
                    ForEach(items) { item in
                        conversationView(item)
                    }
                    if busy {
                        HStack(spacing: Spacing.sm) {
                            ProgressView()
                            Text("Reading the transcript on this iPhone\u{2026}")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, Spacing.lg)
                    }
                    if !items.isEmpty {
                        Button("Open Meeting", action: onDismiss)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                    }
                }
                .padding(Spacing.lg)
            }
            inputBar
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .tint(Theme.Colors.manentAccent)
        .navigationTitle("Vidur")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text("Vidur").font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            if meeting != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Search", selection: $scope) {
                            ForEach(VidurSearchScope.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Search scope")
                }
            }
        }
        .onAppear { scope = VidurPreferences.shared.searchScope }
        .onChange(of: scope) { _, newScope in VidurPreferences.shared.searchScope = newScope }
        .onChange(of: scenePhase) { _, phase in if phase != .active { onDismiss() } }
        .onChange(of: busy) { _, isBusyNow in UIApplication.shared.isIdleTimerDisabled = isBusyNow }
        .onDisappear {
            answerTask?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: Empty state

    private var suggestions: [(question: String, detail: String)] {
        var list: [(question: String, detail: String)] = [
            ("What did we decide?", "Decisions and supporting audio"),
            ("Which actions did we agree on?", "Owners and due dates"),
            ("What is still unresolved?", "Open questions")
        ]
        if let meeting, scope != .thisMeeting, meeting.seriesID != nil {
            let name = meeting.seriesName ?? "this"
            list[2] = ("What changed since the last meeting?", "Across the \(name) series")
        }
        return list
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title).foregroundStyle(Theme.Colors.manentAccent)
                .frame(width: 68, height: 68)
                .background(Theme.Colors.manentAccent.opacity(0.08), in: Circle())
            Text("Ask About \(meetingTitle)").font(.title3.bold()).multilineTextAlignment(.center)
            Text(scopeExplanation)
                .foregroundStyle(.secondary).font(.subheadline).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 8) {
                Text("Suggested Questions").font(.subheadline).foregroundStyle(.secondary)
                    .padding(.leading, 16)
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { offset, suggestion in
                        Button { send(suggestion.question) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.question).foregroundStyle(.primary)
                                    Text(suggestion.detail).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        if offset < suggestions.count - 1 { Divider().padding(.horizontal, 16) }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 22))
            }
            .padding(.top, 32)
        }
        .frame(maxWidth: .infinity)
    }

    private var scopeExplanation: String {
        guard meeting != nil else { return "Answers come from this meeting\u{2019}s transcript." }
        switch scope {
        case .thisMeeting: return "Answers come from this meeting\u{2019}s transcript."
        case .thisMeetingAndSeries: return "Answers come from this meeting and earlier ones in its series."
        case .allMeetings: return "Answers come from every meeting saved on this iPhone."
        }
    }

    // MARK: Conversation

    @MainActor
    private func conversationView(_ item: VidurConversationItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.prompt)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(16)
                .background(Theme.Colors.manentAccent, in: RoundedRectangle(cornerRadius: 22))
                .frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .leading, spacing: 8) {
                Label("Vidur", systemImage: "sparkle")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.Colors.manentAccent)
                Text(item.answerText).textSelection(.enabled)
                if item.kind == .extractive {
                    Text("Matched by keyword from the transcript. Not generated.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let notice = item.notice {
                    Label(notice, systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 22))
            if VidurPreferences.shared.showsSources {
                ForEach(item.citations) { citation in
                    citationRow(citation)
                }
            }
        }
    }

    private func isCurrentMeeting(_ citation: VidurCitation) -> Bool {
        citation.meetingID == nil || citation.meetingID == meeting?.id
    }

    private func canPlay(_ citation: VidurCitation) -> Bool {
        isCurrentMeeting(citation) && (meeting?.hasAudio ?? true)
    }

    @ViewBuilder
    private func citationRow(_ citation: VidurCitation) -> some View {
        let heading = isCurrentMeeting(citation)
            ? "Source \u{00B7} \(citation.timecode)"
            : "\(citation.meetingTitle) \u{00B7} \(citation.timecode)"
        let detail = citation.quote.isEmpty ? "Play the supporting passage" : citation.quote
        if canPlay(citation) {
            Button {
                onSeekToCitation(AICitation(timestamp: citation.timestamp, segmentText: citation.quote))
            } label: {
                citationLabel(heading: heading, detail: detail, showsPlay: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Play the recording at this passage")
        } else {
            citationLabel(heading: heading, detail: detail, showsPlay: false)
        }
    }

    private func citationLabel(heading: String, detail: String, showsPlay: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(heading)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer()
            if showsPlay {
                Image(systemName: "play.circle").font(.title3).foregroundStyle(Theme.Colors.manentAccent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Input

    private var inputPlaceholder: String {
        if !items.isEmpty { return "Ask a follow-up" }
        switch scope {
        case .allMeetings where meeting != nil: return "Ask about your meetings"
        default: return "Ask about this meeting"
        }
    }

    private var inputBar: some View {
        HStack(spacing: Spacing.sm) {
            TextField(inputPlaceholder, text: $queryText)
                .textFieldStyle(.plain)
                .submitLabel(.send)
                .onSubmit { sendTyped() }
            Button { sendTyped() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 28)).foregroundStyle(Theme.Colors.manentAccent)
            }
            .disabled(busy || queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Ask Vidur")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule()).padding(.horizontal, 16)
        .padding(.bottom, Spacing.sm)
    }

    @MainActor
    private func sendTyped() {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !busy else { return }
        queryText = ""
        send(trimmed)
    }

    // MARK: Asking

    @MainActor
    private func send(_ question: String) {
        guard !busy else { return }
        guard let meeting else { onAsk(question); return }
        isLocalBusy = true
        let sources = sourceMeetings(for: meeting)
        let length = VidurPreferences.shared.answerLength
        let meetingID = meeting.id
        answerTask = Task { @MainActor in
            let answer = await VidurAnswerService.answer(question: question, sources: sources, length: length)
            guard !Task.isCancelled else { isLocalBusy = false; return }
            localItems.append(VidurConversationItem(
                prompt: question, answerText: answer.text, citations: answer.citations,
                kind: answer.kind, notice: answer.notice))
            if answer.isRecordable {
                VidurPreferences.shared.record(VidurHistoryEntry(meetingID: meetingID, question: question, answer: answer.text))
            }
            isLocalBusy = false
        }
    }

    @MainActor
    private func sourceMeetings(for meeting: Meeting) -> [VidurSourceMeeting] {
        let current = VidurSourceMeeting.make(from: meeting)
        switch scope {
        case .thisMeeting:
            return [current]
        case .thisMeetingAndSeries:
            guard let seriesID = meeting.seriesID else { return [current] }
            let context = meeting.modelContext ?? modelContext
            let all = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
            var related = all.filter { $0.seriesID == seriesID && $0.id != meeting.id }
            related.sort { $0.createdAt < $1.createdAt }
            return related.map { VidurSourceMeeting.make(from: $0) } + [current]
        case .allMeetings:
            let context = meeting.modelContext ?? modelContext
            let all = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
            var others = all.filter { $0.id != meeting.id }
            others.sort { $0.createdAt < $1.createdAt }
            return others.map { VidurSourceMeeting.make(from: $0) } + [current]
        }
    }
}
