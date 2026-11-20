import Foundation

/// What the local user recorded about an owner's answer to a shared task.
public enum TaskResponseKind: String, Codable, Sendable {
    case confirmed
    case correctionRequested
}

/// A response the local user wrote down for a task. The app never receives a
/// reply from anyone; this only records what the user was told.
public struct TaskResponse: Codable, Equatable, Sendable {
    public var kind: TaskResponseKind
    public var correctionText: String?
    public var recordedAt: Date

    public init(kind: TaskResponseKind, correctionText: String? = nil, recordedAt: Date = Date()) {
        self.kind = kind
        self.correctionText = correctionText
        self.recordedAt = recordedAt
    }

    /// Short status line shown on the task.
    public var summary: String {
        switch kind {
        case .confirmed:
            return "Confirmed by owner"
        case .correctionRequested:
            let text = (correctionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "Correction requested" : "Correction requested: \(text)"
        }
    }

    /// Plain text the user may share themselves (Messages, Mail, and so on).
    public func shareText(taskTitle: String, ownerName: String?) -> String {
        let owner = (ownerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = owner.isEmpty ? "Task" : "Task for \(owner)"
        return "\(prefix): \(taskTitle)\n\(summary)"
    }
}

/// Local JSON store of `TaskResponse` values keyed by `ActionItem.id`.
/// Lives in Application Support and never leaves the device.
@MainActor
public final class TaskResponseStore {
    public static let shared = TaskResponseStore()

    private let fileURL: URL?
    private var responses: [String: TaskResponse] = [:]

    /// Pass `nil` for a memory-only store (tests, previews).
    public init(fileURL: URL? = TaskResponseStore.defaultFileURL()) {
        self.fileURL = fileURL
        load()
    }

    nonisolated public static func defaultFileURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appendingPathComponent("MeetMind", isDirectory: true)
            .appendingPathComponent("TaskResponses.json", isDirectory: false)
    }

    public func response(for actionItemID: UUID) -> TaskResponse? {
        responses[actionItemID.uuidString]
    }

    public var count: Int { responses.count }

    public func record(_ response: TaskResponse, for actionItemID: UUID) throws {
        let previous = responses[actionItemID.uuidString]
        responses[actionItemID.uuidString] = response
        do {
            try persist()
        } catch {
            responses[actionItemID.uuidString] = previous
            throw error
        }
    }

    /// Removes any response for the task. Does nothing when none exists.
    public func remove(for actionItemID: UUID) {
        guard responses.removeValue(forKey: actionItemID.uuidString) != nil else { return }
        try? persist()
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: TaskResponse].self, from: data) else {
            return
        }
        responses = decoded
    }

    private func persist() throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(responses)
        try data.write(to: fileURL, options: .atomic)
    }
}
