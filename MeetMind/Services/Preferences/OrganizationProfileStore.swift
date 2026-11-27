import Foundation

/// Organization details printed on the letterhead preview. Stored only on this iPhone.
/// The organization name itself lives under the existing `Manent.workspaceName` key.
public struct OrganizationDetails: Codable, Equatable, Sendable {
    public var address: String = ""
    public var cin: String = ""
    public var gstin: String = ""
    public var phone: String = ""
    public var email: String = ""

    public init() {}

    public var contactLine: String {
        [phone, email].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }
}

/// Small Codable store for `OrganizationDetails`. Wire `eraseAll()` into the erase-all coordinator.
public struct OrganizationProfileStore: Sendable {
    public static let defaultsKey = "Manent.organizationDetails"
    public static let nameKey = "Manent.workspaceName"

    public init() {}

    public func load(defaults: UserDefaults = .standard) -> OrganizationDetails {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let details = try? JSONDecoder().decode(OrganizationDetails.self, from: data) else {
            return OrganizationDetails()
        }
        return details
    }

    public func save(_ details: OrganizationDetails, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(details) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    public func eraseAll(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
