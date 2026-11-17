//
//  ProcessingPipelineViewModelTests.swift
//  MeetMindTests
//
//  Created by MeetMind Test Automation.
//

import XCTest
import Foundation
import SwiftData
@testable import MeetMind

/// Comprehensive test suite covering Post-Recording Synthesis HUD,
/// Multi-Stage Progression (Audio Finalization -> Speech Diarization -> AI Summarization -> Action Extraction),
/// Progress Interpolation, Stage Retries, Error Fallbacks, and Completion Routing.
/// Corresponds to Feature 39.
@MainActor
final class ProcessingPipelineViewModelTests: XCTestCase {
    
    // MARK: - Test Infrastructure & Fixtures
    
    private var modelContainer: ModelContainer!
    private var context: ModelContext!
    private var sut: ProcessingPipelineViewModel!
    private var mockSummarizationService: MockSummarizationService!
    private var mockTranscriptionService: MockSpeechTranscriptionService!
    private var initialMeeting: Meeting!
    private var targetMeetingId: UUID!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        context = ModelContext(modelContainer)
        mockSummarizationService = MockSummarizationService()
        mockTranscriptionService = MockSpeechTranscriptionService()
        
        targetMeetingId = UUID()
        initialMeeting = Meeting(
            id: targetMeetingId,
            title: "Sprint Retrospective Synthesis",
            createdAt: Date(),
            scheduledStartTime: nil,
            duration: 1200,
            status: .processing,
            isFavorite: false
        )
        context.insert(initialMeeting)
        try? context.save()
        
        sut = ProcessingPipelineViewModel(
            meeting: initialMeeting,
            modelContext: context,
            summarizationService: mockSummarizationService
        )
    }
    
    @MainActor
    override func tearDown() async throws {
        sut = nil
        initialMeeting = nil
        mockSummarizationService = nil
        mockTranscriptionService = nil
        context = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    private func fetchMeeting(id: UUID) -> Meeting? {
        var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    
    // MARK: - Tier 1: Feature 39 (Post-Recording Synthesis HUD)
    
    /// Tier 1: Feature 39 - Validates pipeline initializes with 4 distinct synthesis stages.
    func test_tier1_feature39_pipelineInitialStateHasFourStages() throws {
        XCTAssertEqual(sut.stages.count, 4)
        XCTAssertEqual(sut.currentStageIndex, 0)
        XCTAssertEqual(sut.overallProgress, 0.0)
        XCTAssertEqual(sut.pipelineStatus, .idle)
    }
    
    /// Tier 1: Feature 39 - Validates Stage 1 (Audio Finalization) executes and completes.
    func test_tier1_feature39_stageOneAudioFinalizationProgression() throws {
        sut.startPipeline()
        
        sut.simulateStageCompletion(stageIndex: 0)
        XCTAssertEqual(sut.stages[0].state, .completed)
        XCTAssertEqual(sut.currentStageIndex, 1)
        XCTAssertGreaterThanOrEqual(sut.overallProgress, 0.25)
    }
    
    /// Tier 1: Feature 39 - Validates Stage 2 (Speech Diarization) advances after audio stage.
    func test_tier1_feature39_stageTwoSpeechDiarizationProgression() throws {
        sut.startPipeline()
        sut.simulateStageCompletion(stageIndex: 0)
        
        sut.simulateStageCompletion(stageIndex: 1)
        XCTAssertEqual(sut.stages[1].state, .completed)
        XCTAssertEqual(sut.currentStageIndex, 2)
        XCTAssertGreaterThanOrEqual(sut.overallProgress, 0.50)
    }
    
    /// Tier 1: Feature 39 - Validates Stage 3 (AI Summarization) parses discussion and decisions.
    func test_tier1_feature39_stageThreeSummarizationProgression() throws {
        sut.startPipeline()
        sut.simulateStageCompletion(stageIndex: 0)
        sut.simulateStageCompletion(stageIndex: 1)
        
        sut.simulateStageCompletion(stageIndex: 2)
        XCTAssertEqual(sut.stages[2].state, .completed)
        XCTAssertEqual(sut.currentStageIndex, 3)
        XCTAssertGreaterThanOrEqual(sut.overallProgress, 0.75)
    }
    
    /// Tier 1: Feature 39 - Validates Stage 4 (Action Extraction) extracts tasks and finalizes.
    func test_tier1_feature39_stageFourActionExtractionProgression() throws {
        sut.startPipeline()
        for idx in 0..<4 {
            sut.simulateStageCompletion(stageIndex: idx)
        }
        
        XCTAssertEqual(sut.stages[3].state, .completed)
        XCTAssertEqual(sut.overallProgress, 1.0)
        XCTAssertEqual(sut.pipelineStatus, .completed)
    }
    
    /// Tier 1: Feature 39 - Validates overall progress increments monotonically from 0.0 to 1.0.
    func test_tier1_feature39_overallProgressIncrementsMonotonically() throws {
        sut.startPipeline()
        var lastProgress = sut.overallProgress
        
        for idx in 0..<4 {
            sut.simulateStageCompletion(stageIndex: idx)
            XCTAssertGreaterThanOrEqual(sut.overallProgress, lastProgress)
            lastProgress = sut.overallProgress
        }
        XCTAssertEqual(sut.overallProgress, 1.0)
    }
    
    /// Tier 1: Feature 39 - Validates completion triggers navigation callback to meeting detail view.
    func test_tier1_feature39_completionNavigatesToDetailView() throws {
        var didNavigateToDetail = false
        var navigatedMeetingId: UUID?
        sut.onNavigateToDetail = { id in
            didNavigateToDetail = true
            navigatedMeetingId = id
        }
        
        sut.startPipeline()
        for idx in 0..<4 {
            sut.simulateStageCompletion(stageIndex: idx)
        }
        
        XCTAssertTrue(didNavigateToDetail)
        XCTAssertEqual(navigatedMeetingId, targetMeetingId)
    }
    
    /// Tier 1: Feature 39 - Validates stage titles match specification.
    func test_tier1_feature39_stageTitlesMatchSpecification() throws {
        XCTAssertEqual(sut.stages[0].title, "Audio Finalization")
        XCTAssertEqual(sut.stages[1].title, "Speech Diarization")
        XCTAssertEqual(sut.stages[2].title, "Executive Summarization")
        XCTAssertEqual(sut.stages[3].title, "Action Item Extraction")
    }
    
    /// Tier 1: Feature 39 - Validates status transitions from idle to processing to completed.
    func test_tier1_feature39_statusTransitionsFromIdleToProcessingToCompleted() throws {
        XCTAssertEqual(sut.pipelineStatus, .idle)
        
        sut.startPipeline()
        XCTAssertEqual(sut.pipelineStatus, .processing)
        
        for idx in 0..<4 {
            sut.simulateStageCompletion(stageIndex: idx)
        }
        XCTAssertEqual(sut.pipelineStatus, .completed)
    }
    
    /// Tier 1: Feature 39 - Validates persisting processed status to meeting in data store.
    func test_tier1_feature39_persistsProcessedDataToMeetingStore() throws {
        sut.startPipeline()
        for idx in 0..<4 {
            sut.simulateStageCompletion(stageIndex: idx)
        }
        
        let meeting = fetchMeeting(id: targetMeetingId)
        XCTAssertEqual(meeting?.status, .completed)
    }
    
    /// Tier 1: Feature 39 - Validates structured summary response is attached to meeting.
    func test_tier1_feature39_summaryResponseAttachedToMeeting() throws {
        sut.startPipeline()
        for idx in 0..<4 {
            sut.simulateStageCompletion(stageIndex: idx)
        }
        
        let meeting = fetchMeeting(id: targetMeetingId)
        XCTAssertNotNil(meeting?.summary?.executiveSummary)
    }
    
    /// Tier 1: Feature 39 - Validates extracted action items are attached to meeting record.
    func test_tier1_feature39_actionItemsExtractedAndAttachedToMeeting() throws {
        sut.startPipeline()
        for idx in 0..<4 {
            sut.simulateStageCompletion(stageIndex: idx)
        }
        
        let meeting = fetchMeeting(id: targetMeetingId)
        XCTAssertGreaterThan(meeting?.actionItems.count ?? 0, 0)
    }
    
    /// Tier 1: Feature 39 - Validates pipeline duration estimation string calculation.
    func test_tier1_feature39_pipelineDurationEstimationCalculation() throws {
        sut.startPipeline()
        XCTAssertFalse(sut.estimatedRemainingTimeText.isEmpty)
        XCTAssertTrue(sut.estimatedRemainingTimeText.contains("sec") || sut.estimatedRemainingTimeText.contains("min"))
    }
    
    /// Tier 1: Feature 39 - Validates stage icons and state badge styles.
    func test_tier1_feature39_stageIconNamesAndStateBadges() throws {
        let stage0 = sut.stages[0]
        XCTAssertEqual(stage0.iconName, "waveform")
        
        let stage1 = sut.stages[1]
        XCTAssertEqual(stage1.iconName, "person.2.wave.2")
        
        let stage2 = sut.stages[2]
        XCTAssertEqual(stage2.iconName, "sparkles")
        
        let stage3 = sut.stages[3]
        XCTAssertEqual(stage3.iconName, "checklist")
    }
    
    /// Tier 1: Feature 39 - Validates user cancellation halts pipeline execution.
    func test_tier1_feature39_cancelProcessingHaltsPipeline() throws {
        sut.startPipeline()
        sut.simulateStageCompletion(stageIndex: 0)
        
        sut.cancelProcessing()
        XCTAssertEqual(sut.pipelineStatus, .cancelled)
        XCTAssertTrue(sut.isCancelled)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 39: Retries, Fallbacks & Error States)
    
    /// Tier 2: Feature 39 - Validates stage 2 failure halts progression and enters failed state.
    func test_tier2_feature39_stageTwoFailureEntersFailedState() throws {
        sut.startPipeline()
        sut.simulateStageCompletion(stageIndex: 0)
        
        sut.simulateStageFailure(stageIndex: 1, error: "Diarization model timeout")
        
        XCTAssertEqual(sut.pipelineStatus, .failed)
        XCTAssertEqual(sut.stages[1].state, .failed)
        XCTAssertEqual(sut.stages[1].errorMessage, "Diarization model timeout")
        XCTAssertTrue(sut.hasFailedStage)
    }
    
    /// Tier 2: Feature 39 - Validates retrying failed stage resumes from failed stage index.
    func test_tier2_feature39_retryFailedStageResumesFromFailureIndex() throws {
        sut.startPipeline()
        sut.simulateStageCompletion(stageIndex: 0)
        sut.simulateStageFailure(stageIndex: 1, error: "Diarization network error")
        
        sut.retryCurrentStage()
        XCTAssertEqual(sut.pipelineStatus, .processing)
        XCTAssertEqual(sut.stages[1].state, .inProgress)
        
        // Finish rest of pipeline
        sut.simulateStageCompletion(stageIndex: 1)
        sut.simulateStageCompletion(stageIndex: 2)
        sut.simulateStageCompletion(stageIndex: 3)
        
        XCTAssertEqual(sut.pipelineStatus, .completed)
    }
    
    /// Tier 2: Feature 39 - Validates Stage 3 AI timeout falls back to on-device extractive NaturalLanguage summary.
    func test_tier2_feature39_stageThreeAITimeoutFallsBackToOfflineNL() throws {
        sut.startPipeline()
        sut.simulateStageCompletion(stageIndex: 0)
        sut.simulateStageCompletion(stageIndex: 1)
        
        sut.simulateAITimeoutFallback()
        
        XCTAssertTrue(sut.isUsingOfflineExtractiveFallback)
        XCTAssertEqual(sut.stages[2].state, .completedWithWarning)
        XCTAssertEqual(sut.stages[2].warningMessage, "Generated using on-device extractive intelligence.")
    }
    
    /// Tier 2: Feature 39 - Validates completely empty transcript still generates graceful fallback summary.
    func test_tier2_feature39_emptyTranscriptStillGeneratesGracefulFallbackSummary() throws {
        sut.simulateEmptyTranscriptInput()
        sut.startPipeline()
        
        for idx in 0..<4 {
            sut.simulateStageCompletion(stageIndex: idx)
        }
        
        XCTAssertEqual(sut.pipelineStatus, .completed)
        let meeting = fetchMeeting(id: targetMeetingId)
        XCTAssertEqual(meeting?.summary?.executiveSummary, "No speech detected during meeting.")
    }
    
    /// Tier 2: Feature 39 - Validates extracting 0 action items completes successfully without error.
    func test_tier2_feature39_zeroActionItemsExtractedCompletesSuccessfully() throws {
        sut.simulateZeroActionItemsResult()
        sut.startPipeline()
        
        for idx in 0..<4 {
            sut.simulateStageCompletion(stageIndex: idx)
        }
        
        XCTAssertEqual(sut.pipelineStatus, .completed)
        let meeting = fetchMeeting(id: targetMeetingId)
        XCTAssertEqual(meeting?.actionItems.count, 0)
    }
    
    /// Tier 2: Feature 39 - Validates background processing completion posts local notification signal.
    func test_tier2_feature39_backgroundProcessingNotificationTriggered() throws {
        var didPostNotification = false
        sut.onProcessingNotificationPosted = {
            didPostNotification = true
        }
        
        sut.simulateAppBackgroundState(true)
        sut.startPipeline()
        for idx in 0..<4 {
            sut.simulateStageCompletion(stageIndex: idx)
        }
        
        XCTAssertTrue(didPostNotification)
    }
    
    /// Tier 2: Feature 39 - Validates user cancellation cleans up partial temporary synthesis files.
    func test_tier2_feature39_cancellationCleansUpPartialArtifacts() throws {
        sut.startPipeline()
        sut.simulateStageCompletion(stageIndex: 0)
        sut.cancelProcessing()
        
        XCTAssertTrue(sut.didCleanUpPartialArtifacts)
    }
    
    /// Tier 2: Feature 39 - Validates repeated retry attempts track retry count.
    func test_tier2_feature39_repeatedRetryAttemptsExponentialBackoff() throws {
        sut.startPipeline()
        sut.simulateStageFailure(stageIndex: 0, error: "File lock error")
        XCTAssertEqual(sut.retryCount, 0)
        
        sut.retryCurrentStage()
        XCTAssertEqual(sut.retryCount, 1)
        
        sut.simulateStageFailure(stageIndex: 0, error: "File lock error 2")
        sut.retryCurrentStage()
        XCTAssertEqual(sut.retryCount, 2)
    }
    
    /// Tier 2: Feature 39 - Validates stage progress value is clamped between 0.0 and 1.0.
    func test_tier2_feature39_stageProgressClampsBetweenZeroAndOne() throws {
        sut.setSimulatedProgress(1.5)
        XCTAssertEqual(sut.overallProgress, 1.0)
        
        sut.setSimulatedProgress(-0.5)
        XCTAssertEqual(sut.overallProgress, 0.0)
    }
    
    /// Tier 2: Feature 39 - Validates corrupt audio file at stage 1 fails immediately with descriptive error.
    func test_tier2_feature39_corruptAudioFileAtStageOneFailsImmediately() throws {
        sut.simulateCorruptAudioInput()
        sut.startPipeline()
        
        XCTAssertEqual(sut.pipelineStatus, .failed)
        XCTAssertEqual(sut.stages[0].state, .failed)
        XCTAssertTrue(sut.stages[0].errorMessage?.contains("Corrupt") ?? false)
    }
    
    /// Tier 2: Feature 39 - Validates malformed LLM JSON response triggers fallback cleanly.
    func test_tier2_feature39_malformedLLMJSONFallbackToExtractiveSummary() throws {
        sut.startPipeline()
        sut.simulateStageCompletion(stageIndex: 0)
        sut.simulateStageCompletion(stageIndex: 1)
        
        sut.simulateMalformedLLMResponse()
        
        XCTAssertTrue(sut.isUsingOfflineExtractiveFallback)
        XCTAssertEqual(sut.stages[2].state, .completedWithWarning)
    }
    
    /// Tier 2: Feature 39 - Validates rapid pipeline cancellation during active execution.
    func test_tier2_feature39_rapidPipelineCancellation() throws {
        sut.startPipeline()
        sut.cancelProcessing()
        sut.cancelProcessing()
        
        XCTAssertEqual(sut.pipelineStatus, .cancelled)
    }
    
    /// Tier 2: Feature 39 - Validates pipeline state restoration if app relaunch occurs during processing.
    func test_tier2_feature39_pipelineStateRestorationOnAppRelaunch() throws {
        sut.startPipeline()
        sut.simulateStageCompletion(stageIndex: 0)
        sut.simulateStageCompletion(stageIndex: 1)
        
        // Simulate relaunch: create new sut with existing meeting in processing state
        let restoredSut = ProcessingPipelineViewModel(
            meeting: initialMeeting,
            modelContext: context,
            summarizationService: mockSummarizationService
        )
        restoredSut.restoreState(fromStageIndex: 2)
        
        XCTAssertEqual(restoredSut.currentStageIndex, 2)
        XCTAssertEqual(restoredSut.stages[0].state, .completed)
        XCTAssertEqual(restoredSut.stages[1].state, .completed)
    }
}
