import Foundation

// MARK: - Topics

enum MoMOutcomeKind: String, Codable, CaseIterable, Sendable {
    case resolved
    case deferred
    case open

    var label: String {
        switch self {
        case .resolved: return "RESOLVED THAT"
        case .deferred: return "DEFERRED"
        case .open: return "OPEN"
        }
    }
}

/// One agenda topic of the Minutes of Meeting.
struct MoMTopic: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var discussion: [String]
    var outcomeKind: MoMOutcomeKind
    var outcomeText: String
    var speaker: String?
    /// Seconds from the start of the recording; nil when the engine gave no evidence time.
    var timestamp: Double?

    init(id: String, title: String, discussion: [String] = [], outcomeKind: MoMOutcomeKind = .open,
         outcomeText: String = "", speaker: String? = nil, timestamp: Double? = nil) {
        self.id = id
        self.title = title
        self.discussion = discussion
        self.outcomeKind = outcomeKind
        self.outcomeText = outcomeText
        self.speaker = speaker
        self.timestamp = timestamp
    }

    /// "S1" or "Speaker 2": never shown to the reader as a name.
    static func isGenericSpeakerLabel(_ value: String) -> Bool {
        let lowered = value.lowercased().replacingOccurrences(of: " ", with: "")
        for prefix in ["speaker", "s"] where lowered.hasPrefix(prefix) {
            let rest = lowered.dropFirst(prefix.count)
            if !rest.isEmpty && rest.allSatisfy(\.isNumber) { return true }
        }
        return false
    }

    var hasOutcome: Bool { !outcomeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// "Maya · 12:10", or nil when there is no evidence time.
    var sourceChipText: String? {
        guard let timestamp else { return nil }
        let total = max(0, Int(timestamp))
        let clock = String(format: "%d:%02d", total / 60, total % 60)
        var name = speaker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if MoMTopic.isGenericSpeakerLabel(name) { name = "" }
        return name.isEmpty ? clock : "\(MeetingRecordFormatting.firstName(name)) \u{00B7} \(clock)"
    }
}

struct MoMSuggestedAttendee: Equatable, Identifiable, Sendable {
    var name: String
    var evidence: String?
    var id: String { name.lowercased() }
}

struct MoMNextMeetingHint: Equatable, Sendable {
    var date: Date?
    var note: String?
}

/// Optional fields the offline engine may add to `Meeting.offlineAnalysisData`.
/// Read with JSONSerialization so a missing or differently shaped field never fails decoding.
struct MoMEngineFields: Equatable, Sendable {
    var topics: [MoMTopic] = []
    var suggestedAttendees: [MoMSuggestedAttendee] = []
    var nextMeeting: MoMNextMeetingHint?

    static let empty = MoMEngineFields()

    static func parse(_ data: Data?) -> MoMEngineFields {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else { return .empty }
        var containers: [[String: Any]] = [root]
        // The engine stores the formal minutes under "minutes" in the checkpoint.
        if let minutes = root["minutes"] as? [String: Any] { containers.insert(minutes, at: 0) }
        if let chunks = root["analysis"] as? [Any] {
            for chunk in chunks { if let dictionary = chunk as? [String: Any] { containers.append(dictionary) } }
        }
        var result = MoMEngineFields()
        var seenTopics = Set<String>()
        var seenNames = Set<String>()
        for container in containers {
            if let raw = container["topics"] as? [Any] {
                for item in raw {
                    guard let entry = item as? [String: Any],
                          let topic = parseTopic(entry, index: result.topics.count) else { continue }
                        if seenTopics.insert(topic.title.lowercased()).inserted { result.topics.append(topic) }
                }
            }
            if let raw = container["suggestedAttendees"] as? [Any] {
                for item in raw {
                    var name: String?
                    var evidence: String?
                    if let text = item as? String { name = text }
                    else if let entry = item as? [String: Any] {
                        name = entry["name"] as? String
                        evidence = entry["evidence"] as? String
                        if evidence == nil, let quotes = entry["evidence"] as? [[String: Any]] {
                            evidence = quotes.first?["quote"] as? String
                        }
                    }
                    let cleaned = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleaned.isEmpty { continue }
                    if seenNames.insert(cleaned.lowercased()).inserted {
                        result.suggestedAttendees.append(MoMSuggestedAttendee(name: cleaned, evidence: evidence))
                    }
                }
            }
            if result.nextMeeting == nil, let value = container["nextMeeting"] {
                result.nextMeeting = parseNextMeeting(value)
            }
        }
        return result
    }

    private static func parseTopic(_ entry: [String: Any], index: Int) -> MoMTopic? {
        let title = (entry["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        var discussion: [String] = []
        if let list = entry["discussion"] as? [Any] {
            discussion = list.compactMap { $0 as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        } else if let single = entry["discussion"] as? String {
            let cleaned = single.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { discussion = [cleaned] }
        }
        var kind = MoMOutcomeKind.open
        var text = ""
        if let outcome = entry["outcome"] as? [String: Any] {
            if let raw = (outcome["kind"] as? String)?.lowercased(), let parsed = MoMOutcomeKind(rawValue: raw) { kind = parsed }
            text = (outcome["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let outcome = entry["outcome"] as? String {
            text = outcome.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return MoMTopic(
            id: "engine-\(index)",
            title: title,
            discussion: discussion,
            outcomeKind: kind,
            outcomeText: text,
            speaker: entry["speaker"] as? String,
            timestamp: seconds(from: entry["timestamp"])
        )
    }

    static func seconds(from value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        guard let text = value as? String else { return nil }
        let parts = text.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty, parts.count == text.split(separator: ":").count else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func parseNextMeeting(_ value: Any) -> MoMNextMeetingHint? {
        if let text = value as? String {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : MoMNextMeetingHint(date: nil, note: cleaned)
        }
        guard let entry = value as? [String: Any] else { return nil }
        var date: Date?
        for key in ["isoDate", "date", "start", "when"] {
            if let text = entry[key] as? String {
                date = ISO8601DateFormatter().date(from: text) ?? Self.dayFormatter.date(from: text)
            } else if let number = entry[key] as? NSNumber {
                date = Date(timeIntervalSince1970: number.doubleValue)
            }
            if date != nil { break }
        }
        var note: String?
        for key in ["text", "note", "title"] {
            if let text = entry[key] as? String, !text.isEmpty { note = text; break }
        }
        if date == nil && note == nil { return nil }
        return MoMNextMeetingHint(date: date, note: note)
    }
}

// MARK: - Style (B6a)

enum MoMStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case corporateIndia
    case boardMeeting
    case generalMeeting
    case projectReview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .corporateIndia: return "Corporate (India)"
        case .boardMeeting: return "Board meeting \u{00B7} SS-1"
        case .generalMeeting: return "General meeting \u{00B7} SS-2"
        case .projectReview: return "Project review"
        }
    }

    var shortTitle: String {
        switch self {
        case .corporateIndia: return "Corporate (India)"
        case .boardMeeting: return "Board meeting"
        case .generalMeeting: return "General meeting"
        case .projectReview: return "Project review"
        }
    }

    var subtitle: String {
        switch self {
        case .corporateIndia: return "Attendance, resolutions, ATR"
        case .boardMeeting: return "Quorum, interested directors"
        case .generalMeeting: return "Members, proxies, voting"
        case .projectReview: return "Status, risks, next steps"
        }
    }

    /// Minutes Studio meeting type this style maps to.
    var meetingType: MinutesMeetingType {
        switch self {
        case .corporateIndia: return .officeDepartment
        case .boardMeeting: return .boardOfDirectors
        case .generalMeeting: return .generalMeeting
        case .projectReview: return .teamProject
        }
    }

    var studioFormat: MinutesFormat {
        switch self {
        case .corporateIndia, .boardMeeting, .generalMeeting: return .corporateStandard
        case .projectReview: return .briefNote
        }
    }
}

// MARK: - Reference number

enum MoMReference {
    /// Up to two letters from the first words of the series or meeting title: "Design review" gives "DR".
    static func initials(from title: String) -> String {
        let words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        var letters = ""
        for word in words {
            guard let first = word.first, first.isLetter else { continue }
            letters.append(contentsOf: String(first).uppercased())
            if letters.count == 2 { break }
        }
        if letters.isEmpty { return "MM" }
        if letters.count == 1, let word = words.first, word.count > 1 {
            letters.append(contentsOf: String(word.dropFirst().prefix(1)).uppercased())
        }
        return letters
    }

    static func format(title: String, year: Int, sequence: Int) -> String {
        "MOM/\(initials(from: title))/\(year)/" + String(format: "%03d", sequence)
    }
}

// MARK: - Sidecar record

/// Per-meeting MoM data that has no field on the SwiftData models. Stored in `MoMSidecarStore`.
struct MoMSidecar: Codable, Equatable, Sendable {
    var version: Int = 1
    var referenceNumber: String?
    var venue: String?
    var chairpersonID: String?
    var minutesBy: String?
    var style: MoMStyle?
    /// Participant ids shown as "In attendance (invitee)".
    var inviteeIDs: [String] = []
    /// Participant ids shown under "Leave of absence" as leave granted.
    var leaveGrantedIDs: [String] = []
    /// User-edited topics. When set they replace the engine topics.
    var topics: [MoMTopic]?
    var dismissedMentions: [String] = []
    var anyOtherBusiness: String?
    var nextMeetingDate: Date?
    var nextMeetingNote: String?
    var closure: String?
    var signaturePNG: Data?
    var signedByName: String?
    var signedAt: Date?
    var signedPlace: String?

    init() {}

    var isSigned: Bool { signaturePNG != nil && signedAt != nil }

    private enum CodingKeys: String, CodingKey {
        case version, referenceNumber, venue, chairpersonID, minutesBy, style, inviteeIDs, leaveGrantedIDs
        case topics, dismissedMentions, anyOtherBusiness, nextMeetingDate, nextMeetingNote, closure
        case signaturePNG, signedByName, signedAt, signedPlace
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        referenceNumber = try c.decodeIfPresent(String.self, forKey: .referenceNumber)
        venue = try c.decodeIfPresent(String.self, forKey: .venue)
        chairpersonID = try c.decodeIfPresent(String.self, forKey: .chairpersonID)
        minutesBy = try c.decodeIfPresent(String.self, forKey: .minutesBy)
        style = try c.decodeIfPresent(MoMStyle.self, forKey: .style)
        inviteeIDs = try c.decodeIfPresent([String].self, forKey: .inviteeIDs) ?? []
        leaveGrantedIDs = try c.decodeIfPresent([String].self, forKey: .leaveGrantedIDs) ?? []
        topics = try c.decodeIfPresent([MoMTopic].self, forKey: .topics)
        dismissedMentions = try c.decodeIfPresent([String].self, forKey: .dismissedMentions) ?? []
        anyOtherBusiness = try c.decodeIfPresent(String.self, forKey: .anyOtherBusiness)
        nextMeetingDate = try c.decodeIfPresent(Date.self, forKey: .nextMeetingDate)
        nextMeetingNote = try c.decodeIfPresent(String.self, forKey: .nextMeetingNote)
        closure = try c.decodeIfPresent(String.self, forKey: .closure)
        signaturePNG = try c.decodeIfPresent(Data.self, forKey: .signaturePNG)
        signedByName = try c.decodeIfPresent(String.self, forKey: .signedByName)
        signedAt = try c.decodeIfPresent(Date.self, forKey: .signedAt)
        signedPlace = try c.decodeIfPresent(String.self, forKey: .signedPlace)
    }
}

// MARK: - Topic fallback

enum MoMTopicResolver {
    /// User edits win, then engine topics. Without either, the topics are built from the existing
    /// discussion, decisions and open issues so older minutes still render as a document.
    static func resolve(edited: [MoMTopic]?, engine: [MoMTopic], discussion: [String],
                        decisions: [String], openIssues: [String]) -> [MoMTopic] {
        if let edited { return edited }
        if !engine.isEmpty { return engine }
        var topics: [MoMTopic] = []
        if !discussion.isEmpty {
            topics.append(MoMTopic(id: "fallback-discussion", title: "Discussion", discussion: discussion))
        }
        for (index, text) in decisions.enumerated() {
            topics.append(MoMTopic(id: "fallback-decision-\(index)", title: "Decision \(index + 1)",
                                   outcomeKind: .resolved, outcomeText: text))
        }
        for (index, text) in openIssues.enumerated() {
            topics.append(MoMTopic(id: "fallback-open-\(index)", title: "Open issue \(index + 1)",
                                   outcomeKind: .open, outcomeText: text))
        }
        return topics
    }
}

// MARK: - Share outcome routing
