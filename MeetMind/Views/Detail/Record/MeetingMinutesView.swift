import SwiftUI
import SwiftData
import OfflineEngineKit

extension View {
    /// Shows `message` in an alert and clears it when dismissed.
    func recordErrorAlert(_ title: String, message: Binding<String?>) -> some View {
        alert(title, isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK") { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

/// "Minutes" segment: one white card with Summary, Agenda, Present / Absent, Decisions,
/// Next meeting. Empty sections are left out. Every section is derived from `MeetingMinutesContent`,
/// so edits made in the other tabs, the People sheet or Edit Minutes appear here at once.
/// A dotted underline marks a point that has a quote in the recording; tapping it shows the quote and can play it.
@MainActor
struct MeetingMinutesView: View {
    let meeting: Meeting
    var viewModel: MeetingDetailViewModel? = nil
    var onOpenPeople: () -> Void = {}
    var onOpenTranscript: (Double?) -> Void = { _ in }
    @State private var store = MeetingRecordStore.shared
    @State private var expanded: Set<String> = []
    @State private var playingTurnID: String?


    private var canPlay: Bool { viewModel != nil && meeting.resolvedAudioFileURL != nil }

    var body: some View {
        let record = store.record(for: meeting.id)
        let content = MeetingMinutesContent.make(from: meeting, record: record)
        let analysis = meeting.offlineAnalysis
        let names = MeetingSpeakerNames(meeting: meeting, record: record)
        let isEmpty = content.summary.isEmpty && content.agenda.isEmpty && content.present.isEmpty
            && content.absent.isEmpty && content.decisions.isEmpty
        VStack(alignment: .leading, spacing: 22) {
            let needsMinutesReview = analysis?.minutesNeedSourceReview == true
            let disputed = (analysis?.transcriptCorrections ?? []).filter { correction in
                correction.replacement == nil && meeting.orderedTranscriptSegments.contains {
                    !$0.isEdited && abs($0.startTime - correction.start) < 0.01
                        && abs($0.endTime - correction.end) < 0.01 && $0.text == correction.original
                }
            }
            if needsMinutesReview || !disputed.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(needsMinutesReview ? "Review these minutes" : "Some wording needs review", systemImage: "text.bubble")
                        .font(.subheadline.weight(.semibold))
                    Text(needsMinutesReview
                         ? "MeetMind retried unclear actions. Check the transcript before sharing."
                         : "Disputed lines were left out of these minutes.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if disputed.isEmpty {
                        Button("Review transcript") { onOpenTranscript(nil) }
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                    ForEach(Array(disputed.enumerated()), id: \.offset) { _, correction in
                        let seconds = Int(correction.start)
                        let timestamp = String(format: "%02d:%02d", seconds / 60, seconds % 60)
                        Button("Review disputed wording at \(timestamp)") { onOpenTranscript(correction.start) }
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                }
            }
            if isEmpty {
                Text("No minutes were found in this recording.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Button("Add People", systemImage: "person.badge.plus", action: onOpenPeople)
                    .font(.subheadline)
                    .frame(minHeight: 44)
            } else {
                summarySection(content, languageNote: analysis?.minutes?.languageNote)
                agendaSection(content)
                peopleSection(content)
                decisionsSection(content, analysis: analysis, names: names)
                nextMeetingSection(analysis)
            }
        }
        .recordCard(padding: 20)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: Sections

    private func section<Inner: View>(_ title: String, @ViewBuilder content: () -> Inner) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func summarySection(_ content: MeetingMinutesContent, languageNote: String?) -> some View {
        if !content.summary.isEmpty {
            section("Summary") {
                Text(content.summary).font(.body).textSelection(.enabled)
                if let languageNote, !languageNote.isEmpty {
                    Text(languageNote).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func agendaSection(_ content: MeetingMinutesContent) -> some View {
        if !content.agenda.isEmpty {
            section("Agenda") {
                ForEach(Array(content.agenda.enumerated()), id: \.offset) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(entry.offset + 1)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .leading)
                        Text(entry.element).font(.body).textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private func peopleSection(_ content: MeetingMinutesContent) -> some View {
        if !content.present.isEmpty || !content.absent.isEmpty {
            section("Present") {
                if content.present.isEmpty {
                    Text("No one is marked present.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(content.present) { person in personRow(person) }
            }
            if !content.absent.isEmpty {
                section("Absent") {
                    ForEach(content.absent) { person in personRow(person) }
                }
            }
        }
    }

    private func personRow(_ person: MeetingMinutesContent.Person) -> some View {
        HStack(spacing: 12) {
            Circle().fill(Color(hex: person.colorHex)).frame(width: 12, height: 12)
            Text(person.label).font(.body)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func decisionsSection(_ content: MeetingMinutesContent, analysis: MeetingAnalysisCheckpoint?,
                                  names: MeetingSpeakerNames) -> some View {
        if !content.decisions.isEmpty {
            section("Decisions") {
                ForEach(content.decisions) { decision in
                    let evidence = MeetingEvidence.decision(decision.text, in: analysis)
                    pointRow(key: "x|\(decision.text)", text: decision.text,
                             moments: quotes(evidence, analysis, names))
                }
            }
        }
    }

    private func nextMeetingSection(_ analysis: MeetingAnalysisCheckpoint?) -> some View {
        section("Next meeting") {
            let text = nextMeetingText(analysis)
            Text(text)
                .font(.body)
                .foregroundStyle(text == "Not set" ? Color.secondary : Color.primary)
        }
    }

    private func nextMeetingText(_ analysis: MeetingAnalysisCheckpoint?) -> String {
        guard let next = analysis?.minutes?.nextMeeting else { return "Not set" }
        let when = [next.dateText, next.timeText]
            .compactMap { value in value?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !when.isEmpty { return when.joined(separator: ", ") }
        let text = next.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Not set" : text
    }

    // MARK: Points with evidence

    private func quotes(_ evidence: [SourceEvidence], _ analysis: MeetingAnalysisCheckpoint?,
                        _ names: MeetingSpeakerNames) -> [EvidenceMoment] {
        guard let analysis, !evidence.isEmpty else { return [] }
        return MeetingEvidence.moments(from: evidence, result: analysis, meeting: meeting, names: names)
    }

    private func pointRow(key: String, text: String, moments: [EvidenceMoment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.24))
                    .accessibilityHidden(true)
                if moments.isEmpty {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Button {
                        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
                    } label: {
                        Text(text)
                            .underline(true, pattern: .dot, color: Theme.Colors.manentAccent)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(expanded.contains(key) ? "Hides the quote" : "Shows the quote from the recording")
                }
            }
            if expanded.contains(key), !moments.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(moments.enumerated()), id: \.offset) { entry in
                        EvidenceQuoteRow(
                            moment: entry.element,
                            canPlay: canPlay,
                            isPlaying: playingTurnID == entry.element.turnID && (viewModel?.isPlaying ?? false),
                            onTogglePlay: { togglePlay(entry.element) }
                        )
                    }
                }
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func togglePlay(_ moment: EvidenceMoment) {
        guard let viewModel else { return }
        RecordPlayback.toggle(moment, playing: &playingTurnID, viewModel: viewModel)
    }
}

/// A suggested task with inline Accept, Edit and Discard.
/// Accepting turns it into an action item (and so into the minutes); discarding removes it for good.
@MainActor
struct SuggestedTaskRow: View {
    let meeting: Meeting
    let suggestion: MeetingMinutesContent.Suggestion
    @Environment(\.modelContext) private var context
    @State private var editing: MeetingTaskSuggestion?
    @State private var errorMessage: String?

    private var detail: String {
        var parts: [String] = []
        if let owner = suggestion.owner { parts.append("Owner: \(owner)") }
        if let deadline = suggestion.deadlineText, !deadline.isEmpty { parts.append("Due: \(deadline)") }
        parts.append(suggestion.category)
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(suggestion.title).font(.subheadline)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Accept") { accept() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Accept suggested task \(suggestion.title)")
                Button("Edit") { editing = pending() }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Edit suggested task \(suggestion.title)")
                Button("Discard", role: .destructive) { discard() }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Discard suggested task \(suggestion.title)")
            }
            .frame(minHeight: 44)
        }
        .padding(.vertical, 6)
        .sheet(item: $editing) { target in
            NavigationStack {
                SuggestedTaskEditor(meeting: meeting, suggestion: target)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel", systemImage: "xmark") { editing = nil }.labelStyle(.iconOnly)
                        }
                    }
            }
        }
        .recordErrorAlert("Could Not Update Task", message: $errorMessage)
    }

    private func pending() -> MeetingTaskSuggestion? {
        meeting.pendingTaskSuggestions.first(where: { $0.id == suggestion.id })
    }

    private func accept() {
        guard let target = pending() else { return }
        do { try MeetingRecordEditor.acceptSuggestion(target, meeting: meeting, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func discard() {
        guard let target = pending() else { return }
        do { try MeetingRecordEditor.discardSuggestion(target, meeting: meeting, context: context) }
        catch { errorMessage = error.localizedDescription }
    }
}
