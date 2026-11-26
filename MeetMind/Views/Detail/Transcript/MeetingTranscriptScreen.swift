import SwiftUI
import SwiftData
import OfflineEngineKit

/// Transcript and audio page ("B6e · Transcript"). Works pushed in a NavigationStack or in a sheet.
public struct MeetingTranscriptScreen: View {
    private let meetingId: UUID
    private let focusTime: Double?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState: AppState?
    @Query private var meetings: [Meeting]
    @AppStorage(HindiScriptPreference.key) private var hindiScript = HindiScriptStyle.devanagari.rawValue

    @State private var audio = TranscriptAudioController()
    @State private var corrections: [TranscriptCorrection] = []
    @State private var cards: [TranscriptCard] = []
    @State private var activeCardID: UUID?
    @State private var didFocus = false
    @State private var actionSource: TranscriptCard?
    @State private var actionTitle = ""
    @State private var addsDecision = false
    @State private var audioAvailable = false
    @State private var isProcessing = false
    @State private var isSearchOpen = false
    @State private var query = ""
    @State private var revision = 0
    @State private var scrollHoldUntil = Date.distantPast
    @State private var reviewingCorrection: TranscriptCorrection?
    @State private var editingCard: TranscriptCard?
    @State private var reassigningCard: TranscriptCard?
    @State private var errorMessage: String?
    @FocusState private var searchFocused: Bool

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(meetingId: UUID, focusTime: Double? = nil) {
        self.meetingId = meetingId
        self.focusTime = focusTime
        _meetings = Query(filter: #Predicate<Meeting> { $0.id == meetingId })
    }

    private var meeting: Meeting? { meetings.first }

    private var visibleCards: [TranscriptCard] {
        guard TranscriptSearch.isActive(query) else { return cards }
        return cards.filter {
            TranscriptSearch.matches($0.text, query: query) || TranscriptSearch.matches($0.speakerName, query: query)
                || TranscriptSearch.matches(HindiScriptPreference.display($0.text, raw: hindiScript), query: query)
        }
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            header
            if isSearchOpen { searchField }
            content
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { playerArea }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            configureAudio()
            refreshProcessing()
            rebuildCards()
        }
        .onDisappear {
            audio.unload()
            audio.onTimeChange = nil
            audioAvailable = false
        }
        .onReceive(ticker) { _ in refreshProcessing() }
        .onChange(of: meeting?.orderedTranscriptSegments.map {
            TranscriptRevision(id: $0.id, text: $0.text, start: $0.startTime,
                               end: $0.endTime, speaker: $0.speaker?.name)
        }) { _, _ in rebuildCards() }
        .onChange(of: meeting?.offlineAnalysisData) { _, _ in rebuildCards() }
        .onChange(of: revision) { _, _ in rebuildCards() }
        .onChange(of: isProcessing) { _, _ in rebuildCards() }
        .onChange(of: meeting?.audioFileURL) { _, _ in loadAudio() }
        .onChange(of: activeCardID) { _, newValue in autoScrollTarget = newValue }
        .sheet(item: $actionSource) { card in
            NavigationStack {
                Form {
                    TextField(addsDecision ? "Decision" : "Action", text: $actionTitle, axis: .vertical)
                    Section("Transcript evidence") {
                        Text(card.text)
                    }
                }
                .navigationTitle(addsDecision ? "Add Decision" : "Add Action")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { actionSource = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveRecordItem(from: card) }
                            .disabled(actionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .sheet(item: $editingCard) { card in
            TranscriptCardEditSheet(card: card) { edits in saveEdits(edits) }
        }
        .sheet(item: $reassigningCard) { card in
            SpeakerReassignSheet(
                availableSpeakers: availableSpeakers(),
                currentSpeaker: speaker(for: card),
                onSelect: { speaker in
                    reassign(card, to: speaker)
                    reassigningCard = nil
                },
                onDismiss: { reassigningCard = nil }
            )
        }
        .alert("Transcript comparison", isPresented: Binding(
            get: { reviewingCorrection != nil },
            set: { if !$0 { reviewingCorrection = nil } }
        )) {
            Button("OK", role: .cancel) { reviewingCorrection = nil }
        } message: {
            if let correction = reviewingCorrection {
                if let replacement = correction.replacement {
                    Text("Original: \(correction.original)\nAudio retry: \(replacement)")
                } else {
                    let note = correction.contextFavorsAlternative == true
                        ? "The surrounding conversation favors the live caption. Listen back to confirm."
                        : "The audio retry did not confirm the alternate wording."
                    Text("\(note)\nLive caption: \(correction.alternative)")
                }
            }
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // Scroll requests travel through this state so the ScrollViewReader below can react.
    @State private var autoScrollTarget: UUID?

    // MARK: Header

    private var header: some View {
        ZStack {
            Text("Transcript")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack {
                circleButton(systemName: "chevron.left", label: "Back") { dismiss() }
                Spacer()
                circleButton(systemName: isSearchOpen ? "xmark" : "magnifyingglass",
                             label: isSearchOpen ? "Close search" : "Search transcript") {
                    toggleSearch()
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }

    private func circleButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField("Search words or speakers", text: $query)
                .focused($searchFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm + 2)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Colors.cardBackground))
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }

    private func toggleSearch() {
        isSearchOpen.toggle()
        if isSearchOpen {
            searchFocused = true
        } else {
            query = ""
            searchFocused = false
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if meeting == nil {
            emptyState(icon: "questionmark.folder", title: "This meeting is no longer available", detail: nil)
        } else if cards.isEmpty {
            emptyContent
        } else {
            let shown = visibleCards
            if shown.isEmpty {
                emptyState(icon: "magnifyingglass", title: "No matches", detail: "Nothing in this transcript matches \u{201C}\(query)\u{201D}.")
            } else {
                transcriptList(shown)
            }
        }
    }

    private func transcriptList(_ shown: [TranscriptCard]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.md) {
                    if isProcessing {
                        Label("Editing is unavailable while the transcript is being processed.", systemImage: "hourglass")
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Spacing.xs)
                    }
                    ForEach(shown) { card in
                        cardRow(card)
                            .id(card.id)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8).onChanged { _ in
                    scrollHoldUntil = Date().addingTimeInterval(4)
                }
            )
            .task(id: cards.count) {
                guard !didFocus, let focusTime,
                      let id = TranscriptCardBuilder.activeCardID(at: focusTime, in: cards) else { return }
                didFocus = true
                if audioAvailable { audio.seek(to: focusTime) }
                proxy.scrollTo(id, anchor: .center)
            }
            .onChange(of: autoScrollTarget) { _, target in
                guard let target, Date() >= scrollHoldUntil, !isSearchOpen || !TranscriptSearch.isActive(query) else { return }
                if reduceMotion {
                    proxy.scrollTo(target, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .center) }
                }
            }
        }
    }

    private func cardRow(_ card: TranscriptCard) -> some View {
        Button {
            guard audioAvailable else { return }
            audio.play(from: card.start)
        } label: {
            TranscriptCardView(card: card, isActive: card.id == activeCardID, query: query)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityText)
        .accessibilityHint(audioAvailable ? "Plays the recording from here" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(card.id == activeCardID ? .isSelected : [])
        .accessibilityAction(named: "Edit text") { if !isProcessing { editingCard = card } }
        .accessibilityAction(named: "Change speaker") { if !isProcessing { reassigningCard = card } }
        .contextMenu {
            Button("Add action from passage", systemImage: "plus.circle") {
                addsDecision = false
                actionTitle = ""
                actionSource = card
            }
            .disabled(isProcessing || meeting?.status != .completed)
            Button("Add decision from passage", systemImage: "checkmark.circle") {
                addsDecision = true
                actionTitle = ""
                actionSource = card
            }
            .disabled(isProcessing || meeting?.status != .completed || meeting?.summary == nil)
            if let (line, correction) = correction(for: card) {
                if correction.replacement != nil {
                    Button("Restore original text", systemImage: "arrow.uturn.backward") {
                        saveEdits([line.id: correction.original])
                    }
                    .disabled(isProcessing)
                } else {
                    Button("Confirm displayed wording", systemImage: "checkmark") {
                        saveEdits([line.id: line.text], confirmUnchanged: true)
                    }
                    .disabled(isProcessing)
                }
                Button("Review transcript comparison", systemImage: "text.bubble") {
                    reviewingCorrection = correction
                }
            }
            Button { editingCard = card } label: { Label("Edit text", systemImage: "pencil") }
                .disabled(isProcessing)
            Button { reassigningCard = card } label: { Label("Change speaker", systemImage: "person.2") }
                .disabled(isProcessing || availableSpeakers().isEmpty)
        }
    }

    // MARK: Empty states

    @ViewBuilder
    private var emptyContent: some View {
        let state = meeting?.analysisState
        if isProcessing || (meeting?.status == .processing && state != "failed" && state != "paused" && state != "speakerReview") {
            emptyState(icon: "waveform", title: "Transcribing\u{2026}",
                       detail: "The transcript appears when processing finishes.")
        } else if state == "failed" {
            emptyState(icon: "exclamationmark.triangle", title: "The transcript could not be created",
                       detail: "Processing needs attention. Open the meeting to try again.")
        } else if state == "paused" {
            emptyState(icon: "pause.circle", title: "Processing is paused",
                       detail: "The transcript appears when processing finishes.")
        } else if meeting?.resolvedAudioFileURL != nil || audioAvailable {
            emptyState(icon: "waveform.slash", title: "No speech was recognized in this recording",
                       detail: "You can still play the audio below.")
        } else {
            emptyState(icon: "text.bubble", title: "No transcript yet",
                       detail: "There is no recording for this meeting.")
        }
    }

    private func emptyState(icon: String, title: String, detail: String?) -> some View {
        VStack(spacing: Spacing.md) {
            Spacer(minLength: Spacing.xl)
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Colors.textPrimary)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Spacing.xl)
        }
        .padding(.horizontal, Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Player

    @ViewBuilder
    private var playerArea: some View {
        if meeting != nil {
            Group {
                if audioAvailable {
                    TranscriptPlayerBar(audio: audio)
                } else {
                    TranscriptAudioUnavailableBar()
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.sm)
            .padding(.top, Spacing.xs)
        }
    }

    // MARK: Data

    private struct TranscriptRevision: Equatable {
        let id: UUID
        let text: String
        let start: TimeInterval
        let end: TimeInterval
        let speaker: String?
    }

    private func rebuildCards() {
        guard let meeting else {
            cards = []
            corrections = []
            return
        }
        corrections = meeting.offlineAnalysisData.flatMap {
            try? JSONDecoder().decode(MeetingAnalysisCheckpoint.self, from: $0)
        }?.transcriptCorrections ?? []
        let ordered = meeting.orderedTranscriptSegments
        let refs = ordered.map {
            TranscriptSegmentRef(id: $0.id, sequenceIndex: $0.sequenceIndex, start: $0.startTime)
        }
        let used = TranscriptUsage.usedSegmentIDs(checkpointData: meeting.offlineAnalysisData, segments: refs)
        cards = TranscriptCardBuilder.build(segments: ordered, used: used)
        activeCardID = TranscriptCardBuilder.activeCardID(at: audio.currentTime, in: cards)
    }

    private func refreshProcessing() {
        let running = OfflineAnalysisBackgroundScheduler.isRunning(meetingID: meetingId)
        if running != isProcessing { isProcessing = running }
    }

    // MARK: Audio

    private func configureAudio() {
        audio.isRecordingActive = { [appState] in appState?.isRecordingActive ?? false }
        audio.onTimeChange = { time in
            let id = TranscriptCardBuilder.activeCardID(at: time, in: cards)
            if id != activeCardID { activeCardID = id }
        }
        loadAudio()
    }

    private func loadAudio() {
        audio.load(url: meeting?.resolvedAudioFileURL)
        audioAvailable = audio.isLoaded
    }

    // MARK: Editing

    private func speaker(for card: TranscriptCard) -> Speaker? {
        guard let id = card.speakerID else { return nil }
        return meeting?.transcriptSegments.first { $0.speaker?.id == id }?.speaker
    }

    private func availableSpeakers() -> [Speaker] {
        guard let meeting else { return [] }
        var seen = Set<UUID>()
        var result: [Speaker] = []
        for speaker in meeting.participants + meeting.transcriptSegments.compactMap(\.speaker)
        where seen.insert(speaker.id).inserted {
            result.append(speaker)
        }
        return result
    }

    private func correction(for card: TranscriptCard) -> (TranscriptCardLine, TranscriptCorrection)? {
        for line in card.lines where !line.isEdited {
            if let match = corrections.first(where: {
                abs($0.start - line.start) < 0.01 && abs($0.end - line.end) < 0.01
                    && ($0.replacement ?? $0.original) == line.text
            }) {
                return (line, match)
            }
        }
        return nil
    }

    private func saveEdits(_ edits: [UUID: String], confirmUnchanged: Bool = false) {
        guard let meeting, !isProcessing else { return }
        var changed = false
        for segment in meeting.transcriptSegments {
            guard let draft = edits[segment.id] else { continue }
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != segment.text || (confirmUnchanged && !segment.isEdited) {
                segment.updateText(trimmed)
                changed = true
            }
        }
        guard changed else { return }
        persist()
    }

    private func reassign(_ card: TranscriptCard, to speaker: Speaker) {
        guard let meeting, !isProcessing else { return }
        let ids = Set(card.lines.map(\.id))
        for segment in meeting.transcriptSegments where ids.contains(segment.id) {
            segment.speaker = speaker
        }
        persist()
    }

    private func saveRecordItem(from card: TranscriptCard) {
        let title = actionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let meeting, meeting.status == .completed, !isProcessing, !title.isEmpty else { return }
        if addsDecision {
            do {
                try MeetingRecordEditor.addTranscriptDecision(title, segmentIDs: card.lines.map(\.id),
                    meeting: meeting, context: modelContext, store: .shared)
            } catch {
                errorMessage = error.localizedDescription
            }
            actionSource = nil
            return
        }
        let source = card.lines.map { line in
            let seconds = Int(line.start)
            return String(format: "[%02d:%02d] ", seconds / 60, seconds % 60) + line.text
        }.joined(separator: "\n")
        let item = ActionItem(title: title, meeting: meeting)
        item.priorityRaw = ""
        item.sourceEvidence = source
        modelContext.insert(item)
        meeting.addActionItem(item)
        do {
            try modelContext.save()
            actionSource = nil
        } catch {
            modelContext.rollback()
            actionSource = nil
            errorMessage = error.localizedDescription
        }
    }

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Your change could not be saved. Please try again."
        }
        revision += 1
    }
}

// MARK: - Card

private struct TranscriptCardView: View {
    let card: TranscriptCard
    let isActive: Bool
    let query: String
    @AppStorage(HindiScriptPreference.key) private var hindiScript = HindiScriptStyle.devanagari.rawValue

    private var background: Color {
        card.isUsedInMinutes ? Theme.Colors.manentAccent.opacity(0.12) : Theme.Colors.cardBackground
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(Color(hex: card.colorHex))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(card.initials)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.6)
                    )
                Text(card.speakerName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.sm)
                Text(card.timeText)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Text(TranscriptSearch.highlighted(HindiScriptPreference.display(card.text, raw: hindiScript), query: query))
                .font(.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if card.isUsedInMinutes {
                Text("Used in minutes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.manentAccent)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(Capsule().fill(Theme.Colors.manentAccent.opacity(0.16)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(background))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.Colors.manentAccent, lineWidth: isActive ? 2 : 0)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
