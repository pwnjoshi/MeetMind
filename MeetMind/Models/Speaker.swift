import Foundation
import SwiftData

@Model
public final class Speaker: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var email: String?
    public var role: String?
    public var avatarColorHex: String
    public var voiceSampleURL: URL?
    public var recordingVoiceLabel: String?
    
    public var colorHex: String {
        get { avatarColorHex }
        set { avatarColorHex = newValue }
    }
    
    // Relationships
    @Relationship(deleteRule: .nullify)
    public var meetings: [Meeting]
    
    @Relationship(deleteRule: .nullify)
    public var transcriptSegments: [TranscriptSegment]
    
    @Relationship(deleteRule: .nullify)
    public var assignedActionItems: [ActionItem]
    
    public init(
        id: UUID = UUID(),
        name: String,
        email: String? = nil,
        role: String? = nil,
        avatarColorHex: String = "#3B82F6",
        voiceSampleURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.role = role
        self.avatarColorHex = avatarColorHex
        self.voiceSampleURL = voiceSampleURL
        self.meetings = []
        self.transcriptSegments = []
        self.assignedActionItems = []
    }
    
    public var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2,
           let first = components.first?.first,
           let second = components[1].first {
            return "\(first)\(second)".uppercased()
        } else if let first = name.first {
            return String(first).uppercased()
        }
        return "?"
    }
    
    public var displayLabel: String {
        if let role = role, !role.isEmpty {
            return "\(name) (\(role))"
        }
        return name
    }
}

extension Speaker: ExpressibleByStringLiteral, CustomStringConvertible {
    public convenience init(stringLiteral value: String) {
        self.init(name: value)
    }
    
    public var description: String { name }
}

public func == (lhs: Speaker?, rhs: String?) -> Bool {
    return lhs?.name == rhs
}

public func == (lhs: String?, rhs: Speaker?) -> Bool {
    return lhs == rhs?.name
}

// MARK: - Display helpers

extension Speaker {
    /// Shown only when a transcript line has no speaker at all.
    public static let unknownDisplayName = "Unknown Speaker"

    /// The one name every screen, export and Vidur source row shows for this speaker.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Speaker.unknownDisplayName : trimmed
    }

    /// True for a detected voice ("Speaker 2") that nobody has named yet.
    public var isUnnamedVoice: Bool {
        guard let label = recordingVoiceLabel else { return false }
        return name == label
    }

    /// Name for an optional speaker. "Unknown Speaker" only when there is no speaker.
    public static func displayName(of speaker: Speaker?) -> String {
        speaker?.displayName ?? unknownDisplayName
    }
}