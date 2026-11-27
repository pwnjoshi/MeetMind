import XCTest
import AVFoundation
@testable import OfflineEngineKit

/// Synthetic 8-dimensional "voices". No model, audio or download is involved.
final class VoiceMatchingTests: XCTestCase {
    private func basis(_ index: Int, _ weight: Float = 1, _ others: [(Int, Float)] = []) -> [Float] {
        var vector = [Float](repeating: 0, count: 8)
        vector[index] = weight
        for (other, value) in others { vector[other] = value }
        return vector
    }

    private func profile(_ id: UUID, _ vector: [Float]) -> VoiceProfile {
        var profile = VoiceProfile(personID: id)
        profile.learn(vector)
        return profile
    }

    private func cluster(_ label: String, _ vector: [Float], seconds: Double = 30) -> VoiceCluster {
        VoiceCluster(label: label, embedding: vector, speechSeconds: seconds)
    }

    // MARK: Math

    func testCosineAndNormalizationGuardAgainstBadVectors() {
        XCTAssertEqual(try XCTUnwrap(SpeakerEmbeddingMath.cosine([1, 0], [2, 0])), 1, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(SpeakerEmbeddingMath.cosine([1, 0], [0, 3])), 0, accuracy: 1e-6)
        XCTAssertNil(SpeakerEmbeddingMath.cosine([1, 0], [1, 0, 0]))
        XCTAssertNil(SpeakerEmbeddingMath.cosine([0, 0], [1, 0]))
        XCTAssertNil(SpeakerEmbeddingMath.normalized([]))
        XCTAssertNil(SpeakerEmbeddingMath.normalized([1, .nan]))
        XCTAssertNil(SpeakerEmbeddingMath.normalized([0, 0, 0]))
        let unit = try? XCTUnwrap(SpeakerEmbeddingMath.normalized([3, 4]))
        XCTAssertEqual(unit?[0] ?? 0, 0.6, accuracy: 1e-6)
        XCTAssertEqual(unit?[1] ?? 0, 0.8, accuracy: 1e-6)
    }

    // MARK: Profiles

    func testProfileLearnsAndKeepsAUnitCentroid() {
        var profile = VoiceProfile(personID: UUID())
        XCTAssertTrue(profile.isEmpty)
        XCTAssertEqual(profile.learn(basis(0, 1, [(1, 0.2)])), .created)
        XCTAssertEqual(profile.learn(basis(0, 1, [(2, 0.2)])), .updated)
        XCTAssertEqual(profile.sampleCount, 2)
        let length = SpeakerEmbeddingMath.cosine(profile.centroid, profile.centroid)
        XCTAssertEqual(length ?? 0, 1, accuracy: 1e-5)
        XCTAssertEqual(profile.centroid.reduce(0) { $0 + $1 * $1 }, 1, accuracy: 1e-5)
    }

    func testProfileRejectsOutliersAndInvalidVectors() {
        var voice = profile(UUID(), basis(0))
        let before = voice
        // Orthogonal voice: similarity 0, well under the 0.4 limit.
        XCTAssertEqual(voice.learn(basis(1)), .rejectedOutlier)
        XCTAssertEqual(voice.learn([Float.nan, 0, 0, 0, 0, 0, 0, 0]), .rejectedInvalid)
        XCTAssertEqual(voice.learn([1, 0, 0]), .rejectedInvalid)
        XCTAssertEqual(voice, before)
        // Similarity 0.6 is above the limit and is learned.
        XCTAssertEqual(voice.learn(basis(0, 0.6, [(1, 0.8)])), .updated)
        XCTAssertEqual(voice.sampleCount, 2)
    }

    func testProfileKeepsAtMostFiveExemplarsAndCapsHistoryWeight() {
        var profile = VoiceProfile(personID: UUID())
        for step in 0..<9 {
            // Distinct but similar vectors so none is treated as a duplicate.
            profile.learn(basis(0, 1, [(1 + step % 7, 0.6)]))
        }
        XCTAssertEqual(profile.exemplars.count, VoiceProfile.maxExemplars)
        XCTAssertEqual(profile.sampleCount, 9)
        // History weight is capped, so a long-lived profile still moves toward a new, consistent sample.
        var old = VoiceProfile(personID: UUID())
        for _ in 0..<40 { old.learn(basis(0)) }
        let before = SpeakerEmbeddingMath.cosine(old.centroid, basis(0, 0.6, [(1, 0.8)])) ?? 0
        old.learn(basis(0, 0.6, [(1, 0.8)]))
        let after = SpeakerEmbeddingMath.cosine(old.centroid, basis(0, 0.6, [(1, 0.8)])) ?? 0
        XCTAssertGreaterThan(after - before, 0.02)
    }

    func testNearDuplicateSamplesReplaceTheirExemplar() {
        var profile = VoiceProfile(personID: UUID())
        profile.learn(basis(0))
        profile.learn(basis(0, 1, [(1, 0.01)]))
        XCTAssertEqual(profile.exemplars.count, 1)
    }

    func testProfileCodableRoundTrip() throws {
        let original = profile(UUID(), basis(2, 1, [(3, 0.3)]))
        let decoded = try JSONDecoder().decode(VoiceProfile.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    // MARK: Matching thresholds

    func testClearMatchIsNamedAutomatically() throws {
        let ana = UUID(), ben = UUID()
        let profiles = [profile(ana, basis(0)), profile(ben, basis(1))]
        let matches = VoiceMatcher.match(clusters: [cluster("S1", basis(0, 0.8, [(2, 0.6)]))], profiles: profiles)
        let match = try XCTUnwrap(matches.first)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(match.personID, ana)
        XCTAssertEqual(match.status, .auto)
        XCTAssertEqual(match.similarity, 0.8, accuracy: 1e-4)
        XCTAssertGreaterThanOrEqual(match.margin, 0.08)
    }

    func testSmallMarginOverRunnerUpOnlySuggests() throws {
        let ana = UUID(), ben = UUID()
        // Ben's voice sits close to Ana's, so a voice at 0.78 from Ana is 0.70 from Ben: margin 0.078.
        let profiles = [profile(ana, basis(0)), profile(ben, basis(0, 0.9, [(1, 0.43589)]))]
        let voice = basis(0, 0.78, [(2, 0.62580)])
        let match = try XCTUnwrap(VoiceMatcher.match(clusters: [cluster("S1", voice)], profiles: profiles).first)
        XCTAssertEqual(match.personID, ana)
        XCTAssertEqual(match.status, .suggested)
        XCTAssertLessThan(match.margin, 0.08)
    }

    func testMiddleSimilarityIsSuggestedAndLowSimilarityIsUnknown() throws {
        let ana = UUID()
        let profiles = [profile(ana, basis(0))]
        let likely = try XCTUnwrap(VoiceMatcher.match(
            clusters: [cluster("S1", basis(0, 0.62, [(1, 0.7846)]))], profiles: profiles).first)
        XCTAssertEqual(likely.status, .suggested)
        let unknown = VoiceMatcher.match(clusters: [cluster("S1", basis(0, 0.5, [(1, 0.866)]))], profiles: profiles)
        XCTAssertTrue(unknown.isEmpty)
    }

    func testVoicesWithUnderThreeSecondsAreNeverNamed() {
        let profiles = [profile(UUID(), basis(0))]
        XCTAssertTrue(VoiceMatcher.match(clusters: [cluster("S1", basis(0), seconds: 2.9)], profiles: profiles).isEmpty)
        XCTAssertEqual(VoiceMatcher.match(clusters: [cluster("S1", basis(0), seconds: 3)], profiles: profiles).count, 1)
    }

    func testThresholdsAreTunable() throws {
        let profiles = [profile(UUID(), basis(0))]
        let voice = cluster("S1", basis(0, 0.8, [(1, 0.6)]))
        let strict = VoiceMatchConfig(autoThreshold: 0.9)
        XCTAssertEqual(VoiceMatcher.match(clusters: [voice], profiles: profiles, config: strict).first?.status, .suggested)
    }

    func testEmptyInputsAndMismatchedDimensionsGiveNoMatches() {
        XCTAssertTrue(VoiceMatcher.match(clusters: [], profiles: [profile(UUID(), basis(0))]).isEmpty)
        XCTAssertTrue(VoiceMatcher.match(clusters: [cluster("S1", basis(0))], profiles: []).isEmpty)
        XCTAssertTrue(VoiceMatcher.match(clusters: [cluster("S1", [1, 0, 0])], profiles: [profile(UUID(), basis(0))]).isEmpty)
        XCTAssertTrue(VoiceMatcher.match(clusters: [cluster("S1", basis(0))], profiles: [VoiceProfile(personID: UUID())]).isEmpty)
    }

    // MARK: One-to-one assignment and attendees

    func testTwoVoicesCannotTakeTheSamePerson() throws {
        let ana = UUID()
        let profiles = [profile(ana, basis(0))]
        let strong = cluster("S1", basis(0, 0.9, [(1, 0.43589)]))
        let weaker = cluster("S2", basis(0, 0.75, [(2, 0.6614)]))
        let matches = VoiceMatcher.match(clusters: [weaker, strong], profiles: profiles)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.label, "S1")
    }

    func testAssignmentIsGloballyOptimalNotGreedy() throws {
        let ana = UUID(), ben = UUID()
        // Greedy would give S1 to Ana (0.80) and leave S2 with Ben (0.0). The best total pairs S1 with Ben.
        let profiles = [profile(ana, basis(0)), profile(ben, basis(1))]
        let s1 = cluster("S1", basis(0, 0.8, [(1, 0.6)]))
        let s2 = cluster("S2", basis(0, 0.75, [(2, 0.6614)]))
        let result = VoiceMatcher.match(clusters: [s1, s2], profiles: profiles)
        let byLabel = Dictionary(uniqueKeysWithValues: result.map { ($0.label, $0.personID) })
        // Ben is only 0.6 for S1 (a suggestion), Ana is 0.75 for S2. Total 1.35 beats S1->Ana alone at 0.80.
        XCTAssertEqual(byLabel["S1"], ben)
        XCTAssertEqual(byLabel["S2"], ana)
    }

    func testAttendeesWinAndOutsidersAreOnlySuggestedAboveTheAutoThreshold() throws {
        let attendee = UUID(), stranger = UUID()
        let profiles = [profile(attendee, basis(0)), profile(stranger, basis(1))]
        let room: Set<UUID> = [attendee]
        let first = cluster("S1", basis(0, 0.9, [(2, 0.43589)]))
        let second = cluster("S2", basis(1, 0.9, [(3, 0.43589)]))
        let matches = VoiceMatcher.match(clusters: [first, second], profiles: profiles, attendeeIDs: room)
        let byLabel = Dictionary(uniqueKeysWithValues: matches.map { ($0.label, $0) })
        XCTAssertEqual(byLabel["S1"]?.personID, attendee)
        XCTAssertEqual(byLabel["S1"]?.status, .auto)
        XCTAssertEqual(byLabel["S2"]?.personID, stranger)
        XCTAssertEqual(byLabel["S2"]?.status, .suggested, "A person outside the attendee list is never named automatically")
        // A weaker outsider (0.6) is not even suggested.
        let weak = cluster("S3", basis(1, 0.6, [(3, 0.8)]))
        XCTAssertTrue(VoiceMatcher.match(clusters: [weak], profiles: profiles, attendeeIDs: room).isEmpty)
    }

    func testHungarianMatchesBruteForceOnRandomMatrices() {
        var seed: UInt64 = 42
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) % 1000) / 1000
        }
        func best(_ weights: [[Double]], row: Int, used: Set<Int>) -> Double {
            guard row < weights.count else { return 0 }
            var top = best(weights, row: row + 1, used: used)
            for column in weights[row].indices where !used.contains(column) {
                top = max(top, weights[row][column] + best(weights, row: row + 1, used: used.union([column])))
            }
            return top
        }
        for trial in 0..<60 {
            let rows = 1 + trial % 5
            let columns = 1 + (trial / 5) % 5
            let weights = (0..<rows).map { _ in (0..<columns).map { _ in next() < 0.3 ? 0 : next() } }
            let chosen = VoiceMatcher.optimalAssignment(weights: weights)
            XCTAssertEqual(chosen.count, rows)
            var total = 0.0
            var columnsUsed = Set<Int>()
            for (row, column) in chosen.enumerated() {
                guard let column else { continue }
                XCTAssertTrue(columnsUsed.insert(column).inserted, "A column was assigned twice")
                total += weights[row][column]
            }
            XCTAssertEqual(total, best(weights, row: 0, used: []), accuracy: 1e-9, "trial \(trial)")
        }
    }

    func testClustersCombineEmbeddingsWithSpeechSeconds() {
        let spans = [SpeakerSpan(speaker: "S1", start: 0, end: 4), SpeakerSpan(speaker: "S1", start: 10, end: 12),
                     SpeakerSpan(speaker: "S2", start: 4, end: 5)]
        let clusters = VoiceMatcher.clusters(embeddings: ["S1": basis(0), "S2": basis(1), "S3": basis(2)], spans: spans)
        XCTAssertEqual(clusters.map(\.label), ["S1", "S2"])
        XCTAssertEqual(clusters.first?.speechSeconds ?? 0, 6, accuracy: 1e-9)
    }

    // MARK: Checkpoint

    func testCheckpointWithoutEmbeddingsStillDecodes() throws {
        let checkpoint = MeetingAnalysisCheckpoint(sourceSignature: "s", stage: .analysis, turns: [], speakers: [],
                                                   analysis: [], analyzedChunks: 0)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(checkpoint)) as? [String: Any])
        object.removeValue(forKey: "speakerEmbeddings")
        object.removeValue(forKey: "speakerEmbeddingModel")
        let decoded = try JSONDecoder().decode(MeetingAnalysisCheckpoint.self,
                                               from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.speakerEmbeddings)
        XCTAssertNil(decoded.speakerEmbeddingModel)
    }

    func testSpeakerStageStoresEmbeddingsOnlyForVoicesStillPresent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("synthetic.caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600))
        buffer.frameLength = 1600
        buffer.floatChannelData?[0].update(repeating: 0, count: 1600)
        try AVAudioFile(forWriting: audio, settings: format.settings).write(from: buffer)

        let pipeline = MeetingAnalysisPipeline(backend: EmbeddingBackend(root: root), checkpointRoot: root)
        let result = try await pipeline.run(meetingID: UUID(), audio: audio, meetingDate: Date(),
                                            timezone: "UTC", stopAfterSpeakers: true) { _ in }
        XCTAssertEqual(Set(result.speakerEmbeddings?.keys.map { $0 } ?? []), ["S1", "S2"])
        XCTAssertNotNil(result.speakerEmbeddingModel)
    }
}

private final class EmbeddingBackend: MeetingAnalysisBackend, @unchecked Sendable {
    let root: URL
    init(root: URL) { self.root = root }
    func verifiedFolder(_ profile: ModelProfile) async throws -> URL { root }
    func transcribe(audio: URL, folder: URL, languageCode: String?) async throws -> [AnalysisTurn] {
        [AnalysisTurn(id: "t1", text: "Hello team", start: 0, end: 10, speaker: nil),
         AnalysisTurn(id: "t2", text: "Thanks all", start: 10, end: 20, speaker: nil)]
    }
    func diarize(audio: URL, folder: URL) async throws -> [SpeakerSpan] { [] }
    func diarizeWithEmbeddings(audio: URL, folder: URL, expectedSpeakers: Int?) async throws -> SpeakerDiarizationOutput {
        SpeakerDiarizationOutput(
            spans: [SpeakerSpan(speaker: "S1", start: 0, end: 10), SpeakerSpan(speaker: "S2", start: 10, end: 20)],
            embeddings: ["S1": [1, 0], "S2": [0, 1], "S9": [1, 1]])
    }
    func makeSession(folder: URL, configuration: LocalModelConfiguration) throws -> any MeetingAnalysisSession {
        throw OfflineError.unavailable("Not used")
    }
}
