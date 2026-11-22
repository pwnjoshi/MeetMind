import Foundation
import Observation

/// JSON file in Application Support holding `MoMSidecar` keyed by meeting id.
/// Writes are atomic and file-protected; a corrupt file is reported instead of replaced.
@Observable
@MainActor
final class MoMSidecarStore {
    static let shared = MoMSidecarStore()

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var loadFailure: String?
    private var records: [String: MoMSidecar] = [:]

    nonisolated static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Manent/MinutesOfMeeting.json")
    }

    /// Pass `nil` for an in-memory store (tests).
    init(fileURL: URL? = MoMSidecarStore.defaultFileURL()) {
        self.fileURL = fileURL
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            do { records = try JSONDecoder().decode([String: MoMSidecar].self, from: Data(contentsOf: fileURL)) }
            catch { loadFailure = error.localizedDescription }
        }
    }

    func sidecar(for meetingID: UUID) -> MoMSidecar {
        records[meetingID.uuidString] ?? MoMSidecar()
    }

    func update(_ meetingID: UUID, _ change: (inout MoMSidecar) -> Void) throws {
        if loadFailure != nil { throw SidecarStoreError.corrupt("Minutes of meeting") }
        let key = meetingID.uuidString
        let previous = records[key]
        var updated = previous ?? MoMSidecar()
        change(&updated)
        records[key] = updated
        do { try persist() }
        catch {
            records[key] = previous
            throw error
        }
    }

    /// Returns the stored reference number, creating and saving one the first time.
    /// The sequence counts the numbers already issued with the same prefix, so a number never changes afterwards.
    func referenceNumber(for meetingID: UUID, title: String, date: Date) throws -> String {
        if let existing = sidecar(for: meetingID).referenceNumber { return existing }
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        let prefix = "MOM/\(MoMReference.initials(from: title))/\(year)/"
        let used = records.values.compactMap(\.referenceNumber).filter { $0.hasPrefix(prefix) }
        var sequence = used.count + 1
        var candidate = MoMReference.format(title: title, year: year, sequence: sequence)
        while used.contains(candidate) {
            sequence += 1
            candidate = MoMReference.format(title: title, year: year, sequence: sequence)
        }
        try update(meetingID) { $0.referenceNumber = candidate }
        return candidate
    }

    func remove(meetingID: UUID) throws {
        if loadFailure != nil { throw SidecarStoreError.corrupt("Minutes of meeting") }
        let key = meetingID.uuidString
        guard let previous = records.removeValue(forKey: key) else { return }
        do { try persist() }
        catch {
            records[key] = previous
            throw error
        }
    }

    func eraseAll() throws {
        let previous = records
        records.removeAll()
        do {
            if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            loadFailure = nil
        } catch {
            records = previous
            throw error
        }
    }

    var isEmpty: Bool { records.isEmpty }

    private func persist() throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(records)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
