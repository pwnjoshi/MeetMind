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

    // Old local-only profiles predate `avatarImageData`; decode them without
    // discarding a user's saved name, role, or voice reference during upgrade.
    private enum CodingKeys: String, CodingKey {
        case name, email, role, avatarColorHex, avatarImageData, voiceProfileURL, isCalendarSyncEnabled
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "MeetMind User"
        email = try values.decodeIfPresent(String.self, forKey: .email) ?? ""
        role = try values.decodeIfPresent(String.self, forKey: .role) ?? ""
        avatarColorHex = try values.decodeIfPresent(String.self, forKey: .avatarColorHex) ?? "#3B82F6"
        avatarImageData = try values.decodeIfPresent(Data.self, forKey: .avatarImageData)
        voiceProfileURL = try values.decodeIfPresent(URL.self, forKey: .voiceProfileURL)
        isCalendarSyncEnabled = try values.decodeIfPresent(Bool.self, forKey: .isCalendarSyncEnabled) ?? false
    }
}
