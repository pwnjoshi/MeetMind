import Foundation
import OSLog
import OfflineEngineKit

/// Measures how long one Vidur answer takes and writes a single content-free log line, for example
/// `Vidur answer tier=generated first_token_ms=3120 total_ms=5480`. It never sees or logs a question,
/// an answer or a meeting name. Filter for "Vidur answer" in Console while the iPhone is connected.
final class VidurLatencyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let started = Date()
    private var firstTokenMs: Int?
    private var didLog = false

    static func tierName(_ tier: VidurAnswerTier) -> String {
        switch tier {
        case .none: return "none"
        case .structured: return "structured"
        case .quote: return "quote"
        case .generated: return "generated"
        }
    }

    private func elapsedMs() -> Int {
        Int((Date().timeIntervalSince(started) * 1_000).rounded())
    }

    /// Call for every update. The first update that carries text sets the time to first words, and the
    /// final update writes the log line.
    func observe(_ update: VidurAnswerUpdate) {
        lock.lock()
        if firstTokenMs == nil, let text = update.answer?.text, !text.isEmpty { firstTokenMs = elapsedMs() }
        let shouldLog = update.stage == .final && !didLog
        let first = firstTokenMs
        if shouldLog { didLog = true }
        lock.unlock()
        guard shouldLog else { return }
        let line = VidurLatency.line(tier: Self.tierName(update.tier), firstTokenMs: first, totalMs: elapsedMs())
        Logger(subsystem: "com.meetmind.app", category: "Vidur").notice("\(line, privacy: .public)")
    }
}
