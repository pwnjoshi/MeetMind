import Foundation
import OSLog

/// Content-free diagnostics for one recording attempt. Never add a meeting
/// title, transcript, audio path, or other user content to this value.
public struct RecordingMetrics: Sendable, Equatable {
    public var elapsed: TimeInterval = 0
    public var writtenFrameCount: Int64 = 0
    public var writtenDuration: TimeInterval = 0
    public var sealedChunkCount: Int = 0
    public var preprocessedChunkCount: Int = 0
    public var skippedPreprocessingChunkCount: Int = 0
    public var failedPreprocessingChunkCount: Int = 0
    public var stopLatency: TimeInterval = 0
    public var interruptionCode: String?
    public var writeFailureCode: String?

    public init() {}
}

/// Thread-safe collector shared by the audio pump and preprocessing worker.
/// Metrics remain in memory because the app has no recording diagnostics store.
public final class RecordingMetricsCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var value = RecordingMetrics()
    private let logger = Logger(subsystem: "com.meetmind.app", category: "Recording")

    public init() {}

    public var snapshot: RecordingMetrics {
        lock.recordingWithLock { value }
    }

    public func recordElapsed(_ elapsed: TimeInterval) {
        lock.recordingWithLock { value.elapsed = max(0, elapsed) }
    }

    public func recordCanonicalAudio(frameCount: Int64, duration: TimeInterval) {
        lock.recordingWithLock {
            value.writtenFrameCount = max(0, frameCount)
            value.writtenDuration = max(0, duration)
        }
    }

    public func recordChunkSealed() {
        lock.recordingWithLock { value.sealedChunkCount += 1 }
    }

    public func recordPreprocessed() {
        lock.recordingWithLock { value.preprocessedChunkCount += 1 }
    }

    public func recordPreprocessingSkipped(count: Int = 1) {
        guard count > 0 else { return }
        lock.recordingWithLock { value.skippedPreprocessingChunkCount += count }
    }

    public func recordPreprocessingFailure() {
        lock.recordingWithLock { value.failedPreprocessingChunkCount += 1 }
    }

    public func recordStopLatency(_ latency: TimeInterval) {
        lock.recordingWithLock { value.stopLatency = max(0, latency) }
    }

    public func recordInterruption(code: String) {
        lock.recordingWithLock { value.interruptionCode = code }
        logger.notice("Recording interrupted code=\(code, privacy: .public)")
    }

    public func recordWriteFailure(code: String) {
        lock.recordingWithLock { value.writeFailureCode = code }
        logger.error("Recording write failure code=\(code, privacy: .public)")
    }

    public func logSummary() {
        let metrics = snapshot
        logger.notice(
            "Recording metrics elapsed_ms=\(Int(metrics.elapsed * 1_000), privacy: .public) frames=\(metrics.writtenFrameCount, privacy: .public) duration_ms=\(Int(metrics.writtenDuration * 1_000), privacy: .public) sealed=\(metrics.sealedChunkCount, privacy: .public) preprocessed=\(metrics.preprocessedChunkCount, privacy: .public) skipped=\(metrics.skippedPreprocessingChunkCount, privacy: .public) failed=\(metrics.failedPreprocessingChunkCount, privacy: .public) stop_ms=\(Int(metrics.stopLatency * 1_000), privacy: .public)"
        )
    }
}

private extension NSLock {
    func recordingWithLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}
