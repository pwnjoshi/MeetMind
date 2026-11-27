import Foundation
import OfflineEngineKit

/// One thing the user said and Vidur's reply: an answer, a short chat reply, or a confirmation card.
struct VidurConversationItem: Identifiable {
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
    /// Tasks in this answer the user marked done from the list, as `VidurTaskKey` values.
    var completedTaskKeys: Set<String> = []

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

enum VidurTaskKey {
    static func key(for task: VidurQuickTask) -> String {
        "\(task.meetingID.uuidString)|\(task.title.lowercased())"
    }
}

/// Keeps each conversation for the life of the app session, so closing and reopening Vidur does not lose it.
/// A conversation belongs to a scope: "this meeting" and "series" are per meeting, "all meetings" is shared.
/// Nothing is written to disk here. Saved answers still go to `VidurPreferences` history as before.
@MainActor
final class VidurSessionStore {
    static let shared = VidurSessionStore()
    static let maximumItems = 40

    private var sessions: [String: [VidurConversationItem]] = [:]

    static func key(meetingID: UUID?, scope: VidurSearchScope) -> String {
        switch scope {
        case .allMeetings: return "all"
        case .thisMeeting, .thisMeetingAndSeries: return "\(scope.rawValue)|\(meetingID?.uuidString ?? "none")"
        }
    }

    func items(for key: String) -> [VidurConversationItem] { sessions[key] ?? [] }

    /// Saves finished items only. An answer still being written is dropped, so reopening never shows a frozen spinner.
    func save(_ items: [VidurConversationItem], for key: String) {
        let finished = items.filter { $0.phase == .done }
        if finished.isEmpty {
            sessions[key] = nil
        } else {
            sessions[key] = Array(finished.suffix(Self.maximumItems))
        }
    }

    func clear(_ key: String) { sessions[key] = nil }
}
