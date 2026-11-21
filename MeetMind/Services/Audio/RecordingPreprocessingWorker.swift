import Foundation
import OfflineEngineKit

public protocol RecordingChunkPreprocessing: Sendable {
    func prepare(
        meetingID: UUID,
        chunk: RecordingAudioChunk,
        languageCode: String?
    ) async throws -> Bool

    /// Optionally analyzes finalized transcript windows while recording continues.
    /// Returns true when at least one chunk was analyzed. The default does nothing.
    func preAnalyze(meetingID: UUID, meetingDate: Date, timezone: String) async throws -> Bool
}

public extension RecordingChunkPreprocessing {
    func preAnalyze(meetingID: UUID, meetingDate: Date, timezone: String) async throws -> Bool { false }
}

/// Meeting facts the analysis prompt depends on. Pre-analysis results are reused
/// only when the final pass uses the same day and time zone.
public struct RecordingPreAnalysisContext: Sendable, Equatable {
    public let meetingDate: Date
    public let timezone: String

    public init(meetingDate: Date, timezone: String) {
        self.meetingDate = meetingDate
        self.timezone = timezone
    }
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

    public func preAnalyze(meetingID: UUID, meetingDate: Date, timezone: String) async throws -> Bool {
        // The pipeline enforces thermal, Low Power, model-installed, and memory
        // admission (with an extra reserve) and analyzes at most one chunk.
        try await MeetingAnalysisPipeline.shared.preAnalyzeRecording(
            meetingID: meetingID, meetingDate: meetingDate, timezone: timezone
        ) > 0
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
    private let preAnalysis: RecordingPreAnalysisContext?
    private let preAnalysisAdmission: Admission
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    public init(
        chunks: AsyncStream<RecordingAudioChunk>,
        meetingID: UUID,
        languageCode: String?,
        preprocessor: any RecordingChunkPreprocessing = PipelineRecordingChunkPreprocessor(),
        metrics: RecordingMetricsCollector = RecordingMetricsCollector(),
        admission: @escaping Admission = RecordingPreprocessingWorker.defaultAdmission,
        preAnalysis: RecordingPreAnalysisContext? = nil,
        preAnalysisAdmission: @escaping Admission = RecordingPreprocessingWorker.defaultAdmission
    ) {
        stream = chunks
        self.meetingID = meetingID
        self.languageCode = languageCode
        self.preprocessor = preprocessor
        self.metrics = metrics
        self.admission = admission
        self.preAnalysis = preAnalysis
        self.preAnalysisAdmission = preAnalysisAdmission
    }

    public func start() {
        lock.lock()
        guard task == nil else {
            lock.unlock()
            return
        }
        task = Task.detached(priority: .utility) { [stream, meetingID, languageCode, preprocessor, metrics, admission, preAnalysis, preAnalysisAdmission] in
            // Pre-analysis is optional. One unexpected failure turns it off for the
            // rest of this recording instead of retrying after every chunk.
            var preAnalysisEnabled = preAnalysis != nil
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
                        if preAnalysisEnabled, let context = preAnalysis, preAnalysisAdmission() {
                            do {
                                _ = try await preprocessor.preAnalyze(
                                    meetingID: meetingID,
                                    meetingDate: context.meetingDate,
                                    timezone: context.timezone
                                )
                            } catch is CancellationError {
                                break
                            } catch {
                                preAnalysisEnabled = false
                            }
                        }
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
