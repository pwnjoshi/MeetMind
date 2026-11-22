import SwiftUI
import SwiftData
import UIKit
import OfflineEngineKit

/// "Thinking..." placeholder with a light sweep. Static when Reduce Motion is on.
private struct VidurThinkingShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = -0.6

    var body: some View {
        Text("Thinking\u{2026}")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(colors: [Color.clear, Color.white.opacity(0.85), Color.clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.5)
                            .offset(x: sweep * proxy.size.width)
                    }
                    .mask { Text("Thinking\u{2026}").font(.subheadline) }
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { sweep = 1.1 }
            }
            .accessibilityLabel("Vidur is thinking")
    }
}

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
    @State private var expandedSources: Set<UUID> = []

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
                        conversationView(item)
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
            VStack(alignment: .leading, spacing: 8) {
                Text("SUGGESTED")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { offset, suggestion in
                        Button { send(suggestion.question) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkle")
                                    .foregroundStyle(Theme.Colors.manentAccent)
                                    .frame(width: 24)
                                    .accessibilityHidden(true)
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
                        if offset < suggestions.count - 1 { Divider().padding(.leading, 52) }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
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
    private func conversationView(_ item: VidurConversationItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.prompt)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(16)
                .background(Theme.Colors.manentAccent, in: RoundedRectangle(cornerRadius: 22))
                .frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Theme.Colors.manentAccent, in: Circle())
                        .accessibilityHidden(true)
                    Text("Vidur").font(.subheadline.weight(.semibold))
                    Spacer()
                    if let origin = sourceCountText(item.citations) {
                        Text(origin).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if item.answerText.isEmpty {
                    VidurThinkingShimmer()
                } else {
                    Text(item.answerText).textSelection(.enabled)
                }
                if item.phase == .done, item.tier == .structured || item.tier == .quote {
                    Label("Quick answer", systemImage: "bolt")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let notice = item.notice, item.phase == .done {
                    Label(notice, systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if item.phase == .refining, !item.answerText.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Checking the minutes and transcript\u{2026}")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .animation(.easeOut(duration: 0.2), value: item.phase)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 22))
            if VidurPreferences.shared.showsSources, !item.citations.isEmpty {
                sourceChips(item.citations)
                ForEach(item.citations.filter { expandedSources.contains($0.id) }) { citation in
                    citationRow(citation)
                }
            }
        }
    }

    private func sourceCountText(_ citations: [VidurCitation]) -> String? {
        let titles = Set(citations.map { $0.meetingTitle })
        guard !titles.isEmpty else { return nil }
        return titles.count == 1 ? "From 1 meeting" : "From \(titles.count) meetings"
    }

    private func chipTitle(_ citation: VidurCitation) -> String {
        var parts: [String] = []
        if !isCurrentMeeting(citation) { parts.append(String(citation.meetingTitle.prefix(18))) }
        if let label = citation.sourceLabel {
            parts.append(label)
        } else if let speaker = citation.speaker, !speaker.isEmpty {
            parts.append(speaker.split(separator: " ").first.map(String.init) ?? speaker)
        }
        if citation.hasTimestamp { parts.append(citation.timecode) }
        return parts.isEmpty ? "Source" : parts.joined(separator: " \u{00B7} ")
    }

    private func sourceChips(_ citations: [VidurCitation]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(citations) { citation in
                    let isExpanded = expandedSources.contains(citation.id)
                    Button {
                        if isExpanded { expandedSources.remove(citation.id) } else { expandedSources.insert(citation.id) }
                    } label: {
                        Label(chipTitle(citation), systemImage: citation.sourceLabel == nil ? "waveform" : "doc.text")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(isExpanded ? Theme.Colors.manentAccent.opacity(0.18) : Theme.Colors.manentAccent.opacity(0.08),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(isExpanded ? "Hide this source" : "Show this source")
                }
            }
        }
    }

    private func isCurrentMeeting(_ citation: VidurCitation) -> Bool {
        citation.meetingID == nil || citation.meetingID == meeting?.id
    }

    private func canPlay(_ citation: VidurCitation) -> Bool {
        citation.hasTimestamp && isCurrentMeeting(citation) && (meeting?.hasAudio ?? true)
    }

    @ViewBuilder
    private func citationRow(_ citation: VidurCitation) -> some View {
        let stamp = citation.hasTimestamp ? " \u{00B7} \(citation.timecode)" : ""
        let kind = citation.sourceLabel.map { "Minutes \u{00B7} \($0)" } ?? "Source"
        let heading = isCurrentMeeting(citation)
            ? "\(kind)\(stamp)"
            : "\(citation.meetingTitle) \u{00B7} \(citation.sourceLabel ?? "Source")\(stamp)"
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
            VStack(alignment: .leading, spacing: 8) {
                citationLabel(heading: heading, detail: detail, showsPlay: false)
                if let meetingID = citation.meetingID,
                   meetingID != meeting?.id,
                   meetingExists(meetingID) {
                    Button("Open \(citation.meetingTitle)") { onOpenMeeting(meetingID) }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .accessibilityHint("Opens the cited meeting")
                }
            }
        }
    }

    @MainActor
    private func meetingExists(_ id: UUID) -> Bool {
        let context = meeting?.modelContext ?? modelContext
        return ((try? context.fetch(FetchDescriptor<Meeting>())) ?? []).contains { $0.id == id }
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
            userDisabledRefinement: !VidurDeepAnswerSetting.isEnabled)
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
