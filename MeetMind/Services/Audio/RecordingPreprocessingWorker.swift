import Foundation
import OfflineEngineKit

public protocol RecordingChunkPreprocessing: Sendable {
    func prepare(
        meetingID: UUID,
        chunk: RecordingAudioChunk,
        languageCode: String?
    ) async throws -> Bool
}

public struct PipelineRecordingChunkPreprocessor: RecordingChunkPreprocessing {
    public init() {}

    public func prepare(
        meetingID: UUID,
        chunk: RecordingAudioChunk,
        languageCode: String?
    ) async throws -> Bool {
        // MeetingAnalysisPipeline currently verifies and constructs its ASR
        // engine per call. Keep that optimization behind the package API rather
        // than coupling recording to WhisperKit internals.
        try await MeetingAnalysisPipeline.shared.prepareRecordingChunk(
            meetingID: meetingID,
            sequence: chunk.sequence,
            audio: chunk.fileURL,
            chunkStartTime: chunk.startTime,
            contentStartTime: chunk.contentStartTime,
            endTime: chunk.endTime,
            languageCode: languageCode
        )
    }
}

/// Serial, opportunistic consumer for sealed chunks. Cancellation is immediate
/// to the caller: Stop only signals this task and never waits for inference.
public final class RecordingPreprocessingWorker: @unchecked Sendable {
    public typealias Admission = @Sendable () -> Bool

    private let stream: AsyncStream<RecordingAudioChunk>
    private let meetingID: UUID
    private let languageCode: String?
    private let preprocessor: any RecordingChunkPreprocessing
    private let metrics: RecordingMetricsCollector
    private let admission: Admission
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    public init(
        chunks: AsyncStream<RecordingAudioChunk>,
        meetingID: UUID,
        languageCode: String?,
        preprocessor: any RecordingChunkPreprocessing = PipelineRecordingChunkPreprocessor(),
        metrics: RecordingMetricsCollector = RecordingMetricsCollector(),
        admission: @escaping Admission = RecordingPreprocessingWorker.defaultAdmission
    ) {
        stream = chunks
        self.meetingID = meetingID
        self.languageCode = languageCode
        self.preprocessor = preprocessor
        self.metrics = metrics
        self.admission = admission
    }

    public func start() {
        lock.lock()
        guard task == nil else {
            lock.unlock()
            return
        }
        task = Task.detached(priority: .utility) { [stream, meetingID, languageCode, preprocessor, metrics, admission] in
            for await chunk in stream {
                guard !Task.isCancelled else {
                    metrics.recordPreprocessingSkipped()
                    break
                }
                guard admission() else {
                    metrics.recordPreprocessingSkipped()
                    continue
                }
                do {
                    let prepared = try await preprocessor.prepare(
                        meetingID: meetingID,
                        chunk: chunk,
                        languageCode: languageCode
                    )
                    guard !Task.isCancelled else {
                        metrics.recordPreprocessingSkipped()
                        break
                    }
                    if prepared {
                        metrics.recordPreprocessed()
                    } else {
                        metrics.recordPreprocessingSkipped()
                    }
                } catch is CancellationError {
                    metrics.recordPreprocessingSkipped()
                    break
                } catch {
                    metrics.recordPreprocessingFailure()
                }
            }
        }
        lock.unlock()
    }

    public func cancel() {
        lock.lock()
        let task = task
        self.task = nil
        lock.unlock()
        task?.cancel()
    }

    public static func defaultAdmission() -> Bool {
        ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
