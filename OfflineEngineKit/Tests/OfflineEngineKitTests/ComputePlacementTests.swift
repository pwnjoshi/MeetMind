import XCTest
import AVFoundation
@testable import OfflineEngineKit

/// iOS rejects GPU work from a backgrounded iPhone app. These tests simulate that
/// rejection and check that minutes still come from the model, on the CPU.
final class ComputePlacementTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ComputeEnvironment.setGPUAvailable(true)
    }

    override func tearDown() {
        ComputeEnvironment.setGPUAvailable(true)
        super.tearDown()
    }

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

    func testPlacementFollowsForegroundState() {
        XCTAssertFalse(ComputeEnvironment.needsReload(.independent))
        ComputeEnvironment.setGPUAvailable(false)
        XCTAssertEqual(ComputeEnvironment.preferredPlacement, .cpu)
        XCTAssertTrue(ComputeEnvironment.needsReload(.gpu))
        XCTAssertFalse(ComputeEnvironment.needsReload(.cpu))
        ComputeEnvironment.setGPUAvailable(true)
        XCTAssertEqual(ComputeEnvironment.preferredPlacement, .gpu)
        XCTAssertTrue(ComputeEnvironment.needsReload(.cpu))
        XCTAssertFalse(ComputeEnvironment.needsReload(.gpu))
    }

    func testChunkInterruptedByBackgroundIsRedoneOnTheCPU() async throws {
        let (root, audio) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = PlacementTestBackend(root: root, onFirstAnalyze: { ComputeEnvironment.setGPUAvailable(false) })
        let pipeline = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root)
        let result = try await pipeline.run(meetingID: UUID(), audio: audio,
            meetingDate: Date(timeIntervalSince1970: 1_700_000_000), timezone: "UTC") { _ in }

        XCTAssertEqual(result.stage, .completed)
        XCTAssertEqual(backend.placements, [.gpu, .cpu], "The GPU model is freed and reloaded once on the CPU")
        let timings = await pipeline.lastStageTimings
        XCTAssertEqual(timings.backgroundRetries, 1)
        XCTAssertEqual(timings.cpuChunks, result.analysis.count)
        XCTAssertEqual(timings.modelLoads, 2)
        let fallback = await pipeline.lastAnalysisFallbackChunks
        XCTAssertEqual(fallback, 0, "The interrupted chunk keeps its model result instead of falling back to rules")
        XCTAssertTrue(result.analysis.allSatisfy { !$0.discussion.isEmpty })
    }

    func testReturningToForegroundReloadsOnTheGPU() async throws {
        let (root, audio) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        ComputeEnvironment.setGPUAvailable(false)
        let backend = PlacementTestBackend(root: root, onFirstAnalyze: { ComputeEnvironment.setGPUAvailable(true) })
        let pipeline = MeetingAnalysisPipeline(backend: backend, checkpointRoot: root)
        let result = try await pipeline.run(meetingID: UUID(), audio: audio,
            meetingDate: Date(timeIntervalSince1970: 1_700_000_000), timezone: "UTC") { _ in }

        XCTAssertGreaterThan(result.analysis.count, 1, "The fixture needs a second chunk after the switch")
        XCTAssertEqual(backend.placements, [.cpu, .gpu])
        let timings = await pipeline.lastStageTimings
        XCTAssertEqual(timings.cpuChunks, 1)
        XCTAssertEqual(timings.backgroundRetries, 0)
    }

    func testStageTimingsLogLineHasNoMeetingContent() {
        var timings = AnalysisStageTimings()
        timings.transcriptionMs = 1200
        timings.chunkMs = [800, 1600]
        let line = timings.logDescription
        XCTAssertTrue(line.contains("transcribe_ms=1200"))
        XCTAssertTrue(line.contains("chunk_avg_ms=1200"))
        XCTAssertTrue(line.contains("chunk_max_ms=1600"))
    }
}

private final class PlacementTestBackend: MeetingAnalysisBackend, @unchecked Sendable {
    private let root: URL
    private let lock = NSLock()
    private var madePlacements: [ComputePlacement] = []
    private var onFirstAnalyze: (() -> Void)?
    let turns = (0..<12).map {
        AnalysisTurn(id: "t\($0)", text: String(repeating: "a", count: 500), start: Double($0), end: Double($0 + 1), speaker: nil)
    }

    init(root: URL, onFirstAnalyze: @escaping () -> Void) {
        self.root = root
        self.onFirstAnalyze = onFirstAnalyze
    }

    var placements: [ComputePlacement] { lock.lock(); defer { lock.unlock() }; return madePlacements }

    func verifiedFolder(_ profile: ModelProfile) async throws -> URL { root }
    func transcribe(audio: URL, folder: URL, languageCode: String?) async throws -> [AnalysisTurn] { turns }
    func diarize(audio: URL, folder: URL) async throws -> [SpeakerSpan] { [] }
    func makeSession(folder: URL, configuration: LocalModelConfiguration) throws -> any MeetingAnalysisSession {
        let placement = ComputeEnvironment.preferredPlacement
        lock.lock(); madePlacements.append(placement); lock.unlock()
        return PlacementTestSession(placement: placement, backend: self)
    }

    /// Runs the state change once, during the first analysis call, like an app that
    /// moves to the background (or returns) while a chunk is being decoded.
    func takeFirstAnalyzeHook() -> (() -> Void)? {
        lock.lock(); defer { lock.unlock() }
        let hook = onFirstAnalyze
        onFirstAnalyze = nil
        return hook
    }
}

private struct PlacementTestSession: MeetingAnalysisSession {
    let placement: ComputePlacement
    let backend: PlacementTestBackend
    var inputTokenLimit: Int { 1280 }

    func inputTokenCount(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?) throws -> Int {
        turns.reduce(10) { $0 + $1.text.utf8.count }
    }

    func analyze(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?) throws -> LocalAnalysisResult {
        backend.takeFirstAnalyzeHook()?()
        if placement == .gpu && !ComputeEnvironment.gpuAvailable {
            throw OfflineError.unavailable("Metal command buffer rejected in the background")
        }
        let first = try XCTUnwrap(turns.first)
        return LocalAnalysisResult(discussion: [SupportedPoint(text: "Synthetic supported point",
            evidence: [SourceEvidence(turnID: first.id, quote: first.text)])], decisions: [], tasks: [])
    }
}
