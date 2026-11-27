import SwiftUI
import OfflineEngineKit

// Shared building blocks of the v5.1 meeting record: cards, avatars, chips, evidence quotes.

extension View {
    /// White v5 card (radius 26) on the grouped background.
    func recordCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// Coloured circle with initials.
struct RecordAvatar: View {
    let initials: String
    let colorHex: String
    var size: CGFloat = 28

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: colorHex), in: Circle())
            .accessibilityHidden(true)
    }

    static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        let letters = parts.prefix(2).compactMap { part in part.first.map { String($0) } }
        return letters.joined().uppercased()
    }
}

/// Small tinted capsule: decision status, due date.
struct RecordChip: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

enum RecordDecisionStatus {
    case agreed, deferred, open

    var title: String {
        switch self {
        case .agreed: return "Agreed"
        case .deferred: return "Deferred"
        case .open: return "Open"
        }
    }

    var tint: Color {
        switch self {
        case .agreed: return Color(red: 0.13, green: 0.55, blue: 0.24)
        case .deferred: return Color.orange
        case .open: return Color.secondary
        }
    }
}

/// One quote from the recording that supports a point in the minutes.
struct EvidenceMoment {
    let turnID: String
    let speaker: String
    let start: TimeInterval
    let quote: String
    let colorHex: String
    var timeText: String { MeetingEvidence.clock(start) }
}

/// Finds the quotes behind discussion points, decisions and open issues in the saved analysis.
/// Nothing is guessed: a point with no matching evidence simply has no quote.
enum MeetingEvidence {
    static func clock(_ time: TimeInterval) -> String {
        let seconds = max(0, Int(time))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
    }

    static func discussion(_ text: String, in result: MeetingAnalysisCheckpoint?) -> [SourceEvidence] {
        guard let result else { return [] }
        let key = normalized(text)
        let points = result.analysis.flatMap { $0.discussion }
        if let point = points.first(where: { normalized($0.text) == key }) { return point.evidence }
        for topic in result.minutes?.topics ?? [] {
            let lines = topic.discussion.map { normalized($0) }
            if lines.contains(key) { return topic.evidence }
        }
        return []
    }

    static func decision(_ text: String, in result: MeetingAnalysisCheckpoint?) -> [SourceEvidence] {
        guard let result else { return [] }
        let key = normalized(text)
        let points = result.analysis.flatMap { $0.decisions }
        if let point = points.first(where: { normalized($0.text) == key }) { return point.evidence }
        if let resolution = result.minutes?.resolutions.first(where: { normalized($0.text) == key }) {
            return resolution.evidence
        }
        return []
    }

    static func openIssue(_ text: String, in result: MeetingAnalysisCheckpoint?) -> [SourceEvidence] {
        guard let result else { return [] }
        let key = normalized(text)
        let points = result.analysis.flatMap { $0.openIssues }
        if let point = points.first(where: { normalized($0.text) == key }) { return point.evidence }
        let formal = result.minutes?.openIssues ?? []
        if let issue = formal.first(where: { normalized($0.text) == key || normalized($0.subject) == key }) {
            return issue.evidence
        }
        return discussion(text, in: result)
    }

    static func moments(from evidence: [SourceEvidence], result: MeetingAnalysisCheckpoint,
                        meeting: Meeting, names: MeetingSpeakerNames) -> [EvidenceMoment] {
        var moments: [EvidenceMoment] = []
        for source in evidence {
            guard let turn = result.turns.first(where: { $0.id == source.turnID }) else { continue }
            let name = names.name(forLabel: turn.speaker)
            let color = meeting.participants.first(where: { $0.name == name })?.avatarColorHex ?? "#4F46E5"
            moments.append(EvidenceMoment(turnID: turn.id, speaker: name, start: turn.start,
                                          quote: source.quote, colorHex: color))
        }
        return moments
    }

    static func firstTime(of evidence: [SourceEvidence], in result: MeetingAnalysisCheckpoint?) -> TimeInterval? {
        guard let result else { return nil }
        for source in evidence {
            if let turn = result.turns.first(where: { $0.id == source.turnID }) { return turn.start }
        }
        return nil
    }

    /// The reason recorded for a decision, when the formal minutes hold one for the same resolution.
    static func why(for evidence: [SourceEvidence], text: String, in result: MeetingAnalysisCheckpoint?) -> String? {
        guard let result, let resolutions = result.minutes?.resolutions else { return nil }
        let key = normalized(text)
        let ids = Set(evidence.map { $0.turnID })
        var match = resolutions.first(where: { normalized($0.text) == key })
        if match == nil, !ids.isEmpty {
            match = resolutions.first(where: { resolution in
                resolution.evidence.contains(where: { ids.contains($0.turnID) })
            })
        }
        let reason = match?.rationale?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return reason.isEmpty ? nil : reason
    }

    static func status(of text: String, in result: MeetingAnalysisCheckpoint?) -> RecordDecisionStatus {
        let key = normalized(text)
        for topic in result?.minutes?.topics ?? [] {
            guard let outcome = topic.outcome, normalized(outcome.text) == key else { continue }
            switch outcome.kind {
            case .deferred: return .deferred
            case .open: return .open
            case .resolved: return .agreed
            }
        }
        return .agreed
    }
}

/// Play / pause of the recording from the moment of a quote.
@MainActor
enum RecordPlayback {
    static func toggle(_ moment: EvidenceMoment, playing: inout String?, viewModel: MeetingDetailViewModel) {
        if playing == moment.turnID && viewModel.isPlaying {
            viewModel.stopPlayback()
            playing = nil
        } else {
            viewModel.seek(to: moment.start)
            if !viewModel.isPlaying { viewModel.togglePlayPause() }
            playing = moment.turnID
        }
    }
}

/// Speaker colour bar, name and time, the quote, and a play button when the recording is on this iPhone.
struct EvidenceQuoteRow: View {
    let moment: EvidenceMoment
    let canPlay: Bool
    let isPlaying: Bool
    let onTogglePlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: moment.colorHex)).frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(moment.speaker) \u{00B7} \(moment.timeText)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\u{201C}\(moment.quote)\u{201D}")
                    .font(.body)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            if canPlay {
                Button(action: onTogglePlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .foregroundStyle(Theme.Colors.manentAccent)
                        .frame(width: 36, height: 36)
                        .background(Theme.Colors.manentAccent.opacity(0.1), in: Circle())
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause audio" : "Play audio from \(moment.timeText)")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }
}
