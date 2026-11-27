import Foundation
import SwiftData
import OfflineEngineKit

/// After processing, an empty agenda is filled with the topics heard in the meeting.
/// That derived agenda describes one meeting only. It must not be copied into the
/// next occurrence of a series, where it would show the previous meeting's topics
/// (for example a vendor decision) on a meeting that has not happened yet.
enum PlannedAgenda {
    /// The agenda a person planned for `meeting`, or nil when its agenda is empty or
    /// was filled in from that meeting's minutes.
    static func planned(_ meeting: Meeting) -> String? {
        let text = (meeting.agendaText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let derived = derivedAgenda(meeting), normalized(derived) == normalized(text) { return nil }
        return text
    }

    /// The topic titles the minutes wrote into the agenda of a processed meeting.
    static func derivedAgenda(_ meeting: Meeting) -> String? {
        guard let data = meeting.offlineAnalysisData,
              let checkpoint = try? JSONDecoder().decode(MeetingAnalysisCheckpoint.self, from: data),
              let minutes = checkpoint.minutes, !minutes.topics.isEmpty else { return nil }
        let agenda = minutes.agendaText.trimmingCharacters(in: .whitespacesAndNewlines)
        return agenda.isEmpty ? nil : agenda
    }

    /// True when `meeting`'s agenda is another series meeting's derived agenda, copied
    /// forward by an earlier version of the repeat scheduler.
    static func isCopiedFromSeries(_ meeting: Meeting, among all: [Meeting]) -> Bool {
        let text = normalized(meeting.agendaText ?? "")
        guard !text.isEmpty, let seriesID = meeting.seriesID else { return false }
        return all.contains { other in
            other.id != meeting.id && other.seriesID == seriesID
                && derivedAgenda(other).map { normalized($0) == text } == true
        }
    }

    private static let repairKey = "MeetMind.copiedAgendaRepair.v1"

    /// One-time clean-up of agendas that earlier versions copied from a processed
    /// meeting's minutes into later meetings of the same series. An unrecorded meeting
    /// gets an empty agenda; a processed one gets the topics of its own minutes.
    static func repairCopiedAgendas(context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: repairKey) else { return }
        // Marked done first: a failure here must never repeat on every launch.
        defaults.set(true, forKey: repairKey)
        guard let all = try? context.fetch(FetchDescriptor<Meeting>()) else { return }
        var changed = false
        for meeting in all where !meeting.isDeleted && isCopiedFromSeries(meeting, among: all) {
            let own = derivedAgenda(meeting)
            if own.map({ normalized($0) }) == normalized(meeting.agendaText ?? "") { continue }
            meeting.agendaText = own
            changed = true
        }
        if changed { try? context.save() }
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
