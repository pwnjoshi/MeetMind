import Foundation

/// Persistent user identity and personalization profile
public struct UserProfile: Codable, Sendable, Equatable {
    public var name: String
    public var email: String
    public var role: String
    public var avatarColorHex: String
    /// Locally selected avatar data. It never leaves the device or joins a meeting export.
    public var avatarImageData: Data?
    public var voiceProfileURL: URL?
    public var isCalendarSyncEnabled: Bool
    
    public init(
        name: String = "MeetMind User",
        email: String = "",
        role: String = "",
        avatarColorHex: String = "#3B82F6",
        avatarImageData: Data? = nil,
        voiceProfileURL: URL? = nil,
        isCalendarSyncEnabled: Bool = false
    ) {
        self.name = name
        self.email = email
        self.role = role
        self.avatarColorHex = avatarColorHex
        self.avatarImageData = avatarImageData
        self.voiceProfileURL = voiceProfileURL
        self.isCalendarSyncEnabled = isCalendarSyncEnabled
    }
    
    public var initials: String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2,
           let first = parts.first?.first,
           let second = parts[1].first {
            return "\(first)\(second)".uppercased()
        } else if let first = name.first {
            return String(first).uppercased()
        }
        return "MM"
    }
    
    public static var defaultProfile: UserProfile {
        UserProfile(
            name: "MeetMind User",
            email: "",
            role: "Team Member",
            avatarColorHex: "#3B82F6",
            voiceProfileURL: nil,
            isCalendarSyncEnabled: false
        )
    }
}
