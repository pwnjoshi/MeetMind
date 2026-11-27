import XCTest
@testable import MeetMind

/// The worker only schedules optional pre-analysis after a chunk was prepared,
/// serially, behind its own admission gate, and stops at the first cancellation.
final class RecordingPreAnalysisWorkerTests: XCTestCase {
    private let meetingDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func chunk(_ sequence: Int) -> RecordingAudioChunk {
        RecordingAudioChunk(id: UUID(), sequence: sequence, filePath: "/tmp/pre-analysis-\(sequence).caf",
                            startTime: Double(sequence) * 30, contentStartTime: Double(sequence) * 30,
                            endTime: Double(sequence + 1) * 30)
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async throws {
        for _ in 0..<300 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition was not reached in time")
    }

    private func makeWorker(
        spy: PreAnalysisSpy,
        context: RecordingPreAnalysisContext?,
        preAnalysisAdmission: @escaping RecordingPreprocessingWorker.Admission = { true }
    ) -> (RecordingPreprocessingWorker, AsyncStream<RecordingAudioChunk>.Continuation) {
        let stream = AsyncStream.makeStream(of: RecordingAudioChunk.self)
        let worker = RecordingPreprocessingWorker(
            chunks: stream.stream, meetingID: UUID(), languageCode: "hi", preprocessor: spy,
            metrics: RecordingMetricsCollector(), admission: { true },
            preAnalysis: context, preAnalysisAdmission: preAnalysisAdmission)
        return (worker, stream.continuation)
    }

    func test_preAnalysisRunsAfterEachPreparedChunkWithMeetingContext() async throws {
        let spy = PreAnalysisSpy()
        let context = RecordingPreAnalysisContext(meetingDate: meetingDate, timezone: "Asia/Kolkata")
        let (worker, source) = makeWorker(spy: spy, context: context)
        worker.start()
        source.yield(chunk(0))
        source.yield(chunk(1))

        try await waitUntil { await spy.preAnalyzeCalls.count == 2 }

        let calls = await spy.preAnalyzeCalls
        XCTAssertEqual(calls.map(\.timezone), ["Asia/Kolkata", "Asia/Kolkata"])
        XCTAssertEqual(calls.map(\.date), [meetingDate, meetingDate])
        let order = await spy.events
        XCTAssertEqual(order, ["prepare", "preAnalyze", "prepare", "preAnalyze"],
                       "Work is strictly serial: pre-analysis never overlaps preparation")
        source.finish()
        worker.cancel()
    }

    func test_noPreAnalysisWithoutContextOrWhenChunkWasNotPrepared() async throws {
        let withoutContext = PreAnalysisSpy()
        let (first, firstSource) = makeWorker(spy: withoutContext, context: nil)
        first.start()
        firstSource.yield(chunk(0))
        try await waitUntil { await withoutContext.prepareCount == 1 }

        let unprepared = PreAnalysisSpy(prepareResult: false)
        let context = RecordingPreAnalysisContext(meetingDate: meetingDate, timezone: "UTC")
        let (second, secondSource) = makeWorker(spy: unprepared, context: context)
        second.start()
        secondSource.yield(chunk(0))
        try await waitUntil { await unprepared.prepareCount == 1 }

        try await Task.sleep(for: .milliseconds(100))
        let first_ = await withoutContext.preAnalyzeCalls.count
        let second_ = await unprepared.preAnalyzeCalls.count
        XCTAssertEqual(first_, 0)
        XCTAssertEqual(second_, 0)
        firstSource.finish(); secondSource.finish()
        first.cancel(); second.cancel()
    }

    func test_closedAdmissionGateSkipsPreAnalysisButStillPreparesChunks() async throws {
        let spy = PreAnalysisSpy()
        let context = RecordingPreAnalysisContext(meetingDate: meetingDate, timezone: "UTC")
        let (worker, source) = makeWorker(spy: spy, context: context, preAnalysisAdmission: { false })
        worker.start()
        source.yield(chunk(0))
        source.yield(chunk(1))

        try await waitUntil { await spy.prepareCount == 2 }

        let count = await spy.preAnalyzeCalls.count
        XCTAssertEqual(count, 0)
        source.finish()
        worker.cancel()
    }

    func test_unexpectedPreAnalysisFailureDisablesItWithoutStoppingPreparation() async throws {
        let spy = PreAnalysisSpy(preAnalyzeError: PreAnalysisSpy.Failure.boom)
        let context = RecordingPreAnalysisContext(meetingDate: meetingDate, timezone: "UTC")
        let (worker, source) = makeWorker(spy: spy, context: context)
        worker.start()
        source.yield(chunk(0))
        try await waitUntil { await spy.preAnalyzeCalls.count == 1 }
        source.yield(chunk(1))

        try await waitUntil { await spy.prepareCount == 2 }

        try await Task.sleep(for: .milliseconds(50))
        let count = await spy.preAnalyzeCalls.count
        XCTAssertEqual(count, 1, "A failed pre-analysis is not retried for the rest of the recording")
        source.finish()
        worker.cancel()
    }

    func test_cancelInterruptsPreAnalysisPromptly() async throws {
        let spy = PreAnalysisSpy(blocksInPreAnalysis: true)
        let context = RecordingPreAnalysisContext(meetingDate: meetingDate, timezone: "UTC")
        let (worker, source) = makeWorker(spy: spy, context: context)
        worker.start()
        source.yield(chunk(0))
        try await waitUntil { await spy.preAnalyzeCalls.count == 1 }

        let started = Date()
        worker.cancel()
        try await waitUntil { await spy.preAnalysisWasCancelled }

        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        source.finish()
    }
}

private actor PreAnalysisSpy: RecordingChunkPreprocessing {
    enum Failure: Error { case boom }
    struct Call: Sendable { let date: Date; let timezone: String }

    private let prepareResult: Bool
    private let preAnalyzeError: Error?
    private let blocksInPreAnalysis: Bool
    private(set) var prepareCount = 0
    private(set) var preAnalyzeCalls: [Call] = []
    private(set) var events: [String] = []
    private(set) var preAnalysisWasCancelled = false

    init(prepareResult: Bool = true, preAnalyzeError: Error? = nil, blocksInPreAnalysis: Bool = false) {
        self.prepareResult = prepareResult
        self.preAnalyzeError = preAnalyzeError
        self.blocksInPreAnalysis = blocksInPreAnalysis
    }

    func prepare(meetingID: UUID, chunk: RecordingAudioChunk, languageCode: String?) async throws -> Bool {
        prepareCount += 1
        events.append("prepare")
        return prepareResult
    }

    func preAnalyze(meetingID: UUID, meetingDate: Date, timezone: String) async throws -> Bool {
        preAnalyzeCalls.append(Call(date: meetingDate, timezone: timezone))
        events.append("preAnalyze")
        if let preAnalyzeError { throw preAnalyzeError }
        if blocksInPreAnalysis {
            do { try await Task.sleep(for: .seconds(30)) }
            catch {
                preAnalysisWasCancelled = true
                throw error
            }
        }
        return true
    }
}
