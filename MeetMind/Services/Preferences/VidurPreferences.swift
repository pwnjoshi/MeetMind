import Foundation
import Observation

/// How much text Vidur should produce for an answer.
public enum VidurAnswerLength: String, CaseIterable, Codable, Sendable, Identifiable {
    case brief, standard, detailed
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .brief: return "Brief"
        case .standard: return "Standard"
        case .detailed: return "Detailed"
        }
    }
    /// Upper bound for generated answer tokens passed to the local model.
    public var maxTokens: Int {
        switch self {
        case .brief: return 160
        case .standard: return 320
        case .detailed: return 640
        }
    }
}

/// Which saved meetings Vidur may read when answering.
public enum VidurSearchScope: String, CaseIterable, Codable, Sendable, Identifiable {
    case thisMeeting, thisMeetingAndSeries, allMeetings
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .thisMeeting: return "This Meeting"
        case .thisMeetingAndSeries: return "This Meeting and Series"
        case .allMeetings: return "All Meetings"
        }
    }
}

/// One saved Vidur question and its answer. Stored only on this iPhone.
public struct VidurHistoryEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var meetingID: UUID?
    public var question: String
    public var answer: String
    public var askedAt: Date

    public init(id: UUID = UUID(), meetingID: UUID?, question: String, answer: String, askedAt: Date = Date()) {
        self.id = id
        self.meetingID = meetingID
        self.question = question
        self.answer = answer
        self.askedAt = askedAt
    }
}

/// Vidur preferences shared by Settings and every Vidur surface.
/// The selected local model stays owned by the existing offline model settings.
@MainActor
@Observable
public final class VidurPreferences {
    public static let shared = VidurPreferences()

    private enum Key {
        static let answerLength = "Manent_Vidur_AnswerLength"
        static let searchScope = "Manent_Vidur_SearchScope"
        static let showSources = "Manent_Vidur_ShowSources"
        static let history = "Manent_Vidur_History"
    }

    private let defaults: UserDefaults
    private var loadFailure: String?
    public var answerLength: VidurAnswerLength {
        didSet { defaults.set(answerLength.rawValue, forKey: Key.answerLength) }
    }
    public var searchScope: VidurSearchScope {
        didSet { defaults.set(searchScope.rawValue, forKey: Key.searchScope) }
    }
    public var showsSources: Bool {
        didSet { defaults.set(showsSources, forKey: Key.showSources) }
    }
    public private(set) var history: [VidurHistoryEntry]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Voice mode was removed. Drop its two old switches so no stale setting stays behind.
        for legacyKey in ["Manent_Vidur_VoiceReplies", "Manent_Vidur_HeyVidur"] {
            defaults.removeObject(forKey: legacyKey)
        }
        answerLength = defaults.string(forKey: Key.answerLength).flatMap(VidurAnswerLength.init) ?? .standard
        searchScope = defaults.string(forKey: Key.searchScope).flatMap(VidurSearchScope.init) ?? .thisMeeting
        showsSources = defaults.object(forKey: Key.showSources) as? Bool ?? true
        if let data = defaults.data(forKey: Key.history) {
            do { history = try JSONDecoder().decode([VidurHistoryEntry].self, from: data) }
            catch {
                history = []
                loadFailure = error.localizedDescription
            }
        } else {
            history = []
        }
    }

    public func record(_ entry: VidurHistoryEntry) {
        history.insert(entry, at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
        persistHistory()
    }

    public func history(for meetingID: UUID) -> [VidurHistoryEntry] {
        history.filter { $0.meetingID == meetingID }
    }

    public func clearHistory() {
        history = []
        defaults.removeObject(forKey: Key.history)
    }

    public func remove(meetingID: UUID) throws {
        if loadFailure != nil { throw SidecarStoreError.corrupt("Vidur history") }
        history.removeAll { $0.meetingID == meetingID }
        persistHistory()
    }

    /// Removes private Vidur history and user choices. The selected downloaded
    /// model is owned by OfflineEngineKit and is deliberately preserved.
    public func eraseAll() {
        history = []
        loadFailure = nil
        answerLength = .standard
        searchScope = .thisMeeting
        showsSources = true
        defaults.removeObject(forKey: Key.history)
        defaults.removeObject(forKey: Key.answerLength)
        defaults.removeObject(forKey: Key.searchScope)
        defaults.removeObject(forKey: Key.showSources)
    }

    public var isEmpty: Bool { history.isEmpty }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Key.history)
        }
    }
}
