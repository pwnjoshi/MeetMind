import SwiftUI
import SwiftData

/// Transcript and audio page ("B6e · Transcript"). Works pushed in a NavigationStack or in a sheet.
public struct MeetingTranscriptScreen: View {
    private let meetingId: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState: AppState?
    @Query private var meetings: [Meeting]
    @AppStorage(HindiScriptPreference.key) private var hindiScript = HindiScriptStyle.devanagari.rawValue

    @State private var audio = TranscriptAudioController()
    @State private var cards: [TranscriptCard] = []
    @State private var activeCardID: UUID?
    @State private var audioAvailable = false
    @State private var isProcessing = false
    @State private var isSearchOpen = false
    @State private var query = ""
    @State private var revision = 0
    @State private var scrollHoldUntil = Date.distantPast
    @State private var editingCard: TranscriptCard?
    @State private var reassigningCard: TranscriptCard?
    @State private var errorMessage: String?
    @FocusState private var searchFocused: Bool

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(meetingId: UUID) {
        self.meetingId = meetingId
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
            return
        }
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

    private func saveEdits(_ edits: [UUID: String]) {
        guard let meeting, !isProcessing else { return }
        var changed = false
        for segment in meeting.transcriptSegments {
            guard let draft = edits[segment.id] else { continue }
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != segment.text {
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
