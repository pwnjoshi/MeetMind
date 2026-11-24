import SwiftUI
import SwiftData
import UIKit
import OfflineEngineKit

/// One thing the user said and Vidur's reply: an answer, a short chat reply, or a confirmation card.
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
    /// A short chat reply (hello, thanks, a refusal). It never counts as an answer about a meeting.
    var isNote = false
    /// A change Vidur wants to make, shown as a confirmation card.
    var pending: VidurPendingAction?
    var pendingIntro = ""
    var pendingState: VidurPendingState = .awaiting
    var result: VidurActionResult?

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

/// Vidur: the on-device meeting assistant. It chats, answers from saved meetings, runs commands
/// (schedule, add or finish an action, open a meeting, start a recording, star a meeting) after
/// asking for confirmation. Answers are retrieval based: Vidur finds the matching minutes and transcript
/// passages first, then writes the reply from them. Everything runs on this iPhone.
///
/// Without `meeting` the sheet behaves as before and forwards questions to `onAsk`.
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
    @State private var persistScope = true
    @State private var localItems: [VidurConversationItem] = []
    @State private var isLocalBusy = false
    @State private var answerTask: Task<Void, Never>?
    @State private var assistant = VidurAssistantContext()
    @State private var showsSettings = false
    @Environment(SettingsViewModel.self) private var settings: SettingsViewModel?
    @Environment(AppState.self) private var appState: AppState?
    @Environment(NavigationRouter.self) private var router: NavigationRouter?

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

    @MainActor private var isRecordingActive: Bool { appState?.isRecordingActive ?? false }
    @MainActor private var dataContext: ModelContext { meeting?.modelContext ?? modelContext }
    @MainActor private var selfNames: [String] { [settings?.userProfile?.name ?? UserProfile.defaultLocalName] }

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

    // MARK: Body

    public var body: some View {
        VStack(spacing: Spacing.sm) {
            ScrollViewReader { proxy in
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
                    }
                    .padding(Spacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: localItems.last?.id) { _, newID in
                    guard let newID else { return }
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(newID, anchor: .bottom) }
                }
            }
            inputBar
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .tint(Theme.Colors.manentAccent)
        .navigationTitle("Vidur")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // One way out, one menu. iOS 26 draws the glass behind these itself.
            ToolbarItem(placement: .topBarLeading) {
                Button(action: closeSheet) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text("Vidur").font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if meeting != nil {
                        Picker("Search in", selection: scopeBinding) {
                            ForEach(VidurSearchScope.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    }
                    Button(role: .destructive) { clearConversation() } label: {
                        Label("Clear conversation", systemImage: "trash")
                    }
                    Button { showsSettings = true } label: {
                        Label("Vidur settings", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                VidurSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsSettings = false }
                        }
                    }
            }
        }
        .onAppear {
            scope = VidurPreferences.shared.searchScope
            loadPersistedHistory()
            refreshAssistant()
            startPrewarm()
        }
        .onChange(of: scope) { _, newScope in
            if persistScope { VidurPreferences.shared.searchScope = newScope }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            onDismiss()
        }
        .onChange(of: busy) { _, isBusyNow in UIApplication.shared.isIdleTimerDisabled = isBusyNow }
        .onDisappear {
            answerTask?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var scopeBinding: Binding<VidurSearchScope> {
        Binding(get: { scope }, set: { newValue in
            persistScope = true
            scope = newValue
        })
    }

    @MainActor
    private func closeSheet() {
        onDismiss()
    }

    @MainActor
    private func clearConversation() {
        answerTask?.cancel()
        localItems.removeAll()
        isLocalBusy = false
        if let meeting { try? VidurPreferences.shared.remove(meetingID: meeting.id) }
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

    @MainActor
    private func refreshAssistant() {
        assistant = VidurActions.assistantContext(
            modelContext: dataContext, userName: settings?.userProfile?.name, selfNames: selfNames,
            isRecording: isRecordingActive)
    }

    // MARK: Empty state

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

    private var greetingText: String {
        VidurSmallTalk.reply(to: "hi", context: assistant, seed: 0)?.text
            ?? "Ask about your meetings, or tell me what to do."
    }

    @MainActor
    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.Colors.manentAccent, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(greetingText)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(scopeExplanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
            VidurSuggestionList(
                suggestions: VidurProactive.suggestions(for: assistant, limit: 4), recent: recentQuestions) { question in
                submit(question)
            }
            .disabled(busy)
            Text("Vidur runs on this iPhone and uses a small on-device model. It relies on your saved minutes and transcripts, and tells you when it can\u{2019}t find something. Your meetings never leave your phone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scopeExplanation: String {
        guard meeting != nil else { return "Answers come from this meeting\u{2019}s minutes, transcript and notes." }
        switch scope {
        case .thisMeeting: return "Answering from \(meetingTitle). Use the menu to search a series or all meetings."
        case .thisMeetingAndSeries: return "Answering from the minutes, transcripts and notes of this meeting and its series."
        case .allMeetings: return "Answering from every meeting saved on this iPhone."
        }
    }

    // MARK: Conversation

    @MainActor @ViewBuilder
    private func conversationRow(_ item: VidurConversationItem) -> some View {
        if item.pending != nil {
            VStack(alignment: .leading, spacing: 16) {
                VidurPromptBubble(text: item.prompt)
                VidurActionCard(
                    intro: item.pendingIntro,
                    action: pendingBinding(item.id),
                    state: item.pendingState,
                    result: item.result,
                    onConfirm: { confirmPending(item.id) },
                    onCancel: { cancelPending(item.id) },
                    onOpenMeeting: { id in onOpenMeeting(id) })
            }
        } else {
            answerRow(item)
        }
    }

    @MainActor
    private func answerRow(_ item: VidurConversationItem) -> some View {
        let model = VidurAnswerCardModel(
            text: item.answerText,
            citations: item.citations,
            people: item.people,
            tasks: item.relatedTasks,
            suggestions: item.phase == .done ? item.suggestions : [],
            notice: item.notice,
            isQuick: item.tier == .structured || item.tier == .quote,
            isRefining: item.phase == .refining,
            currentMeetingID: meeting?.id,
            isWriting: item.phase == .refining && item.tier == .generated)
        return VidurConversationRow(
            prompt: item.prompt,
            model: model,
            showsSources: VidurPreferences.shared.showsSources,
            now: Date(),
            onOpenSource: { openSource($0) },
            onOpenTask: { openTask($0) },
            onAsk: { submit($0) })
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
        ((try? dataContext.fetch(FetchDescriptor<Meeting>())) ?? []).contains { $0.id == id }
    }

    // MARK: Input

    private var inputPlaceholder: String {
        if !items.isEmpty { return "Ask a follow-up, or tell me what to do" }
        switch scope {
        case .allMeetings where meeting != nil: return "Ask about your meetings"
        default: return "Ask or tell Vidur what to do"
        }
    }

    @MainActor
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
        submit(trimmed)
    }

    // MARK: Routing

    /// Everything the user says or taps goes through here: chat, commands, then questions.
    @MainActor
    private func submit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard meeting != nil else { send(trimmed); return }

        if let index = localItems.lastIndex(where: { $0.pending != nil && $0.pendingState == .awaiting }),
           index == localItems.count - 1, let decision = VidurConfirmation.answer(to: trimmed) {
            let id = localItems[index].id
            if decision { confirmPending(id) } else { cancelPending(id) }
            return
        }

        let seed = Int.random(in: 0..<10_000)
        switch VidurConversationRouter.route(trimmed, context: assistant, seed: seed) {
        case .smallTalk(let reply):
            appendNote(prompt: trimmed, text: reply.text, suggestions: reply.suggestions)
        case .reply(let reply):
            appendNote(prompt: trimmed, text: reply, suggestions: VidurProactive.suggestions(for: assistant, limit: 3))
        case .command(let command):
            run(command, prompt: trimmed)
        case .question(let question):
            send(question)
        }
    }

    @MainActor
    private func appendNote(prompt: String, text: String, suggestions: [String]) {
        var item = VidurConversationItem(prompt: prompt, answerText: text, citations: [], kind: nil, notice: nil)
        item.isNote = true
        item.tier = .structured
        item.suggestions = suggestions
        localItems.append(item)
    }

    // MARK: Commands

    @MainActor
    private func run(_ command: VidurCommand, prompt: String) {
        let prepared = VidurActions.prepare(command, current: meeting, modelContext: dataContext,
                                            isRecording: isRecordingActive)
        switch prepared {
        case .confirm(let action, let intro):
            var item = VidurConversationItem(prompt: prompt, answerText: "", citations: [], kind: nil, notice: nil)
            item.isNote = true
            item.pending = action
            item.pendingIntro = intro
            localItems.append(item)
        case .openMeeting(let id, let title):
            appendNote(prompt: prompt, text: "Opening \(title).", suggestions: [])
            onOpenMeeting(id)
        case .openScreen(let screen):
            appendNote(prompt: prompt, text: "Opening \(screen.title).", suggestions: [])
            open(screen)
        case .message(let text):
            appendNote(prompt: prompt, text: text, suggestions: VidurProactive.suggestions(for: assistant, limit: 3))
        }
    }

    private func pendingBinding(_ id: UUID) -> Binding<VidurPendingAction> {
        Binding(
            get: { localItems.first(where: { $0.id == id })?.pending ?? VidurPendingAction(kind: .startRecording) },
            set: { newValue in
                if let index = localItems.firstIndex(where: { $0.id == id }) { localItems[index].pending = newValue }
            })
    }

    @MainActor
    private func confirmPending(_ id: UUID) {
        guard let index = localItems.firstIndex(where: { $0.id == id }),
              let pending = localItems[index].pending, localItems[index].pendingState == .awaiting else { return }
        if case .startRecording = pending.kind, isRecordingActive {
            localItems[index].result = VidurActionResult(
                message: "A recording is already running, so I didn\u{2019}t start another one.", succeeded: false)
            localItems[index].pendingState = .done
            return
        }
        let result = VidurActions.perform(pending, modelContext: dataContext)
        localItems[index].result = result
        localItems[index].pendingState = .done
        refreshAssistant()
        if let recordingID = result.recordingMeetingID { openRecorder(recordingID) }
    }

    @MainActor
    private func cancelPending(_ id: UUID) {
        guard let index = localItems.firstIndex(where: { $0.id == id }),
              localItems[index].pendingState == .awaiting else { return }
        localItems[index].pendingState = .cancelled
    }

    @MainActor
    private func openRecorder(_ meetingID: UUID) {
        appState?.activeTab = .home
        onDismiss()
        router?.navigate(to: .liveRecording(id: meetingID), in: .home)
    }

    @MainActor
    private func open(_ screen: VidurScreen) {
        switch screen {
        case .home: appState?.activeTab = .home
        case .actions: appState?.activeTab = .actionItems
        case .search: appState?.activeTab = .search
        case .settings:
            appState?.activeTab = .home
            router?.navigate(to: .settings, in: .home)
        }
        onDismiss()
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
            selfNames: selfNames)
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
            if let answer = update.answer {
                if localItems[index].suggestions.isEmpty, answer.kind != .failed {
                    let intent: VidurQuickIntent? = answer.relatedTasks.isEmpty ? nil : .tasks
                    localItems[index].suggestions = VidurProactive.followUps(after: intent, asked: question, context: assistant)
                }
                if answer.isRecordable {
                    VidurPreferences.shared.record(VidurHistoryEntry(meetingID: meetingID, question: question, answer: answer.text))
                }
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

    /// The last four finished question and answer pairs, so "aur Neha ne?" follows the previous question.
    @MainActor
    private func conversationHistory() -> [VidurChatTurn] {
        let usable = localItems.filter { item in
            guard item.phase == .done, !item.isNote, item.pending == nil, !item.answerText.isEmpty else { return false }
            return item.kind != .failed && item.kind != .unavailable
        }
        return usable.suffix(4).map { VidurChatTurn(question: $0.prompt, answer: $0.answerText) }
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
