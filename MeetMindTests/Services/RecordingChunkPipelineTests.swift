import AVFoundation
import XCTest
@testable import MeetMind

final class RecordingChunkPipelineTests: XCTestCase {
    func test_stageD_blockedPreprocessingDoesNotBlockPumpAndBoundedQueueDropsOnlyWork() async throws {
        let writer = try RollingAudioChunkWriter(meetingID: UUID())
        let metrics = RecordingMetricsCollector()
        let pump = RecordingChunkPump(writer: writer, queueCapacity: 1, metrics: metrics)
        let blocker = BlockingChunkPreprocessor()
        let worker = RecordingPreprocessingWorker(
            chunks: pump.sealedChunks,
            meetingID: UUID(),
            languageCode: "en",
            preprocessor: blocker,
            metrics: metrics,
            admission: { true }
        )
        let source = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
        pump.start(draining: source.stream)
        worker.start()

        let buffer = try makeBuffer(duration: 31)
        source.continuation.yield(buffer)
        try await waitForPreprocessor(blocker)
        for _ in 0..<5 { source.continuation.yield(buffer) }
        source.continuation.finish()

        let chunks = try await pump.finishAfterSourceEnds()
        worker.cancel()
        let snapshot = metrics.snapshot

        XCTAssertGreaterThanOrEqual(chunks.count, 6)
        XCTAssertEqual(snapshot.sealedChunkCount, chunks.count)
        XCTAssertGreaterThan(snapshot.skippedPreprocessingChunkCount, 0)
        XCTAssertEqual(snapshot.preprocessedChunkCount, 0)
        pump.cancelAndDiscard()
    }

    @MainActor
    func test_stageD_stopReturnsWithoutWaitingForBlockedPreprocessing() async throws {
        let service = MockAudioRecordingService()
        service.automaticallyAdvancesDuration = false
        let blocker = BlockingChunkPreprocessor()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("stage-d-stop-\(UUID().uuidString).m4a")
        let viewModel = LiveRecordingViewModel(
            recordingService: service,
            destinationAudioURL: output,
            updatesFromRecordingClock: false,
            chunkPreprocessor: blocker
        )
        viewModel.startSession()
        try await viewModel.waitUntilRecordingStarted()
        service.emitAudioBuffer(try makeBuffer(duration: 31))
        try await waitForPreprocessor(blocker)

        let started = Date()
        let savedURL = try await viewModel.finishSession()
        let latency = Date().timeIntervalSince(started)

        XCTAssertEqual(savedURL, output)
        XCTAssertEqual(viewModel.recordingState, .saved)
        XCTAssertLessThan(latency, 1.0)
        XCTAssertLessThan(viewModel.recordingMetrics.stopLatency, 1.0)
        viewModel.confirmDiscard()
    }

    func test_stageD_canonicalValidatorAcceptsNonzeroFramesAndDuration() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stage-d-valid-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try writePCMFile(to: url, frameCount: 8_000, sampleRate: 8_000)

        let info = try CanonicalRecordingValidator.validate(url)

        XCTAssertEqual(info.frameCount, 8_000)
        XCTAssertEqual(info.duration, 1, accuracy: 0.001)
    }

    func test_stageD_canonicalValidatorRejectsMissingAndZeroFrameFilesPrecisely() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("stage-d-missing-\(UUID().uuidString).caf")
        XCTAssertThrowsError(try CanonicalRecordingValidator.validate(missing)) { error in
            XCTAssertEqual(error as? CanonicalRecordingValidationError, .fileMissing)
        }

        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("stage-d-empty-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: empty) }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1) else {
            return XCTFail("Could not create test format")
        }
        _ = try AVAudioFile(forWriting: empty, settings: format.settings)
        XCTAssertThrowsError(try CanonicalRecordingValidator.validate(empty)) { error in
            XCTAssertEqual(error as? CanonicalRecordingValidationError, .emptyAudio)
        }
    }

    private func makeBuffer(duration: TimeInterval) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 100, channels: 1),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(duration * format.sampleRate)
              ) else {
            throw TestError.bufferCreation
        }
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData?.pointee.initialize(repeating: 0, count: Int(buffer.frameLength))
        return buffer
    }

    private func writePCMFile(to url: URL, frameCount: AVAudioFrameCount, sampleRate: Double) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw TestError.bufferCreation
        }
        buffer.frameLength = frameCount
        buffer.floatChannelData?.pointee.initialize(repeating: 0, count: Int(frameCount))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private func waitForPreprocessor(_ blocker: BlockingChunkPreprocessor) async throws {
        for _ in 0..<100 {
            if await blocker.callCount > 0 { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Preprocessor did not receive a sealed chunk")
    }

    private enum TestError: Error { case bufferCreation }
}

private actor BlockingChunkPreprocessor: RecordingChunkPreprocessing {
    private(set) var callCount = 0

    func prepare(
        meetingID: UUID,
        chunk: RecordingAudioChunk,
        languageCode: String?
    ) async throws -> Bool {
        callCount += 1
        try await Task.sleep(for: .seconds(30))
        return true
    }
}
