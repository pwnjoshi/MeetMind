import SwiftUI
import SwiftData
import UIKit
import OfflineEngineKit

/// One question and its answer as shown in the Vidur conversation.
private struct VidurConversationItem: Identifiable {
    enum Phase { case searching, refining, done }

    let id = UUID()
    let prompt: String
    var answerText: String
    var citations: [VidurCitation]
    var kind: VidurAnswerKind?
    var notice: String?
    var tier: VidurAnswerTier = .none
    var people: [String] = []
    var relatedTasks: [VidurQuickTask] = []
    var suggestions: [String] = []
    var phase: Phase = .done

    init(prompt: String, answerText: String, citations: [VidurCitation], kind: VidurAnswerKind?,
         notice: String?, phase: Phase = .done) {
        self.prompt = prompt
        self.answerText = answerText
        self.citations = citations
        self.kind = kind
        self.notice = notice
        self.phase = phase
    }
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
    public let onOpenMeeting: (UUID) -> Void
    public let onDismiss: () -> Void
    public let isBusy: Bool
    public let meeting: Meeting?

    @State private var queryText: String = ""
    @State private var scope: VidurSearchScope = .thisMeeting
    @State private var localItems: [VidurConversationItem] = []
    @State private var isLocalBusy = false
    @State private var answerTask: Task<Void, Never>?
    @Environment(SettingsViewModel.self) private var settings: SettingsViewModel?

    public init(
        history: [(prompt: String, response: AIAnswerResponse)],
        onAsk: @escaping (String) -> Void,
        onSeekToCitation: @escaping (AICitation) -> Void,
        onOpenMeeting: @escaping (UUID) -> Void = { _ in },
        onDismiss: @escaping () -> Void,
        meetingTitle: String = "this meeting",
        isBusy: Bool = false,
        meeting: Meeting? = nil
    ) {
        self.meetingTitle = meetingTitle
        self.history = history
        self.onAsk = onAsk
        self.onSeekToCitation = onSeekToCitation
        self.onOpenMeeting = onOpenMeeting
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
                        conversationRow(item)
                    }
                    if isBusy {
                        HStack(spacing: Spacing.sm) {
                            ProgressView()
                            Text("Working on this iPhone\u{2026}")
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
            ToolbarItem(placement: .cancellationAction) {
                PrepCloseButton(action: onDismiss)
            }
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
        .onAppear {
            scope = VidurPreferences.shared.searchScope
            loadPersistedHistory()
            startPrewarm()
        }

        .onChange(of: scope) { _, newScope in VidurPreferences.shared.searchScope = newScope }
        .onChange(of: scenePhase) { _, phase in if phase != .active { onDismiss() } }
        .onChange(of: busy) { _, isBusyNow in UIApplication.shared.isIdleTimerDisabled = isBusyNow }
        .onDisappear {
            answerTask?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// Loads the on-device model while the user is typing, so the first refined answer is warm.
    /// Skipped while minutes are being generated; the engine also refuses then.
    @MainActor
    private func startPrewarm() {
        guard let meeting, meeting.status != .processing else { return }
        Task(priority: .utility) { await VidurTieredAnswerService.prewarm() }
    }

    @MainActor
    private func loadPersistedHistory() {
        guard localItems.isEmpty, let meeting else { return }
        localItems = VidurPreferences.shared.history(for: meeting.id).reversed().map { entry in
            VidurConversationItem(prompt: entry.question, answerText: entry.answer,
                                  citations: [], kind: nil, notice: "Saved on this iPhone")
        }
    }

    // MARK: Empty state

    private var suggestions: [String] {
        var list = [
            "What did we decide?",
            "Which actions did we agree on?",
            "What is still unresolved?"
        ]
        if let meeting, scope != .thisMeeting, meeting.seriesID != nil {
            list[2] = "What changed since the last meeting?"
        }
        return list
    }

    @MainActor
    private var recentQuestions: [VidurSuggestionList.Recent] {
        var entries = VidurPreferences.shared.history
        if let meeting, scope == .thisMeeting {
            entries = entries.filter { $0.meetingID == meeting.id }
        }
        var seen = Set<String>()
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        var result: [VidurSuggestionList.Recent] = []
        for entry in entries where seen.insert(entry.question).inserted {
            result.append(VidurSuggestionList.Recent(
                question: entry.question,
                when: formatter.localizedString(for: entry.askedAt, relativeTo: Date())))
            if result.count == 3 { break }
        }
        return result
    }

    @MainActor
    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.Colors.manentAccent, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(scope == .allMeetings && meeting != nil ? "Ask about your meetings" : "Ask About \(meetingTitle)")
                        .font(.subheadline.weight(.semibold))
                    Text(scopeExplanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Theme.Colors.manentAccent.opacity(0.14), Color.cyan.opacity(0.12)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .accessibilityElement(children: .combine)
            VidurSuggestionList(suggestions: suggestions, recent: recentQuestions) { question in
                send(question)
            }
            .disabled(busy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var scopeExplanation: String {
        guard meeting != nil else { return "Answers come from this meeting\u{2019}s minutes, transcript and notes." }
        switch scope {
        case .thisMeeting: return "Answers come from this meeting\u{2019}s minutes, transcript and notes."
        case .thisMeetingAndSeries: return "Answers come from the minutes, transcripts and notes of this meeting and its series."
        case .allMeetings: return "Answers come from the minutes, transcripts and notes of every meeting saved on this iPhone."
        }
    }

    // MARK: Conversation

    @MainActor
    private func conversationRow(_ item: VidurConversationItem) -> some View {
        let model = VidurAnswerCardModel(
            text: item.answerText,
            citations: item.citations,
            people: item.people,
            tasks: item.relatedTasks,
            suggestions: item.phase == .done ? item.suggestions : [],
            notice: item.notice,
            isQuick: item.tier == .structured || item.tier == .quote,
            isRefining: item.phase == .refining,
            currentMeetingID: meeting?.id)
        return VidurConversationRow(
            prompt: item.prompt,
            model: model,
            showsSources: VidurPreferences.shared.showsSources,
            now: Date(),
            onOpenSource: { openSource($0) },
            onOpenTask: { openTask($0) },
            onAsk: { send($0) })
            .animation(.easeOut(duration: 0.2), value: item.phase)
    }

    private func isCurrentMeeting(_ citation: VidurCitation) -> Bool {
        citation.meetingID == nil || citation.meetingID == meeting?.id
    }

    private func canPlay(_ citation: VidurCitation) -> Bool {
        citation.hasTimestamp && isCurrentMeeting(citation) && (meeting?.hasAudio ?? true)
    }

    /// Plays the recording at the cited moment, or opens the meeting the source came from.
    @MainActor
    private func openSource(_ citation: VidurCitation) {
        if canPlay(citation) {
            onSeekToCitation(AICitation(timestamp: citation.timestamp, segmentText: citation.quote))
        } else if let meetingID = citation.meetingID, meetingID != meeting?.id, meetingExists(meetingID) {
            onOpenMeeting(meetingID)
        }
    }

    /// Opens the meeting a task belongs to. Tasks of the current meeting close Vidur instead.
    @MainActor
    private func openTask(_ task: VidurQuickTask) {
        if task.meetingID == meeting?.id {
            onDismiss()
        } else if meetingExists(task.meetingID) {
            onOpenMeeting(task.meetingID)
        }
    }

    @MainActor
    private func meetingExists(_ id: UUID) -> Bool {
        let context = meeting?.modelContext ?? modelContext
        return ((try? context.fetch(FetchDescriptor<Meeting>())) ?? []).contains { $0.id == id }
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
            Image(systemName: "sparkle")
                .foregroundStyle(Theme.Colors.manentAccent)
                .accessibilityHidden(true)
            TextField(inputPlaceholder, text: $queryText)
                .textFieldStyle(.plain)
                .submitLabel(.send)
                .onSubmit { sendTyped() }
            Button { sendTyped() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 28)).foregroundStyle(Theme.Colors.manentAccent)
            }
            .disabled(isBusy || queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Ask Vidur")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule()).padding(.horizontal, 16)
        .padding(.bottom, Spacing.sm)
    }

    @MainActor
    private func sendTyped() {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        queryText = ""
        send(trimmed)
    }

    // MARK: Asking

    @MainActor
    private func send(_ question: String) {
        guard !isBusy else { return }
        guard let meeting else { onAsk(question); return }
        // A new question stops the previous one. Its best answer so far stays in the conversation.
        answerTask?.cancel()
        settlePendingItems()
        let sources = sourceMeetings(for: meeting)
        // Saved minutes feed the instant tier for this meeting only. Wider scopes still give the
        // deep answer the minutes of every meeting in scope.
        let current = VidurMeetingFacts.make(from: meeting)
        let facts: VidurMeetingFacts? = scope == .thisMeeting ? current : nil
        let extraFacts: [VidurMeetingFacts] = scope == .thisMeeting ? [] : otherMeetingFacts(for: meeting, current: current)
        let request = VidurTieredRequest(
            question: question, sources: sources, facts: facts, length: VidurPreferences.shared.answerLength,
            allowRefinement: meeting.status != .processing, additionalFacts: extraFacts,
            history: conversationHistory(),
            userDisabledRefinement: !VidurDeepAnswerSetting.isEnabled,
            selfNames: [settings?.userProfile?.name ?? UserProfile.defaultLocalName])
        let item = VidurConversationItem(prompt: question, answerText: "", citations: [], kind: nil, notice: nil,
                                         phase: .searching)
        let itemID = item.id
        let meetingID = meeting.id
        localItems.append(item)
        isLocalBusy = true
        answerTask = Task { @MainActor in
            for await update in VidurTieredAnswerService.stream(request) {
                guard !Task.isCancelled else { return }
                apply(update, itemID: itemID, meetingID: meetingID, question: question)
            }
            if !Task.isCancelled, let index = localItems.firstIndex(where: { $0.id == itemID }),
               localItems[index].phase != .done {
                settlePendingItems()
            }
            if !Task.isCancelled { isLocalBusy = false }
        }
    }

    @MainActor
    private func apply(_ update: VidurAnswerUpdate, itemID: UUID, meetingID: UUID, question: String) {
        guard let index = localItems.firstIndex(where: { $0.id == itemID }) else { return }
        if let answer = update.answer {
            localItems[index].answerText = answer.text
            localItems[index].citations = answer.citations
            localItems[index].kind = answer.kind
            localItems[index].notice = answer.notice
            localItems[index].people = answer.people
            localItems[index].relatedTasks = answer.relatedTasks
            localItems[index].suggestions = answer.suggestions
        }
        localItems[index].tier = update.tier
        switch update.stage {
        case .instant, .refining:
            localItems[index].phase = .refining
        case .final:
            localItems[index].phase = .done
            if let answer = update.answer, answer.isRecordable {
                VidurPreferences.shared.record(VidurHistoryEntry(meetingID: meetingID, question: question, answer: answer.text))
            }
            isLocalBusy = false
        }
    }

    /// Ends any answer that was still running: keeps what it has, drops an empty placeholder.
    @MainActor
    private func settlePendingItems() {
        localItems.removeAll { $0.phase != .done && $0.answerText.isEmpty }
        for index in localItems.indices where localItems[index].phase != .done {
            localItems[index].phase = .done
            localItems[index].notice = "Stopped before refinement finished."
        }
        isLocalBusy = false
    }
    /// The last two finished question and answer pairs, so "aur Neha ne?" follows the previous question.
    @MainActor
    private func conversationHistory() -> [VidurChatTurn] {
        let usable = localItems.filter { item in
            guard item.phase == .done, !item.answerText.isEmpty else { return false }
            return item.kind != .failed && item.kind != .unavailable
        }
        return usable.suffix(2).map { VidurChatTurn(question: $0.prompt, answer: $0.answerText) }
    }

    /// Minutes of the other meetings in scope (the 20 most recent), with the current meeting last.
    @MainActor
    private func otherMeetingFacts(for meeting: Meeting, current: VidurMeetingFacts) -> [VidurMeetingFacts] {
        let context = meeting.modelContext ?? modelContext
        let all = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
        var others: [Meeting]
        switch scope {
        case .thisMeeting:
            return []
        case .thisMeetingAndSeries:
            guard let seriesID = meeting.seriesID else { return [current] }
            others = all.filter { $0.seriesID == seriesID && $0.id != meeting.id }
        case .allMeetings:
            others = all.filter { $0.id != meeting.id }
        }
        others.sort { $0.createdAt < $1.createdAt }
        return others.suffix(20).map { VidurMeetingFacts.make(from: $0) } + [current]
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
