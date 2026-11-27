import XCTest
import AVFoundation
@testable import OfflineEngineKit

/// Gap-only transcription reuse and pre-analysis during recording, proven with a
/// fake backend so no model is needed.
final class RecordingReuseTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: Fixtures

    private func makeSilentAudio(seconds: Int) throws -> (root: URL, audio: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audio = root.appendingPathComponent("synthetic.caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000))
        buffer.frameLength = 8000
        buffer.floatChannelData?[0].update(repeating: 0, count: 8000)
        let file = try AVAudioFile(forWriting: audio, settings: format.settings)
        for _ in 0..<seconds { try file.write(from: buffer) }
        return (root, audio)
    }

    private func prepare(_ pipeline: MeetingAnalysisPipeline, id: UUID, sequence: Int,
                         chunkStart: Double, content: Double, end: Double) async throws {
        let prepared = try await pipeline.prepareRecordingChunk(
            meetingID: id, sequence: sequence, audio: URL(fileURLWithPath: "/tmp/chunk-\(sequence).caf"),
            chunkStartTime: chunkStart, contentStartTime: content, endTime: end)
        XCTAssertTrue(prepared)
    }

    private func speech(_ text: String, _ start: Double, _ end: Double) -> [AnalysisTurn] {
        [AnalysisTurn(id: "raw", text: text, start: start, end: end, speaker: nil)]
    }

    private func longTurns(prefix: String = "turn") -> [AnalysisTurn] {
        (0..<8).map {
            AnalysisTurn(id: "raw-\($0)", text: "\(prefix)\($0) " + String(repeating: "x", count: 493),
                         start: Double($0) * 3, end: Double($0) * 3 + 2, speaker: nil)
        }
    }

    private func window(_ sequence: Int, _ start: Double, _ end: Double,
                        turns: [AnalysisTurn] = []) -> PreparedRecordingChunk {
        PreparedRecordingChunk(sequence: sequence, contentStartTime: start, endTime: end, turns: turns)
    }

    // MARK: Gap-only transcription

    func testFinalPassTranscribesOnlyTheUncoveredRanges() async throws {
        let (root, audio) = try makeSilentAudio(seconds: 120)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = ReuseBackend(root: root)
        let pipeline = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root, resourceGate: { true })
        let id = UUID()
        backend.setChunk(0, speech("alpha speech", 2, 6))
        backend.setChunk(2, speech("beta speech", 8, 12))
        try await prepare(pipeline, id: id, sequence: 0, chunkStart: 0, content: 0, end: 30)
        try await prepare(pipeline, id: id, sequence: 2, chunkStart: 55, content: 60, end: 90)

        let result = try await pipeline.run(meetingID: id, audio: audio, meetingDate: date,
                                            timezone: "UTC", model: .fast) { _ in }

        let durations = backend.finalTranscriptionDurations
        XCTAssertEqual(durations.count, 2, "Only the two uncovered ranges may be transcribed")
        for value in durations { XCTAssertEqual(value, 30, accuracy: 0.05) }
        XCTAssertEqual(result.turns.map(\.text), ["alpha speech", "gap speech 30", "beta speech", "gap speech 30"])
        XCTAssertEqual(result.turns.map(\.start), result.turns.map(\.start).sorted())
        XCTAssertEqual(result.turns[1].start, 31, accuracy: 0.05)
        XCTAssertEqual(result.turns[3].start, 91, accuracy: 0.05)
        XCTAssertEqual(result.turns[2].start, 63, accuracy: 0.05)
        let summary = try XCTUnwrap(TranscriptReuseRegistry.shared.summary(for: id))
        XCTAssertTrue(summary.partiallyReused)
        XCTAssertEqual(summary.reusedSeconds, 60, accuracy: 0.05)
        XCTAssertEqual(summary.transcribedSeconds, 60, accuracy: 0.05)
    }

    func testFullyPreparedRecordingIsNotTranscribedAgain() async throws {
        let (root, audio) = try makeSilentAudio(seconds: 60)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = ReuseBackend(root: root)
        let pipeline = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root, resourceGate: { true })
        let id = UUID()
        backend.setChunk(0, speech("first half", 2, 6))
        backend.setChunk(1, speech("second half", 8, 12))
        try await prepare(pipeline, id: id, sequence: 0, chunkStart: 0, content: 0, end: 30)
        try await prepare(pipeline, id: id, sequence: 1, chunkStart: 25, content: 30, end: 60)

        let result = try await pipeline.run(meetingID: id, audio: audio, meetingDate: date,
                                            timezone: "UTC", model: .fast) { _ in }

        XCTAssertTrue(backend.finalTranscriptionDurations.isEmpty)
        XCTAssertEqual(result.turns.map(\.text), ["first half", "second half"])
        XCTAssertEqual(result.stage, .completed)
        XCTAssertEqual(try XCTUnwrap(TranscriptReuseRegistry.shared.summary(for: id)).fullyReused, true)
    }

    func testMostlyUnpreparedRecordingUsesOneWholeFilePass() async throws {
        let (root, audio) = try makeSilentAudio(seconds: 240)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = ReuseBackend(root: root)
        let pipeline = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root, resourceGate: { true })
        let id = UUID()
        backend.setChunk(0, speech("only early speech", 2, 6))
        try await prepare(pipeline, id: id, sequence: 0, chunkStart: 0, content: 0, end: 30)

        let result = try await pipeline.run(meetingID: id, audio: audio, meetingDate: date,
                                            timezone: "UTC", model: .fast) { _ in }

        XCTAssertEqual(backend.finalTranscriptionDurations.count, 1)
        XCTAssertEqual(try XCTUnwrap(backend.finalTranscriptionDurations.first), 240, accuracy: 0.05)
        XCTAssertEqual(result.turns.map(\.text), ["gap speech 240"])
        XCTAssertEqual(try XCTUnwrap(TranscriptReuseRegistry.shared.summary(for: id)).reusedSeconds, 0, accuracy: 0.05)
    }

    func testPreparedWindowsOfAnotherMeetingAreIgnored() async throws {
        let (root, audio) = try makeSilentAudio(seconds: 60)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = ReuseBackend(root: root)
        let pipeline = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root, resourceGate: { true })
        backend.setChunk(0, speech("other meeting", 2, 6))
        try await prepare(pipeline, id: UUID(), sequence: 0, chunkStart: 0, content: 0, end: 60)

        let result = try await pipeline.run(meetingID: UUID(), audio: audio, meetingDate: date,
                                            timezone: "UTC", model: .fast) { _ in }

        XCTAssertEqual(backend.finalTranscriptionDurations.count, 1)
        XCTAssertEqual(result.turns.map(\.text), ["gap speech 60"])
    }

    func testPlanBridgesNearbyGapsSoModelLoadsStayBounded() {
        let windows = [
            window(0, 0, 30, turns: speech("kept early", 4, 8)),
            window(2, 60, 90, turns: speech("inside bridged gap", 70, 74)),
            window(4, 120, 150, turns: speech("kept later", 125, 129)),
            window(6, 180, 210)
        ]
        let plan = RecordingReuse.plan(windows: windows, duration: 240)
        XCTAssertEqual(plan.gaps, [TimeGap(start: 30, end: 120), TimeGap(start: 150, end: 180),
                                   TimeGap(start: 210, end: 240)])
        XCTAssertEqual(plan.turns.map(\.text), ["kept early", "kept later"])
        XCTAssertEqual(plan.reusedSeconds, 90, accuracy: 0.001)
    }

    func testPlanIgnoresSubSecondGaps() {
        let plan = RecordingReuse.plan(windows: [window(0, 0, 30), window(1, 30.9, 60)], duration: 60.4)
        XCTAssertTrue(plan.gaps.isEmpty)
    }

    func testPlanWithNoWindowsCoversTheWholeRecording() {
        let plan = RecordingReuse.plan(windows: [], duration: 0.1)
        XCTAssertEqual(plan.gaps, [TimeGap(start: 0, end: 0.1)])
        XCTAssertTrue(plan.turns.isEmpty)
    }

    func testPlanFallsBackToWholeFileWhenMostIsMissing() {
        let plan = RecordingReuse.plan(windows: [window(0, 0, 30, turns: speech("early", 1, 3))], duration: 240)
        XCTAssertEqual(plan.gaps, [TimeGap(start: 0, end: 240)])
        XCTAssertTrue(plan.turns.isEmpty)
    }

    func testGapTurnsAreOffsetAndConfinedToTheirRange() {
        let raw = [AnalysisTurn(id: "x", text: "inside", start: 1, end: 3, speaker: nil),
                   AnalysisTurn(id: "y", text: "   ", start: 4, end: 5, speaker: nil),
                   AnalysisTurn(id: "z", text: "beyond", start: 40, end: 42, speaker: nil)]
        let turns = RecordingReuse.offsetGapTurns(raw, gap: TimeGap(start: 100, end: 130), index: 3)
        XCTAssertEqual(turns.map(\.text), ["inside"])
        XCTAssertEqual(turns.first?.id, "gap-3-0")
        XCTAssertEqual(turns.first?.start ?? 0, 101, accuracy: 0.001)
    }

    func testExtractAudioCopiesOnlyTheRequestedRange() throws {
        let (root, audio) = try makeSilentAudio(seconds: 60)
        defer { try? FileManager.default.removeItem(at: root) }
        let clip = try RecordingReuse.extractAudio(from: audio, start: 10, end: 25)
        let file = try AVAudioFile(forReading: clip)
        XCTAssertEqual(file.length, 15 * 8000)
        RecordingReuse.removeClip(clip)
        XCTAssertFalse(FileManager.default.fileExists(atPath: clip.path))
    }

    // MARK: Pre-analysis during recording

    private func finalRun(_ pipeline: MeetingAnalysisPipeline, id: UUID, audio: URL) async throws -> MeetingAnalysisCheckpoint {
        try await pipeline.run(meetingID: id, audio: audio, meetingDate: date, timezone: "UTC",
                               model: .fast) { _ in }
    }

    func testPreAnalysisIsReusedByFinalPassWhenTextsMatch() async throws {
        let (root, audio) = try makeSilentAudio(seconds: 30)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = ReuseBackend(root: root)
        let pipeline = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root, resourceGate: { true })
        let id = UUID()
        backend.setChunk(0, longTurns())
        try await prepare(pipeline, id: id, sequence: 0, chunkStart: 0, content: 0, end: 30)

        var analyzed: [Int] = []
        for _ in 0..<4 {
            analyzed.append(try await pipeline.preAnalyzeRecording(meetingID: id, meetingDate: date,
                                                                   timezone: "UTC", model: .fast))
        }
        XCTAssertEqual(analyzed, [1, 1, 1, 0], "Three closed chunks, one per call; the open chunk waits")
        XCTAssertEqual(backend.analysisCalls, 3)

        let result = try await finalRun(pipeline, id: id, audio: audio)

        XCTAssertEqual(result.analysis.count, 4)
        XCTAssertEqual(backend.analysisCalls, 4, "Only the open final chunk is analyzed after Stop")
        XCTAssertTrue(backend.finalTranscriptionDurations.isEmpty)
        let stored = root.appendingPathComponent("RecordingPreAnalysis-v1/\(id.uuidString).json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.path), "Pre-analysis is removed once used")
    }

    func testPreAnalysisIsRecomputedForChunksWhoseTextChanged() async throws {
        let (root, audio) = try makeSilentAudio(seconds: 30)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = ReuseBackend(root: root)
        let pipeline = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root, resourceGate: { true })
        let id = UUID()
        backend.setChunk(0, longTurns())
        try await prepare(pipeline, id: id, sequence: 0, chunkStart: 0, content: 0, end: 30)
        for _ in 0..<3 {
            _ = try await pipeline.preAnalyzeRecording(meetingID: id, meetingDate: date, timezone: "UTC", model: .fast)
        }
        XCTAssertEqual(backend.analysisCalls, 3)

        // Every turn is rewritten, so no stored chunk matches any more.
        backend.setChunk(0, longTurns(prefix: "alter"))
        try await prepare(pipeline, id: id, sequence: 0, chunkStart: 0, content: 0, end: 30)
        let result = try await finalRun(pipeline, id: id, audio: audio)

        XCTAssertEqual(result.analysis.count, 4)
        XCTAssertEqual(backend.analysisCalls, 3 + 4, "All four chunks must be recomputed")
    }

    func testPreAnalysisKeepsUnchangedChunksWhenOnlyOneTurnChanges() async throws {
        let (root, audio) = try makeSilentAudio(seconds: 30)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = ReuseBackend(root: root)
        let pipeline = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root, resourceGate: { true })
        let id = UUID()
        backend.setChunk(0, longTurns())
        try await prepare(pipeline, id: id, sequence: 0, chunkStart: 0, content: 0, end: 30)
        for _ in 0..<3 {
            _ = try await pipeline.preAnalyzeRecording(meetingID: id, meetingDate: date, timezone: "UTC", model: .fast)
        }

        var changed = longTurns()
        changed[0] = AnalysisTurn(id: "raw-0", text: "alter0 " + String(repeating: "x", count: 492),
                                  start: 0, end: 2, speaker: nil)
        backend.setChunk(0, changed)
        try await prepare(pipeline, id: id, sequence: 0, chunkStart: 0, content: 0, end: 30)
        _ = try await finalRun(pipeline, id: id, audio: audio)

        // Turn 0 sits only in chunk 0: it and the open chunk are recomputed; the
        // two middle chunks keep their pre-analysis.
        XCTAssertEqual(backend.analysisCalls, 3 + 2)
    }

    func testPreAnalysisRequiresResourcesInstalledModelAndExtraMemoryReserve() async throws {
        let (root, audio) = try makeSilentAudio(seconds: 30)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = audio
        let backend = ReuseBackend(root: root)
        let open = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root, resourceGate: { true })
        let closed = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root, resourceGate: { false })
        let id = UUID()
        backend.setChunk(0, longTurns())
        try await prepare(open, id: id, sequence: 0, chunkStart: 0, content: 0, end: 30)

        let blocked = try await closed.preAnalyzeRecording(meetingID: id, meetingDate: date, timezone: "UTC", model: .fast)
        XCTAssertEqual(blocked, 0)
        XCTAssertEqual(backend.sessionCount, 0, "No model may load while thermal/Low Power gates are closed")

        backend.setInstalled(false)
        let missing = try await open.preAnalyzeRecording(meetingID: id, meetingDate: date, timezone: "UTC", model: .fast)
        XCTAssertEqual(missing, 0)
        XCTAssertEqual(backend.sessionCount, 0)
        backend.setInstalled(true)

        backend.setMemoryFailure(true)
        let starved = try await open.preAnalyzeRecording(meetingID: id, meetingDate: date, timezone: "UTC", model: .fast)
        XCTAssertEqual(starved, 0, "A memory refusal is silent and never fails recording")
        backend.setMemoryFailure(false)

        let admitted = try await open.preAnalyzeRecording(meetingID: id, meetingDate: date, timezone: "UTC", model: .fast)
        XCTAssertEqual(admitted, 1)
        let reserve = try XCTUnwrap(backend.lastConfiguration?.reserveBytes)
        XCTAssertGreaterThanOrEqual(reserve, LocalModelConfiguration.compact.reserveBytes + 750_000_000)
    }

    func testPreAnalysisWaitsUntilAChunkCloses() async throws {
        let (root, audio) = try makeSilentAudio(seconds: 30)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = audio
        let backend = ReuseBackend(root: root)
        let pipeline = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root, resourceGate: { true })
        let id = UUID()
        backend.setChunk(0, [AnalysisTurn(id: "raw", text: String(repeating: "short ", count: 40), start: 0, end: 5, speaker: nil)])
        try await prepare(pipeline, id: id, sequence: 0, chunkStart: 0, content: 0, end: 30)

        let count = try await pipeline.preAnalyzeRecording(meetingID: id, meetingDate: date, timezone: "UTC", model: .fast)

        XCTAssertEqual(count, 0)
        XCTAssertEqual(backend.sessionCount, 0)
    }

    func testCancelledPreAnalysisStopsBeforeRunningTheModel() async throws {
        let (root, audio) = try makeSilentAudio(seconds: 30)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = audio
        let backend = ReuseBackend(root: root)
        let pipeline = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root, resourceGate: { true })
        let id = UUID()
        backend.setChunk(0, longTurns())
        try await prepare(pipeline, id: id, sequence: 0, chunkStart: 0, content: 0, end: 30)
        let date = self.date

        let task = Task { () -> Int in
            _ = withUnsafeCurrentTask { task in task?.cancel() }
            return try await pipeline.preAnalyzeRecording(meetingID: id, meetingDate: date, timezone: "UTC", model: .fast)
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled pre-analysis must throw")
        } catch is CancellationError {
        }
        XCTAssertEqual(backend.analysisCalls, 0)
    }

    func testDiscardingCheckpointRemovesPreAnalysis() async throws {
        let (root, audio) = try makeSilentAudio(seconds: 30)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = audio
        let backend = ReuseBackend(root: root)
        let pipeline = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root, resourceGate: { true })
        let id = UUID()
        backend.setChunk(0, longTurns())
        try await prepare(pipeline, id: id, sequence: 0, chunkStart: 0, content: 0, end: 30)
        _ = try await pipeline.preAnalyzeRecording(meetingID: id, meetingDate: date, timezone: "UTC", model: .fast)
        let stored = root.appendingPathComponent("RecordingPreAnalysis-v1/\(id.uuidString).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path))

        try await pipeline.discardCheckpoint(meetingID: id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.path))
        XCTAssertNil(TranscriptReuseRegistry.shared.summary(for: id))
    }

    func testChunkPlanIsIndependentOfSpeakerLabels() {
        let plain = longTurns()
        let labelled = plain.map { AnalysisTurn(id: $0.id, text: $0.text, start: $0.start, end: $0.end, speaker: "Speaker 2") }
        XCTAssertEqual(MeetingAnalysisPipeline.analysisChunks(plain).map { $0.map(\.id) },
                       MeetingAnalysisPipeline.analysisChunks(labelled).map { $0.map(\.id) })
    }
}

private final class ReuseBackend: MeetingAnalysisBackend, @unchecked Sendable {
    private let root: URL
    private let lock = NSLock()
    private var chunkTurns: [Int: [AnalysisTurn]] = [:]
    private var durations: [Double] = []
    private var analyses = 0
    private var sessions = 0
    private var configurations: [LocalModelConfiguration] = []
    private var installed = true
    private var memoryFailure = false

    init(root: URL) { self.root = root }

    private func synchronized<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }

    func setChunk(_ sequence: Int, _ turns: [AnalysisTurn]) { synchronized { chunkTurns[sequence] = turns } }
    func setInstalled(_ value: Bool) { synchronized { installed = value } }
    func setMemoryFailure(_ value: Bool) { synchronized { memoryFailure = value } }
    func recordAnalysis() { synchronized { analyses += 1 } }

    var finalTranscriptionDurations: [Double] { synchronized { durations } }
    var analysisCalls: Int { synchronized { analyses } }
    var sessionCount: Int { synchronized { sessions } }
    var lastConfiguration: LocalModelConfiguration? { synchronized { configurations.last } }

    func verifiedFolder(_ profile: ModelProfile) async throws -> URL { root }

    func isInstalled(_ profile: ModelProfile) async -> Bool { synchronized { installed } }

    func transcribe(audio: URL, folder: URL, languageCode: String?) async throws -> [AnalysisTurn] {
        let name = audio.lastPathComponent
        if name.hasPrefix("chunk-") {
            let digits = String(name.dropFirst("chunk-".count).prefix { $0.isNumber })
            let sequence = Int(digits) ?? -1
            return synchronized { chunkTurns[sequence] ?? [] }
        }
        let file = try AVAudioFile(forReading: audio)
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        synchronized { durations.append(seconds) }
        return [AnalysisTurn(id: "t1", text: "gap speech \(Int(seconds.rounded()))",
                             start: 1, end: max(2, seconds - 1), speaker: nil)]
    }

    func diarize(audio: URL, folder: URL) async throws -> [SpeakerSpan] { [] }

    func makeSession(folder: URL, configuration: LocalModelConfiguration) throws -> any MeetingAnalysisSession {
        let fail = synchronized { () -> Bool in
            if memoryFailure { return true }
            sessions += 1
            configurations.append(configuration)
            return false
        }
        if fail { throw OfflineError.memoryBudget(requiredEstimate: 4_000_000_000, budget: 1_000_000_000) }
        return ReuseSession(backend: self)
    }
}

private struct ReuseSession: MeetingAnalysisSession {
    let backend: ReuseBackend
    var inputTokenLimit: Int { 100_000 }
    func inputTokenCount(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?) throws -> Int { 10 }
    func analyze(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?) throws -> LocalAnalysisResult {
        backend.recordAnalysis()
        guard let first = turns.first else { throw OfflineError.unavailable("Empty chunk") }
        return LocalAnalysisResult(
            discussion: [SupportedPoint(text: "Point about \(first.id)",
                                        evidence: [SourceEvidence(turnID: first.id, quote: first.text)])],
            decisions: [], tasks: [])
    }
}
