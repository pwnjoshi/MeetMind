import Foundation
import SwiftData

// MARK: - Meeting Status
public enum MeetingStatus: String, Codable, CaseIterable, Sendable {
    case scheduled = "scheduled"
    case recording = "recording"
    case processing = "processing"
    case completed = "completed"
    case archived = "archived"
    
    public var displayName: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .recording: return "Recording"
        case .processing: return "Processing"
        case .completed: return "Completed"
        case .archived: return "Archived"
        }
    }
    
    public var badgeColorHex: String {
        switch self {
        case .scheduled: return "#3B82F6"  // Live Blue
        case .recording: return "#EF4444"  // Coral Red
        case .processing: return "#F59E0B" // Warm Amber
        case .completed: return "#10B981"  // Mint Green
        case .archived: return "#6B7280"   // Neutral Slate
        }
    }
    
    public var iconName: String {
        switch self {
        case .scheduled: return "calendar"
        case .recording: return "record.circle.fill"
        case .processing: return "gearshape.arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .archived: return "archivebox.fill"
        }
    }
    
    /// State machine transition invariants (validates scenario S24)
    public func canTransition(to next: MeetingStatus) -> Bool {
        switch (self, next) {
        case (.scheduled, .recording), (.scheduled, .processing), (.scheduled, .archived):
            return true
        case (.recording, .processing), (.recording, .scheduled):
            return true
        case (.processing, .completed), (.processing, .recording):
            return true
        case (.completed, .archived):
            return true
        case (.archived, .completed):
            return true
        default:
            return self == next
        }
    }
}

// MARK: - Meeting Error
public enum MeetingError: LocalizedError, Sendable, Equatable {
    case invalidStateTransition(from: MeetingStatus, to: MeetingStatus)
    case meetingNotFound
    case emptyTitle
    case invalidDuration
    
    public var errorDescription: String? {
        switch self {
        case .invalidStateTransition(let from, let to):
            return "Cannot transition meeting status from \(from.displayName) to \(to.displayName)."
        case .meetingNotFound:
            return "Meeting not found."
        case .emptyTitle:
            return "Meeting title cannot be empty."
        case .invalidDuration:
            return "Meeting duration must be positive."
        }
    }
}

// MARK: - Audio Quality
public enum AudioQuality: String, Codable, CaseIterable, Sendable {
    case standard = "standard" // 64 kbps AAC mono, 44.1 kHz
    case high = "high"         // 128 kbps AAC stereo/mono, 44.1 kHz
    
    public static let standard64k: AudioQuality = .standard
    public static let high128k: AudioQuality = .high
    
    public var displayName: String {
        switch self {
        case .standard: return "Standard (64 kbps)"
        case .high: return "High Fidelity (128 kbps)"
        }
    }
    
    public var bitRate: Int {
        switch self {
        case .standard: return 64_000
        case .high: return 128_000
        }
    }
    
    public var sampleRate: Double {
        switch self {
        case .standard: return 44_100.0
        case .high: return 44_100.0
        }
    }
    
    public var fileExtension: String { "m4a" }
    
    public var storageEstimatePerHour: String {
        switch self {
        case .standard: return "~28 MB / hour"
        case .high: return "~57 MB / hour"
        }
    }
}

// MARK: - Meeting SwiftData Entity
@Model
public final class Meeting: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var createdAt: Date
    public var scheduledStartTime: Date?
    public var duration: TimeInterval
    public var statusRaw: String
    public var audioFileURL: URL?
    public var audioQualityRaw: String
    public var isFavorite: Bool
    public var templateName: String?
    
    // Relationships
    @Relationship(deleteRule: .nullify, inverse: \Folder.meetings)
    public var folder: Folder?
    
    @Relationship(deleteRule: .nullify, inverse: \Tag.meetings)
    public var tags: [Tag]
    
    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.meeting)
    public var transcriptSegments: [TranscriptSegment]
    
    @Relationship(deleteRule: .cascade, inverse: \Summary.meeting)
    public var summary: Summary?
    
    @Relationship(deleteRule: .cascade, inverse: \ActionItem.meeting)
    public var actionItems: [ActionItem]
    
    @Relationship(deleteRule: .cascade, inverse: \Note.meeting)
    public var notes: [Note]
    
    @Relationship(deleteRule: .nullify, inverse: \Speaker.meetings)
    public var participants: [Speaker]
    
    // Enum accessors
    public var status: MeetingStatus {
        get { MeetingStatus(rawValue: statusRaw) ?? .scheduled }
        set { statusRaw = newValue.rawValue }
    }
    
    public var audioQuality: AudioQuality {
        get { AudioQuality(rawValue: audioQualityRaw) ?? .standard }
        set { audioQualityRaw = newValue.rawValue }
    }
    
    public var isStarred: Bool {
        get { isFavorite }
        set { isFavorite = newValue }
    }
    
    public var speakers: [Speaker] {
        get { participants }
        set { participants = newValue }
    }
    
    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        scheduledStartTime: Date? = nil,
        duration: TimeInterval = 0,
        status: MeetingStatus = .scheduled,
        audioFileURL: URL? = nil,
        audioQuality: AudioQuality = .standard,
        isFavorite: Bool = false,
        templateName: String? = nil,
        folder: Folder? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.scheduledStartTime = scheduledStartTime
        self.duration = duration
        self.statusRaw = status.rawValue
        self.audioFileURL = audioFileURL
        self.audioQualityRaw = audioQuality.rawValue
        self.isFavorite = isFavorite
        self.templateName = templateName
        self.folder = folder
        self.tags = []
        self.transcriptSegments = []
        self.summary = nil
        self.actionItems = []
        self.notes = []
        self.participants = []
    }
    
    // Helper Methods & Computed Properties
    public var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private static let cachedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    public var formattedDate: String {
        let date = scheduledStartTime ?? createdAt
        return Self.cachedDateFormatter.string(from: date)
    }
    
    private static let figmaDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM · h:mm a"
        return formatter
    }()
    
    public var figmaFormattedSubtitle: String {
        let date = scheduledStartTime ?? createdAt
        let dateStr = Self.figmaDateFormatter.string(from: date)
        if status == .scheduled && templateName?.contains("Series") == true {
            return "Next: \(dateStr)"
        }
        return dateStr
    }
    
    public var figmaBadgeText: String {
        if let templateName = templateName, !templateName.isEmpty {
            return templateName
        }
        if status == .completed {
            return "Finalized"
        } else if status == .scheduled {
            return "Scheduled"
        } else {
            return status.displayName
        }
    }
    
    public var figmaBadgeColorHex: String {
        if status == .completed {
            return "#0068D9"
        } else {
            return "#5F636B"
        }
    }
    
    public var fullTranscriptText: String {
        transcriptSegments
            .sorted { $0.startTime < $1.startTime }
            .map { segment in
                let speakerName = segment.speaker?.name ?? "Unknown"
                return "[\(segment.formattedStartTime)] \(speakerName): \(segment.text)"
            }
            .joined(separator: "\n")
    }
    
    public var pendingActionItemsCount: Int {
        actionItems.filter { !$0.isCompleted }.count
    }
    
    public var completedActionItemsCount: Int {
        actionItems.filter { $0.isCompleted }.count
    }
    
    public var hasAudio: Bool {
        audioFileURL != nil
    }
    
    public func addParticipant(_ speaker: Speaker) {
        if !participants.contains(where: { $0.id == speaker.id }) {
            participants.append(speaker)
        }
    }
    
    public func removeParticipant(_ speaker: Speaker) {
        participants.removeAll { $0.id == speaker.id }
    }
    
    public func toggleFavorite() {
        isFavorite.toggle()
    }
    
    public func canTransition(to next: MeetingStatus) -> Bool {
        status.canTransition(to: next)
    }
    
    public func transition(to next: MeetingStatus) throws {
        guard canTransition(to: next) else {
            throw MeetingError.invalidStateTransition(from: status, to: next)
        }
        status = next
    }
    
    public func addTranscriptSegment(_ segment: TranscriptSegment) {
        segment.meeting = self
        transcriptSegments.append(segment)
    }
    
    public func addActionItem(_ item: ActionItem) {
        item.meeting = self
        actionItems.append(item)
    }
    
    public func addNote(_ note: Note) {
        note.meeting = self
        notes.append(note)
    }
}
