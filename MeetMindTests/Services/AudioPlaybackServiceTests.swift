//
//  AudioPlaybackServiceTests.swift
//  MeetMindTests
//
//  Comprehensive test suite verifying AudioPlaybackServiceProtocol contract,
//  state machine transitions, variable rate playback, boundary seek clamping,
//  periodic time observers, error typing, and concurrency safety.
//

import XCTest
import Foundation
@testable import MeetMind

final class AudioPlaybackServiceTests: XCTestCase {
    
    private var service: MockAudioPlaybackService!
    private var testAudioURL: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        service = MockAudioPlaybackService(duration: 120.0)
        let tempDir = FileManager.default.temporaryDirectory
        testAudioURL = tempDir.appendingPathComponent("test_playback_\(UUID().uuidString).m4a")
    }
    
    override func tearDown() async throws {
        service.stop()
        service = nil
        testAudioURL = nil
        try await super.tearDown()
    }
    
    // MARK: - Tier 1: Feature Coverage (Feature 4, 43, 46, 47: Audio Playback)
    
    /// Tier 1: Feature 4 - Validates initial playback state and properties.
    func test_tier1_feature4_initialPlaybackStateDefaults() throws {
        let player: any AudioPlaybackServiceProtocol = service
        XCTAssertEqual(player.state, .idle)
        XCTAssertEqual(player.currentTime, 0.0)
        XCTAssertEqual(player.duration, 120.0)
        XCTAssertEqual(player.playbackRate, 1.0)
        XCTAssertFalse(player.isPlaying)
    }
    
    /// Tier 1: Feature 4 - Validates loadAudio prepares player and resets playhead.
    func test_tier1_feature4_loadAudioPreparesPlayer() throws {
        let player: any AudioPlaybackServiceProtocol = service
        service.currentTime = 45.0
        try player.loadAudio(url: testAudioURL)
        
        XCTAssertEqual(player.state, .idle)
        XCTAssertEqual(player.currentTime, 0.0)
    }
    
    /// Tier 1: Feature 4 - Validates play transitions state to .playing and isPlaying is true.
    func test_tier1_feature4_playTransitionsToPlaying() throws {
        let player: any AudioPlaybackServiceProtocol = service
        try player.play()
        
        XCTAssertEqual(player.state, .playing)
        XCTAssertTrue(player.isPlaying)
    }
    
    /// Tier 1: Feature 4 - Validates pause transitions state to .paused and isPlaying is false.
    func test_tier1_feature4_pauseTransitionsToPaused() throws {
        let player: any AudioPlaybackServiceProtocol = service
        try player.play()
        XCTAssertTrue(player.isPlaying)
        
        player.pause()
        XCTAssertEqual(player.state, .paused)
        XCTAssertFalse(player.isPlaying)
    }
    
    /// Tier 1: Feature 4 - Validates stop transitions state to .stopped and resets currentTime to 0.
    func test_tier1_feature4_stopResetsPlayheadToZero() throws {
        let player: any AudioPlaybackServiceProtocol = service
        try player.play()
        service.currentTime = 55.0
        
        player.stop()
        XCTAssertEqual(player.state, .stopped)
        XCTAssertEqual(player.currentTime, 0.0)
        XCTAssertFalse(player.isPlaying)
    }
    
    /// Tier 1: Feature 43 - Validates seek directly updates playhead to valid timecode.
    func test_tier1_feature43_seekDirectlyUpdatesCurrentTime() throws {
        let player: any AudioPlaybackServiceProtocol = service
        player.seek(to: 42.5)
        XCTAssertEqual(player.currentTime, 42.5)
        
        player.seek(to: 110.0)
        XCTAssertEqual(player.currentTime, 110.0)
    }
    
    /// Tier 1: Feature 46 - Validates adding time observer and receiving notifications.
    func test_tier1_feature46_addTimeObserverReceivesUpdates() throws {
        let player: any AudioPlaybackServiceProtocol = service
        var notifiedTime: TimeInterval = -1.0
        
        let observerID = player.addTimeObserver(interval: 0.1) { time in
            notifiedTime = time
        }
        
        XCTAssertNotNil(observerID)
        player.seek(to: 33.3)
        XCTAssertEqual(notifiedTime, 33.3)
    }
    
    /// Tier 1: Feature 46 - Validates removing time observer ceases notifications.
    func test_tier1_feature46_removeTimeObserverStopsUpdates() throws {
        let player: any AudioPlaybackServiceProtocol = service
        var callCount = 0
        
        let observerID = player.addTimeObserver(interval: 0.1) { _ in
            callCount += 1
        }
        
        player.seek(to: 10.0)
        XCTAssertEqual(callCount, 1)
        
        player.removeTimeObserver(id: observerID)
        player.seek(to: 20.0)
        XCTAssertEqual(callCount, 1) // unchanged
    }
    
    /// Tier 1: Feature 47 - Validates variable playback rate update.
    func test_tier1_feature47_variablePlaybackRateUpdates() throws {
        var player: any AudioPlaybackServiceProtocol = service
        let supportedRates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]
        
        for rate in supportedRates {
            player.playbackRate = rate
            XCTAssertEqual(player.playbackRate, rate)
        }
    }
    
    /// Tier 1: Feature 8 - Validates Clean Architecture dependency injection via protocol.
    func test_tier1_feature8_cleanArchitecturePlaybackInjection() throws {
        final class AudioPlaybackConsumer {
            let player: any AudioPlaybackServiceProtocol
            init(player: any AudioPlaybackServiceProtocol) {
                self.player = player
            }
            func executeJumpTo(offset: TimeInterval) {
                player.seek(to: offset)
            }
        }
        
        let consumer = AudioPlaybackConsumer(player: service)
        consumer.executeJumpTo(offset: 88.0)
        XCTAssertEqual(service.currentTime, 88.0)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Clamping, Errors, Simulation)
    
    /// Tier 2: Feature 43 - Validates seeking negative timecode clamps to 0.0.
    func test_tier2_feature43_seekNegativeClampsToZero() throws {
        let player: any AudioPlaybackServiceProtocol = service
        player.seek(to: -50.0)
        XCTAssertEqual(player.currentTime, 0.0)
        
        player.seek(to: -0.001)
        XCTAssertEqual(player.currentTime, 0.0)
    }
    
    /// Tier 2: Feature 43 - Validates seeking past duration clamps to total duration.
    func test_tier2_feature43_seekBeyondDurationClampsToMax() throws {
        let player: any AudioPlaybackServiceProtocol = service
        player.seek(to: 9999.0)
        XCTAssertEqual(player.currentTime, 120.0)
        
        player.seek(to: 120.001)
        XCTAssertEqual(player.currentTime, 120.0)
    }
    
    /// Tier 2: Feature 43 - Validates seeking exactly at 0 and exactly at duration boundary.
    func test_tier2_feature43_seekExactBoundaries() throws {
        let player: any AudioPlaybackServiceProtocol = service
        player.seek(to: 0.0)
        XCTAssertEqual(player.currentTime, 0.0)
        
        player.seek(to: 120.0)
        XCTAssertEqual(player.currentTime, 120.0)
    }
    
    /// Tier 2: Feature 4 - Validates fileNotFound error injection and description.
    func test_tier2_feature4_fileNotFoundErrorInjection() throws {
        let missingURL = URL(fileURLWithPath: "/nonexistent/meeting.m4a")
        service.shouldThrowError = .fileNotFound(missingURL)
        
        XCTAssertThrowsError(try service.loadAudio(url: missingURL)) { error in
            guard let playbackError = error as? AudioPlaybackError else {
                return XCTFail("Expected AudioPlaybackError")
            }
            XCTAssertEqual(playbackError, .fileNotFound(missingURL))
            XCTAssertTrue(playbackError.errorDescription?.contains("Audio file not found") == true)
        }
    }
    
    /// Tier 2: Feature 4 - Validates playerInitializationFailed error typing and description.
    func test_tier2_feature4_playerInitializationFailedError() throws {
        let error = AudioPlaybackError.playerInitializationFailed("Corrupted codec header")
        XCTAssertEqual(error.errorDescription, "Failed to initialize AVAudioPlayer: Corrupted codec header")
    }
    
    /// Tier 2: Feature 4 - Validates invalidState error typing and description.
    func test_tier2_feature4_invalidStateError() throws {
        let error = AudioPlaybackError.invalidState("Cannot play while loading")
        XCTAssertEqual(error.errorDescription, "Invalid playback state operation: Cannot play while loading")
    }
    
    /// Tier 2: Feature 4 - Validates seekFailed error typing and description.
    func test_tier2_feature4_seekFailedError() throws {
        let error = AudioPlaybackError.seekFailed("Hardware decoder stalled")
        XCTAssertEqual(error.errorDescription, "Seek operation failed: Hardware decoder stalled")
    }
    
    /// Tier 2: Feature 4 - Validates throwing on play when configured.
    func test_tier2_feature4_throwOnPlay() throws {
        service.shouldThrowError = .invalidState("Audio session inactive")
        XCTAssertThrowsError(try service.play()) { error in
            XCTAssertEqual(error as? AudioPlaybackError, .invalidState("Audio session inactive"))
        }
    }
    
    /// Tier 2: Feature 4 - Validates playback simulation advances currentTime.
    func test_tier2_feature4_playbackSimulationAdvancesTime() async throws {
        service.playbackRate = 2.0
        try service.play()
        
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertGreaterThan(service.currentTime, 0.0)
        service.pause()
    }
    
    /// Tier 2: Feature 4 - Validates multiple observers receiving simultaneous seek events.
    func test_tier2_feature4_multipleObserversSimultaneousUpdates() throws {
        var val1 = 0.0
        var val2 = 0.0
        var val3 = 0.0
        
        let id1 = service.addTimeObserver(interval: 0.1) { val1 = $0 }
        let id2 = service.addTimeObserver(interval: 0.1) { val2 = $0 }
        let id3 = service.addTimeObserver(interval: 0.1) { val3 = $0 }
        
        service.seek(to: 50.0)
        XCTAssertEqual(val1, 50.0)
        XCTAssertEqual(val2, 50.0)
        XCTAssertEqual(val3, 50.0)
        
        service.removeTimeObserver(id: id1)
        service.removeTimeObserver(id: id2)
        service.removeTimeObserver(id: id3)
    }
    
    // MARK: - Tier 3: Concurrency, Thread Safety & State Machine
    
    /// Tier 3: Pairwise - Verifies concurrent thread-safe seeking and observer removal.
    func test_tier3_concurrentThreadSafety() async throws {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    let offset = Double(i * 5)
                    self.service.seek(to: offset)
                    _ = self.service.state
                    _ = self.service.currentTime
                    _ = self.service.isPlaying
                }
            }
        }
        
        XCTAssertGreaterThanOrEqual(service.currentTime, 0.0)
        XCTAssertLessThanOrEqual(service.currentTime, 120.0)
    }
    
    /// Tier 3: Pairwise - Verifies PlaybackState enum raw values and Codable conformance.
    func test_tier3_playbackStateCodableConformance() throws {
        let states: [PlaybackState] = [.idle, .loading, .playing, .paused, .stopped, .completed]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for state in states {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(PlaybackState.self, from: data)
            XCTAssertEqual(decoded, state)
            XCTAssertEqual(decoded.rawValue, state.rawValue)
        }
    }
    
    /// Tier 1: Feature 4 - Validates seek updates playhead when playing.
    func test_tier1_feature4_seekUpdatesPlayheadWhenPlaying() throws {
        try service.play()
        XCTAssertTrue(service.isPlaying)
        service.seek(to: 45.0)
        XCTAssertEqual(service.currentTime, 45.0)
        XCTAssertTrue(service.isPlaying)
    }
    
    /// Tier 1: Feature 4 - Validates seek updates playhead when paused.
    func test_tier1_feature4_seekUpdatesPlayheadWhenPaused() throws {
        try service.play()
        service.pause()
        XCTAssertFalse(service.isPlaying)
        service.seek(to: 60.0)
        XCTAssertEqual(service.currentTime, 60.0)
        XCTAssertEqual(service.state, .paused)
    }
    
    /// Tier 1: Feature 4 - Validates playbackRate persists across play and pause.
    func test_tier1_feature4_playbackRatePersistsAcrossPlayPause() throws {
        service.playbackRate = 1.5
        try service.play()
        XCTAssertEqual(service.playbackRate, 1.5)
        service.pause()
        XCTAssertEqual(service.playbackRate, 1.5)
    }
    
    /// Tier 2: Feature 4 - Validates play called while already playing stays playing.
    func test_tier2_feature4_playWhileAlreadyPlayingDoesNotCrash() throws {
        try service.play()
        XCTAssertEqual(service.state, .playing)
        try service.play()
        XCTAssertEqual(service.state, .playing)
    }
    
    /// Tier 2: Feature 4 - Validates pause called while already paused stays paused.
    func test_tier2_feature4_pauseWhileAlreadyPausedDoesNotCrash() throws {
        try service.play()
        service.pause()
        XCTAssertEqual(service.state, .paused)
        service.pause()
        XCTAssertEqual(service.state, .paused)
    }
    
    /// Tier 2: Feature 4 - Validates stop called while already stopped resets time to 0.
    func test_tier2_feature4_stopWhileAlreadyStoppedDoesNotCrash() throws {
        service.stop()
        XCTAssertEqual(service.state, .stopped)
        XCTAssertEqual(service.currentTime, 0.0)
        service.stop()
        XCTAssertEqual(service.state, .stopped)
    }
    
    /// Tier 2: Feature 47 - Validates custom playback rate assignment and clamping [0.5, 2.0].
    func test_tier2_feature47_customPlaybackRateAssignment() throws {
        service.playbackRate = 0.5
        XCTAssertEqual(service.playbackRate, 0.5)
        service.playbackRate = 3.0
        XCTAssertEqual(service.playbackRate, 2.0)
    }
    
    /// Tier 2: Feature 47 - Validates NaN and infinite values in playbackRate are guarded to finite valid rate.
    func test_tier2_feature47_playbackRateNaNGuarded() throws {
        service.playbackRate = Float.nan
        XCTAssertTrue(service.playbackRate.isFinite)
        XCTAssertEqual(service.playbackRate, 1.0)
        
        service.playbackRate = Float.infinity
        XCTAssertTrue(service.playbackRate.isFinite)
        XCTAssertEqual(service.playbackRate, 1.0)
        
        service.playbackRate = -Float.infinity
        XCTAssertTrue(service.playbackRate.isFinite)
        XCTAssertEqual(service.playbackRate, 1.0)
    }
    
    /// Tier 3: Concurrency - Validates MockAudioPlaybackService recursive lock prevents deadlocks during simulation.
    func test_tier3_mockPlaybackServiceRecursiveLockSafety() async throws {
        try service.play()
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<30 {
                group.addTask {
                    _ = self.service.playbackRate
                    self.service.playbackRate = Float(1.0 + Double(i % 5) * 0.25)
                    _ = self.service.state
                    _ = self.service.currentTime
                    _ = self.service.duration
                    self.service.seek(to: Double(i))
                    _ = self.service.isPlaying
                }
            }
        }
        
        service.pause()
        service.stop()
        XCTAssertEqual(service.state, .stopped)
    }
}
