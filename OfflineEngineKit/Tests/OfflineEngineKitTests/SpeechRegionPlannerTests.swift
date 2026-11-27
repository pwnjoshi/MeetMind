import XCTest
@testable import OfflineEngineKit

final class SpeechRegionPlannerTests: XCTestCase {
    private let frame = 0.05
    private let quiet: Float = 0.0005
    private let loud: Float = 0.1

    /// Energies for `total` seconds of silence with loud speech at the given `(start, end)` seconds.
    private func energies(total: Double, speech: [(Double, Double)]) -> [Float] {
        var result = [Float](repeating: quiet, count: Int((total / frame).rounded()))
        for (start, end) in speech {
            let from = Int((start / frame).rounded())
            let to = min(result.count, Int((end / frame).rounded()))
            if from < to { for index in from..<to { result[index] = loud } }
        }
        return result
    }

    func testMissingIntervalsUseCoverageAndIgnoreShortPauses() {
        let region = SpeechRegion(start: 0, end: 25)
        let covered = [SpeechRegion(start: 14, end: 16), SpeechRegion(start: 1, end: 5),
                       SpeechRegion(start: 4, end: 7), SpeechRegion(start: 17, end: 19)]
        XCTAssertEqual(SpeechRegionPlanner.missingIntervals(in: region, covered: covered),
                       [SpeechRegion(start: 7, end: 14), SpeechRegion(start: 19, end: 25)])
        XCTAssertTrue(SpeechRegionPlanner.missingIntervals(in: region, covered: []).isEmpty)
    }

    func testFrameEnergiesIsRMSWithShortLastFrame() {
        let samples = [Float](repeating: 0.5, count: 2_500)
        let result = SpeechRegionPlanner.frameEnergies(samples, frameLength: 1_000)
        XCTAssertEqual(result.count, 3)
        for value in result { XCTAssertEqual(value, 0.5, accuracy: 0.0001) }
        XCTAssertTrue(SpeechRegionPlanner.frameEnergies([], frameLength: 1_000).isEmpty)
    }

    func testSilenceYieldsNoRegions() {
        let flat = [Float](repeating: 0.001, count: 400)
        XCTAssertTrue(SpeechRegionPlanner.plan(energies: flat).isEmpty)
        XCTAssertTrue(SpeechRegionPlanner.plan(energies: []).isEmpty)
    }

    func testShortPauseMergesAndLongPauseSplits() {
        let merged = SpeechRegionPlanner.plan(energies: energies(total: 9, speech: [(0, 3), (3.5, 8)]))
        XCTAssertEqual(merged.count, 1)
        let split = SpeechRegionPlanner.plan(energies: energies(total: 8, speech: [(0, 3), (4, 8)]))
        XCTAssertEqual(split.count, 2)
        XCTAssertEqual(split[0].start, 0, accuracy: 0.06)
        XCTAssertEqual(split[0].end, 3.2, accuracy: 0.06)
        XCTAssertEqual(split[1].start, 3.8, accuracy: 0.06)
        XCTAssertEqual(split[1].end, 8, accuracy: 0.06)
    }

    func testClickIsDropped() {
        let regions = SpeechRegionPlanner.plan(energies: energies(total: 12, speech: [(1, 1.1), (6, 10)]))
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].start, 5.8, accuracy: 0.06)
    }

    func testShortRegionJoinsNeighbourOnlyWithinSmallGap() {
        let joined = SpeechRegionPlanner.plan(energies: energies(total: 10, speech: [(0, 1), (2, 6)]))
        XCTAssertEqual(joined.count, 1)
        XCTAssertEqual(joined[0].end, 6, accuracy: 0.25)
        let apart = SpeechRegionPlanner.plan(energies: energies(total: 10, speech: [(0, 1), (2.5, 6.5)]))
        XCTAssertEqual(apart.count, 2)
    }

    func testMergeShortRespectsMaximumLength() {
        let regions = [SpeechRegion(start: 0, end: 24), SpeechRegion(start: 24.5, end: 25.5)]
        let result = SpeechRegionPlanner.mergeShort(regions, shortRegion: 2, maxGap: 1.2, maxRegion: 25)
        XCTAssertEqual(result, regions)
    }

    func testLongRegionSplitsAtQuietestPoint() {
        var values = [Float](repeating: loud, count: 800)
        values[400] = 0.02
        values[401] = 0.02
        let regions = SpeechRegionPlanner.plan(energies: values)
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0].end, 20.0, accuracy: 0.2)
        XCTAssertEqual(regions[0].end, regions[1].start, accuracy: 0.0001)
        XCTAssertEqual(regions[1].end, 40.0, accuracy: 0.0001)
    }

    func testContinuousSpeechIsCappedAndContiguous() {
        let regions = SpeechRegionPlanner.plan(energies: [Float](repeating: loud, count: 1_200))
        XCTAssertGreaterThanOrEqual(regions.count, 3)
        for region in regions { XCTAssertLessThanOrEqual(region.duration, 25.0001) }
        for pair in zip(regions, regions.dropFirst()) { XCTAssertEqual(pair.0.end, pair.1.start, accuracy: 0.0001) }
        XCTAssertEqual(regions.first?.start ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(regions.last?.end ?? -1, 60, accuracy: 0.0001)
    }

    func testPaddingNeverOverlapsNeighbours() {
        let regions = SpeechRegionPlanner.pad([SpeechRegion(start: 1, end: 2), SpeechRegion(start: 2.1, end: 3)],
                                              by: 0.2, duration: 3.05)
        XCTAssertEqual(regions[0].end, 2.05, accuracy: 0.0001)
        XCTAssertEqual(regions[1].start, 2.05, accuracy: 0.0001)
        XCTAssertEqual(regions[1].end, 3.05, accuracy: 0.0001)
        XCTAssertEqual(regions[0].start, 0.8, accuracy: 0.0001)
    }

    func testQuietestTimeIsNilForEmptyRange() {
        XCTAssertNil(SpeechRegionPlanner.quietestTime(energies: [1, 2, 3], frameSeconds: 0.05, from: 5, to: 6))
        XCTAssertNil(SpeechRegionPlanner.quietestTime(energies: [], frameSeconds: 0.05, from: 0, to: 1))
    }

    func testShiftedClampsToRegionThenOffsets() {
        let inside = SpeechRegionPlanner.shifted(start: 1, end: 2, by: 10, limit: 5)
        XCTAssertEqual(inside.start, 11, accuracy: 0.0001)
        XCTAssertEqual(inside.end, 12, accuracy: 0.0001)
        let past = SpeechRegionPlanner.shifted(start: 4, end: 9, by: 10, limit: 5)
        XCTAssertEqual(past.start, 14, accuracy: 0.0001)
        XCTAssertEqual(past.end, 15, accuracy: 0.0001)
        let negative = SpeechRegionPlanner.shifted(start: -1, end: -0.5, by: 3, limit: 5)
        XCTAssertEqual(negative.start, 3, accuracy: 0.0001)
        XCTAssertEqual(negative.end, 3, accuracy: 0.0001)
    }
}
