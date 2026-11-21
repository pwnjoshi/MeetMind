import AVFoundation
import Foundation

/// Drains microphone buffers into rolling files without ever waiting for
/// preprocessing. The bounded descriptor stream drops the oldest unprocessed
/// descriptor when full. Only optional preprocessing work is dropped; the
/// canonical recorder writes independently before a buffer reaches this pump.
public final class RecordingChunkPump: @unchecked Sendable {
    public static let defaultQueueCapacity = 2

    private let writer: RollingAudioChunkWriter
    private let metrics: RecordingMetricsCollector
    private let descriptorContinuation: AsyncStream<RecordingAudioChunk>.Continuation
    public let sealedChunks: AsyncStream<RecordingAudioChunk>

    private let lock = NSLock()
    private var drainTask: Task<Void, Never>?
    private var finishedChunks: [RecordingAudioChunk] = []
    private var finishError: Error?

    public init(
        writer: RollingAudioChunkWriter,
        queueCapacity: Int = RecordingChunkPump.defaultQueueCapacity,
        metrics: RecordingMetricsCollector = RecordingMetricsCollector()
    ) {
        self.writer = writer
        self.metrics = metrics
        let stream = AsyncStream.makeStream(
            of: RecordingAudioChunk.self,
            bufferingPolicy: .bufferingNewest(max(1, queueCapacity))
        )
        sealedChunks = stream.stream
        descriptorContinuation = stream.continuation
    }

    public func start(draining buffers: AsyncStream<AVAudioPCMBuffer>) {
        lock.lock()
        guard drainTask == nil else {
            lock.unlock()
            return
        }
        drainTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { self.descriptorContinuation.finish() }
            do {
                for await buffer in buffers {
                    guard !Task.isCancelled else { break }
                    if let chunk = try self.writer.append(buffer) {
                        self.offerForPreprocessing(chunk)
                    }
                }
                let existingCount = self.metrics.snapshot.sealedChunkCount
                let chunks = try self.writer.finish()
                if chunks.count > existingCount {
                    for chunk in chunks.dropFirst(existingCount) {
                        self.offerForPreprocessing(chunk)
                    }
                }
                self.lock.lock()
                self.finishedChunks = chunks
                self.lock.unlock()
            } catch {
                self.metrics.recordWriteFailure(code: "rolling_chunk_write_failed")
                self.lock.lock()
                self.finishError = error
                self.lock.unlock()
            }
        }
        lock.unlock()
    }

    /// Waits only for the quick writer drain. Inference runs in a different
    /// task and is never awaited here.
    public func finishAfterSourceEnds() async throws -> [RecordingAudioChunk] {
        lock.lock()
        let task = drainTask
        lock.unlock()
        await task?.value
        lock.lock()
        defer { lock.unlock() }
        if let finishError { throw finishError }
        return finishedChunks
    }

    public func cancelAndDiscard() {
        lock.lock()
        let task = drainTask
        drainTask = nil
        lock.unlock()
        task?.cancel()
        descriptorContinuation.finish()
        writer.discard()
    }

    private func offerForPreprocessing(_ chunk: RecordingAudioChunk) {
        metrics.recordChunkSealed()
        switch descriptorContinuation.yield(chunk) {
        case .enqueued:
            break
        case .dropped:
            metrics.recordPreprocessingSkipped()
        case .terminated:
            metrics.recordPreprocessingSkipped()
        @unknown default:
            metrics.recordPreprocessingSkipped()
        }
    }
}
