import Foundation
import Network
import Observation

public enum ConnectivityKind: String, Sendable, Equatable {
    case offline
    case wifi
    case cellular
    case wired
    case other

    public var displayName: String {
        switch self {
        case .offline: return "Offline"
        case .wifi: return "Wi-Fi"
        case .cellular: return "Cellular"
        case .wired: return "Wired network"
        case .other: return "Network"
        }
    }

    public static func map(isSatisfied: Bool, usesWiFi: Bool = false,
                           usesCellular: Bool = false, usesWired: Bool = false) -> ConnectivityKind {
        guard isSatisfied else { return .offline }
        if usesWiFi { return .wifi }
        if usesCellular { return .cellular }
        if usesWired { return .wired }
        return .other
    }
}

public struct ConnectivitySnapshot: Sendable, Equatable {
    public let kind: ConnectivityKind
    public let isExpensive: Bool
    public let isConstrained: Bool

    public init(kind: ConnectivityKind, isExpensive: Bool = false, isConstrained: Bool = false) {
        self.kind = kind
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }

    public var isOnline: Bool { kind != .offline }
}

public enum DownloadNetworkDecision: Sendable, Equatable {
    case allow
    case confirmCellular
    case offline
}

public enum DownloadAccessPolicy {
    public static let largeDownloadThresholdBytes: Int64 = 100_000_000

    public static func decision(for bytes: Int64, connectivity: ConnectivitySnapshot) -> DownloadNetworkDecision {
        guard connectivity.isOnline else { return .offline }
        if bytes > largeDownloadThresholdBytes,
           connectivity.kind == .cellular || connectivity.isExpensive {
            return .confirmCellular
        }
        return .allow
    }
}

@Observable
@MainActor
public final class ConnectivityMonitor {
    public static let shared = ConnectivityMonitor()

    public private(set) var snapshot = ConnectivitySnapshot(kind: .offline)

    @ObservationIgnored private let monitor: NWPathMonitor
    @ObservationIgnored private let queue = DispatchQueue(label: "com.meetmind.connectivity", qos: .utility)

    public init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let snapshot = ConnectivitySnapshot(
                kind: ConnectivityKind.map(
                    isSatisfied: path.status == .satisfied,
                    usesWiFi: path.usesInterfaceType(.wifi),
                    usesCellular: path.usesInterfaceType(.cellular),
                    usesWired: path.usesInterfaceType(.wiredEthernet)
                ),
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained
            )
            Task { @MainActor [weak self] in self?.snapshot = snapshot }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
