import XCTest
import AVFoundation
@testable import OfflineEngineKit

final class MeetingCheckpointRecoveryTests: XCTestCase {
    private func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audio = root.appendingPathComponent("synthetic.caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600))
        buffer.frameLength = 1600
        buffer.floatChannelData?[0].update(repeating: 0, count: 1600)
        let file = try AVAudioFile(forWriting: audio, settings: format.settings)
        try file.write(from: buffer)
        return (root, audio)
    }

    func testSpeakerFailureContinuesWithTranscriptAndMinutes() async throws {
        let (root, audio) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = CheckpointTestBackend(root: root, failSpeakers: true)
        let id = UUID(), date = Date(timeIntervalSince1970: 1700000000)
        let pipeline = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root)
        let result = try await pipeline.run(meetingID: id, audio: audio, meetingDate: date,
                                            timezone: "Asia/Kolkata") { _ in }
        XCTAssertEqual(result.stage, .completed)
        XCTAssertEqual(backend.counts.0, 1)
        XCTAssertEqual(backend.counts.1, 1)
        XCTAssertFalse(result.analysis.isEmpty)
        let warning = await pipeline.lastSpeakerWarning
        XCTAssertTrue(warning?.contains("unnamed speakers") == true)
        XCTAssertEqual(backend.contextTokens, 2048)
    }

    func testAnalysisFailureResumesAtLastSavedChunkAndCompletedRunReusesResult() async throws {
        let (root, audio) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = CheckpointTestBackend(root: root, failAnalysisCall: 2)
        let id = UUID(), date = Date(timeIntervalSince1970: 1700000000)
        let first = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root)
        do {
            _ = try await first.run(meetingID: id, audio: audio, meetingDate: date, timezone: "UTC") { _ in }
            XCTFail("Injected interruption must surface")
        } catch { }
        let resumed = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root)
        let result = try await resumed.run(meetingID: id, audio: audio, meetingDate: date, timezone: "UTC") { _ in }
        let callsAfterResume = backend.counts.2
        // One injected failure is retried; every fitted chunk is otherwise analyzed once.
        XCTAssertEqual(result.analysis.count, callsAfterResume - 1)
        XCTAssertEqual(backend.counts.0, 1)
        XCTAssertEqual(backend.counts.1, 1)
        _ = try await resumed.run(meetingID: id, audio: audio, meetingDate: date, timezone: "UTC") { _ in }
        XCTAssertEqual(backend.counts.2, callsAfterResume)
    }

    func testReviewedTranscriptFeedsMinutesAndInvalidatesStaleAnalysis() async throws {
        let (root, audio) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = CheckpointTestBackend(root: root)
        let pipeline = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root)
        let meetingID = UUID()
        let date = Date(timeIntervalSince1970: 1700000000)

        for text in ["Estimate due Monday.", "Estimate due Friday."] {
            let turns = [AnalysisTurn(id: "reviewed-1", text: text, start: 0, end: 0.1, speaker: "Speaker 1")]
            let result = try await pipeline.run(meetingID: meetingID, audio: audio, meetingDate: date,
                                                timezone: "UTC", reviewedTurns: turns) { _ in }
            XCTAssertEqual(result.stage, .completed)
            XCTAssertEqual(result.analysis.first?.discussion.first?.evidence.first?.quote, text)
        }
        XCTAssertEqual(backend.counts.0, 0)
        XCTAssertEqual(backend.counts.1, 0)
        XCTAssertEqual(backend.counts.2, 2)
    }

    func testChangedSourceInvalidatesCheckpointAndExplicitDiscardRemovesIt() async throws {
        let (root, audio) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = CheckpointTestBackend(root: root)
        let pipeline = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root)
        let id = UUID(), date = Date(timeIntervalSince1970: 1700000000)
        _ = try await pipeline.run(meetingID: id, audio: audio, meetingDate: date, timezone: "UTC") { _ in }
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: audio.path)
        _ = try await pipeline.run(meetingID: id, audio: audio, meetingDate: date, timezone: "UTC") { _ in }
        XCTAssertEqual(backend.counts.0, 2)
        try await pipeline.discardCheckpoint(meetingID: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(id.uuidString + ".json").path))
    }
    func testFittedChunkPlanSurvivesInterruptedRunWithoutRepeatingSource() async throws {
        let (root, audio) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = CheckpointTestBackend(root: root, failAnalysisCall: 2, tokenBudget: 300)
        let id = UUID(), date = Date(timeIntervalSince1970: 1700000000)
        let first = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root)
        do {
            _ = try await first.run(meetingID: id, audio: audio, meetingDate: date, timezone: "UTC") { _ in }
            XCTFail("Injected interruption must surface")
        } catch { }
        let before = try JSONDecoder().decode(MeetingAnalysisCheckpoint.self,
            from: Data(contentsOf: root.appendingPathComponent(id.uuidString + ".json")))
        let plan = try XCTUnwrap(before.chunkTurnIDs)
        XCTAssertEqual(before.analyzedChunks, 1)
        let resumed = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root)
        let result = try await resumed.run(meetingID: id, audio: audio, meetingDate: date, timezone: "UTC") { _ in }
        XCTAssertEqual(result.chunkTurnIDs, plan)
        XCTAssertEqual(result.analysis.count, plan.count)
        XCTAssertEqual(backend.counts.0, 1)
        XCTAssertEqual(backend.counts.2, plan.count + 1)
        XCTAssertEqual(result.turns.map(\.text).joined(), backend.turns.map(\.text).joined())
    }

    func testFinalTranscriptionAndDiarizationAreSerialByDefault() async throws {
        let (root, audio) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = OverlapTestBackend(root: root)
        let pipeline = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root)

        _ = try await pipeline.run(meetingID: UUID(), audio: audio,
            meetingDate: Date(timeIntervalSince1970: 1_700_000_000), timezone: "UTC") { _ in }

        XCTAssertFalse(backend.didOverlap, "ASR and diarization must remain serial unless a qualified resource governor explicitly admits overlap.")
    }

}

private final class CheckpointTestBackend: MeetingAnalysisBackend, @unchecked Sendable {
    private let root: URL
    private let lock = NSLock()
    private var transcriptionCalls = 0, speakerCalls = 0, analysisCalls = 0
    private var latestContextTokens: UInt32?
    private var failSpeakers: Bool
    private let failAnalysisCall: Int?
    let tokenBudget: Int
    let turns = (0..<12).map {
        AnalysisTurn(id: "t\($0)", text: String(repeating: "a", count: 500), start: Double($0), end: Double($0 + 1), speaker: nil)
    }
    init(root: URL, failSpeakers: Bool = false, failAnalysisCall: Int? = nil, tokenBudget: Int = 1280) {
        self.root = root; self.failSpeakers = failSpeakers; self.failAnalysisCall = failAnalysisCall; self.tokenBudget = tokenBudget
    }
    private func synchronized<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }
    var contextTokens: UInt32? { synchronized { latestContextTokens } }
    var counts: (Int, Int, Int) { synchronized { (transcriptionCalls, speakerCalls, analysisCalls) } }
    func verifiedFolder(_ profile: ModelProfile) async throws -> URL { root }
    func transcribe(audio: URL, folder: URL, languageCode: String?) async throws -> [AnalysisTurn] {
        synchronized { transcriptionCalls += 1 }
        return turns
    }
    func diarize(audio: URL, folder: URL) async throws -> [SpeakerSpan] {
        let fail = synchronized {
            speakerCalls += 1
            let fail = failSpeakers; failSpeakers = false; return fail
        }
        if fail { throw OfflineError.unavailable("Injected diarization failure") }
        return []
    }
    func makeSession(folder: URL, configuration: LocalModelConfiguration) throws -> any MeetingAnalysisSession {
        synchronized { latestContextTokens = configuration.contextTokens }
        return CheckpointTestSession(backend: self)
    }
    func analyze(_ turns: [AnalysisTurn]) throws -> LocalAnalysisResult {
        let fail = synchronized { analysisCalls += 1; return analysisCalls == failAnalysisCall }
        if fail { throw CancellationError() }
        let first = try XCTUnwrap(turns.first)
        return LocalAnalysisResult(discussion: [SupportedPoint(text: "Synthetic supported point",
            evidence: [SourceEvidence(turnID: first.id, quote: first.text)])], decisions: [], tasks: [])
    }
}

private struct CheckpointTestSession: MeetingAnalysisSession {
    var inputTokenLimit: Int { backend.tokenBudget }
    func inputTokenCount(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?) throws -> Int { turns.reduce(10) { $0 + $1.text.utf8.count } }
    let backend: CheckpointTestBackend
    func analyze(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?) throws -> LocalAnalysisResult {
        try backend.analyze(turns)
    }
}

private final class OverlapTestBackend: MeetingAnalysisBackend, @unchecked Sendable {
    private let root: URL
    private let lock = NSLock()
    private var transcribing = false
    private var diarizing = false
    private var observedOverlap = false
    private let turn = AnalysisTurn(id: "t0", text: "Rahul will send the estimate tomorrow.", start: 0, end: 2, speaker: nil)

    init(root: URL) { self.root = root }

    var didOverlap: Bool {
        lock.lock(); defer { lock.unlock() }
        return observedOverlap
    }

    func verifiedFolder(_ profile: ModelProfile) async throws -> URL { root }

    func transcribe(audio: URL, folder: URL, languageCode: String?) async throws -> [AnalysisTurn] {
        beginTranscription(); defer { endTranscription() }
        try await Task.sleep(nanoseconds: 150_000_000)
        return [turn]
    }

    func diarize(audio: URL, folder: URL) async throws -> [SpeakerSpan] {
        beginDiarization(); defer { endDiarization() }
        try await Task.sleep(nanoseconds: 150_000_000)
        return [SpeakerSpan(speaker: "S0", start: 0, end: 2)]
    }

    func makeSession(folder: URL, configuration: LocalModelConfiguration) throws -> any MeetingAnalysisSession {
        OverlapTestSession(turn: turn)
    }

    private func beginTranscription() {
        lock.lock(); defer { lock.unlock() }
        transcribing = true
        observedOverlap = observedOverlap || diarizing
    }

    private func endTranscription() {
        lock.lock(); defer { lock.unlock() }
        transcribing = false
    }

    private func beginDiarization() {
        lock.lock(); defer { lock.unlock() }
        diarizing = true
        observedOverlap = observedOverlap || transcribing
    }

    private func endDiarization() {
        lock.lock(); defer { lock.unlock() }
        diarizing = false
    }
}

private struct OverlapTestSession: MeetingAnalysisSession {
    let turn: AnalysisTurn
    var inputTokenLimit: Int { 2_048 }
    func inputTokenCount(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?) throws -> Int { 20 }
    func analyze(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?) throws -> LocalAnalysisResult {
        LocalAnalysisResult(discussion: [SupportedPoint(text: "Estimate will be sent tomorrow.",
            evidence: [SourceEvidence(turnID: turn.id, quote: turn.text)])], decisions: [], tasks: [])
    }
}
