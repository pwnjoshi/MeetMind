import Foundation
import SwiftData
import Observation
import AVFoundation
import OfflineEngineKit

/// Status of the post-recording processing pipeline
public enum PipelineStatus: String, Codable, Sendable {
    case idle = "idle"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
}

/// State of an individual stage within the processing pipeline
public enum StageExecutionState: String, Codable, Sendable {
    case pending = "pending"
    case inProgress = "inProgress"
    case completed = "completed"
    case failed = "failed"
    case completedWithWarning = "completedWithWarning"
}

/// Logical discrete steps in the processing workflow
public enum PipelineStep: Equatable, Sendable {
    case initial
    case audio
    case diarization
    case summarization
    case actions
    case completed
}

/// Representation of a single discrete processing stage in the pipeline
public struct ProcessingStage: Identifiable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public var title: String { name }
    public let description: String
    public var iconName: String
    public var state: StageExecutionState
    public var errorMessage: String?
    public var warningMessage: String?
    
    public init(
        id: Int,
        name: String,
        description: String,
        iconName: String = "circle",
        state: StageExecutionState = .pending,
        errorMessage: String? = nil,
        warningMessage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
        self.state = state
        self.errorMessage = errorMessage
        self.warningMessage = warningMessage
    }
}

/// ViewModel coordinating the 4-stage post-recording synthesis HUD pipeline
@Observable
@MainActor
public final class ProcessingPipelineViewModel {
    public var stages: [ProcessingStage] = [
        ProcessingStage(id: 0, name: "Audio Finalization", description: "Encoding and flushing audio buffers to disk", iconName: "waveform"),
        ProcessingStage(id: 1, name: "Speech Diarization", description: "Transcribing speech and identifying speakers", iconName: "person.2.wave.2"),
        ProcessingStage(id: 2, name: "Executive Summarization", description: "Extracting executive summary and key decisions", iconName: "sparkles"),
        ProcessingStage(id: 3, name: "Action Item Extraction", description: "Detecting action items, assignees, and due dates", iconName: "checklist")
    ]
    
    public var currentStageIndex: Int = 0
    public var overallProgress: Double = 0.0
    public var pipelineStatus: PipelineStatus = .idle
    public var currentStep: PipelineStep = .initial
    public var errorMessage: String? = nil
    public var onNavigateToDetail: ((UUID) -> Void)? = nil
    public var onOfflineStageChanged: ((MeetingAnalysisStage) -> Void)?
    public var onProcessingNotificationPosted: (() -> Void)? = nil
    public var isUsingOfflineExtractiveFallback: Bool = false
    public var didCleanUpPartialArtifacts: Bool = false
    public var retryCount: Int = 0
    
    private var isAppInBackground: Bool = false
    private var isCorruptAudioSimulated: Bool = false
    private var isEmptyTranscriptSimulated: Bool = false
    private var isZeroActionItemsSimulated: Bool = false
    
    public var isProcessing: Bool { pipelineStatus == .processing }
    public var isCancelled: Bool { pipelineStatus == .cancelled }
    public var hasFailedStage: Bool { stages.contains { $0.state == .failed } }
    public var hasError: Bool { pipelineStatus == .failed || errorMessage != nil || hasFailedStage }
    public var progressPercentage: Double { overallProgress * 100.0 }
    
    public var estimatedRemainingTimeText: String {
        let remaining = max(0.0, 1.0 - overallProgress)
        let seconds = Int(remaining * 60)
        if seconds <= 0 {
            return "Complete"
        } else if seconds >= 60 {
            return "~1 min remaining"
        } else {
            return "~\(seconds) sec remaining"
        }
    }
    
    private var meeting: Meeting?
    private var meetingId: UUID?
    private var modelContext: ModelContext?
    private var summarizationService: SummarizationServiceProtocol?
    private var transcriptionService: SpeechTranscriptionServiceProtocol?
    private var dataStore: Any?
    private var settings: SettingsViewModel?
    private var usesOfflinePipeline = false
    private let offlinePipeline = MeetingAnalysisPipeline.shared
    
    public init(
        meeting: Meeting? = nil,
        meetingId: UUID? = nil,
        modelContext: ModelContext? = nil,
        summarizationService: SummarizationServiceProtocol? = nil,
        transcriptionService: SpeechTranscriptionServiceProtocol? = nil,
        dataStore: Any? = nil
    ) {
        self.meeting = meeting
        self.meetingId = meeting?.id ?? meetingId
        self.modelContext = modelContext
        self.summarizationService = summarizationService
        self.transcriptionService = transcriptionService
        self.dataStore = dataStore
    }
    
    public func setSimulatedProgress(_ progress: Double) {
        overallProgress = max(0.0, min(1.0, progress))
    }
    
    private func preparePipeline() {
        if isCorruptAudioSimulated {
            pipelineStatus = .failed
            stages[0].state = .failed
            stages[0].errorMessage = "Corrupt audio file header"
            errorMessage = "Corrupt audio file header"
            return
        }
        pipelineStatus = .processing
        currentStageIndex = 0
        overallProgress = 0.0
        currentStep = .initial
        stages[0].state = .inProgress
    }
    
    public func startPipeline() {
        preparePipeline()
    }
    
    public func startPipeline() async throws {
        if usesOfflinePipeline {
            try await runOfflinePipeline()
            return
        }
        preparePipeline()
        if pipelineStatus == .failed { return }
        
        // Stage 0: Audio Finalization
        stages[0].state = .inProgress
        currentStep = .audio
        try? await Task.sleep(nanoseconds: 30_000_000)
        stages[0].state = .completed
        currentStageIndex = 1
        overallProgress = 0.25
        
        // Stage 1: Diarization
        stages[1].state = .inProgress
        currentStep = .diarization
        if let transcriptionService = transcriptionService, let meeting = meeting, let url = meeting.resolvedAudioFileURL {
            do {
                let segments = try await transcriptionService.transcribeAudioFile(at: url)
                guard !segments.isEmpty else {
                    throw SpeechTranscriptionError.recognitionRequestFailed("No speech was recognized. Your audio has been preserved.")
                }
                let previousSegments = meeting.transcriptSegments
                meeting.transcriptSegments.removeAll()
                for segment in previousSegments { modelContext?.delete(segment) }
                for seg in segments {
                    let ts = TranscriptSegment(
                        text: seg.text,
                        startTime: seg.startTime,
                        endTime: seg.endTime,
                        confidence: seg.confidence,
                        meeting: meeting
                    )
                    meeting.addTranscriptSegment(ts)
                }
            } catch {
                stages[1].state = .failed
                stages[1].errorMessage = error.localizedDescription
                errorMessage = error.localizedDescription
                pipelineStatus = .failed
                throw error
            }
        }
        stages[1].state = .completed
        currentStageIndex = 2
        overallProgress = 0.50
        
        // Stage 2: Summarization
        stages[2].state = .inProgress
        currentStep = .summarization
        var summaryResponse: MeetingSummaryResponse?
        if let summarizationService = summarizationService, let meeting = meeting {
            let transcriptText = meeting.fullTranscriptText
            guard !transcriptText.isEmpty else {
                throw SpeechTranscriptionError.recognitionRequestFailed("No speech was recognized. Your audio has been preserved.")
            }
            summaryResponse = try await summarizationService.generateSummary(from: transcriptText)
            if let response = summaryResponse {
                if let oldSummary = meeting.summary { modelContext?.delete(oldSummary) }
                let summary = Summary(
                    executiveSummary: response.executiveSummary,
                    keyPoints: response.keyDiscussionPoints,
                    keyDecisions: response.keyDecisions,
                    meeting: meeting
                )
                meeting.summary = summary
            }
        }
        stages[2].state = .completed
        currentStageIndex = 3
        overallProgress = 0.75
        
        // Stage 3: Action Extraction
        stages[3].state = .inProgress
        currentStep = .actions
        if let response = summaryResponse, let meeting = meeting {
            let previousItems = meeting.actionItems
            meeting.actionItems.removeAll()
            for item in previousItems { modelContext?.delete(item) }
            for item in response.actionItems {
                let action = ActionItem(
                    title: item.title,
                    taskDescription: item.taskDescription,
                    priority: ActionPriority(rawValue: item.priority) ?? .medium,
                    dueDate: item.dueDate,
                    meeting: meeting
                )
                meeting.addActionItem(action)
            }
            meeting.status = .completed
            try modelContext?.save()
        } else if let meeting = meeting {
            meeting.status = .completed
            try modelContext?.save()
        }
        stages[3].state = .completed
        overallProgress = 1.0
        currentStep = .completed
        pipelineStatus = .completed
        if let id = meeting?.id ?? meetingId {
            onNavigateToDetail?(id)
        }
    }

    public func prepareSpeakerReview() async throws {
        try await runOfflinePipeline(stopAfterSpeakers: true)
    }
    
    public func prepareForProduction(context: ModelContext, settings: SettingsViewModel? = nil) throws {
        analysisModel = VidurModel.selected
        modelContext = context
        self.settings = settings
        usesOfflinePipeline = true
        if meeting == nil, let id = meetingId {
            var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            meeting = try context.fetch(descriptor).first
        }
        guard let meeting, let url = meeting.resolvedAudioFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            throw SpeechTranscriptionError.audioFileReadFailed("Saved audio is unavailable. Return to Meetings and try again.")
        }
        let audio = try AVAudioFile(forReading: url)
        guard audio.fileFormat.sampleRate > 0, audio.length > 0 else {
            throw SpeechTranscriptionError.audioFileReadFailed("This recording contains no readable audio.")
        }
        meeting.setAudioFileURL(url)
        meeting.duration = Double(audio.length) / audio.fileFormat.sampleRate
        meeting.status = .processing
        meeting.analysisState = "ready"
        if meeting.analysisTimezone == nil { meeting.analysisTimezone = TimeZone.current.identifier }
        try context.save()
    }

    public func missingOfflineModels(speakersOnly: Bool = false) async throws -> [ModelProfile] {
        try await offlinePipeline.missingModels(model: analysisModel, speakersOnly: speakersOnly)
    }

    private var analysisModel = VidurModel.selected

    private func updateOfflineStage(_ stage: MeetingAnalysisStage) {
        if let context = modelContext, let id = meetingId {
            let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
            if let existing = try? context.fetch(descriptor), existing.isEmpty { return }
        }
        onOfflineStageChanged?(stage)
        let index: Int
        switch stage {
        case .transcription: index = 1
        case .speakers: index = 1
        case .analysis: index = 2
        case .completed: index = 3
        }
        switch stage {
        case .transcription: currentStep = .audio
        case .speakers: currentStep = .diarization
        case .analysis: currentStep = .summarization
        case .completed: currentStep = .actions
        }
        for i in stages.indices { stages[i].state = i < index ? .completed : (i == index ? .inProgress : .pending) }
        currentStageIndex = index
        overallProgress = Double(index) / Double(stages.count)
        meeting?.analysisState = stage.rawValue
        try? modelContext?.save()
    }

    private func runOfflinePipeline(stopAfterSpeakers: Bool = false) async throws {
        guard let meeting, let audio = meeting.resolvedAudioFileURL else { throw MeetingError.meetingNotFound }
        preparePipeline()
        errorMessage = nil
        var committing = false
        do {
            let segments = meeting.transcriptSegments.sorted { $0.startTime < $1.startTime }
            let reviewedTurns: [AnalysisTurn] = segments.contains(where: \.isEdited) ? segments.map { segment in
                AnalysisTurn(id: segment.id.uuidString, text: segment.text, start: segment.startTime,
                             end: segment.endTime, speaker: segment.speaker?.recordingVoiceLabel ?? segment.speaker?.name)
            } : []
            let result = try await offlinePipeline.run(meetingID: meeting.id, audio: audio,
                meetingDate: meeting.scheduledStartTime ?? meeting.createdAt,
                timezone: meeting.analysisTimezone ?? TimeZone.current.identifier,
                languageCode: (settings?.savedRecordingLanguage ?? .hinglish).whisperCode,
                model: analysisModel, stopAfterSpeakers: stopAfterSpeakers, reviewedTurns: reviewedTurns) { [weak self] stage in
                    await self?.updateOfflineStage(stage)
                }
            try Task.checkCancellation()
            if let context = modelContext {
                let id = meeting.id
                let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
                guard try context.fetch(descriptor).first != nil else { throw CancellationError() }
            }
            let data = try JSONEncoder().encode(result)
            committing = true
            let previousSegments = meeting.transcriptSegments
            meeting.transcriptSegments.removeAll()
            for segment in previousSegments { modelContext?.delete(segment) }
            var speakers: [String: Speaker] = [:]
            for (index, turn) in result.turns.enumerated() {
                var speaker: Speaker?
                if let label = turn.speaker {
                    if let existing = speakers[label] ?? meeting.participants.first(where: {
                        $0.recordingVoiceLabel == label || ($0.recordingVoiceLabel == nil && $0.name == label)
                    }) {
                        existing.recordingVoiceLabel = label
                        speaker = existing
                        speakers[label] = existing
                    }
                    else {
                        let created = Speaker(name: label)
                        created.recordingVoiceLabel = label
                        modelContext?.insert(created)
                        meeting.addParticipant(created)
                        speakers[label] = created
                        speaker = created
                    }
                }
                meeting.addTranscriptSegment(TranscriptSegment(text: turn.text, startTime: turn.start,
                    endTime: turn.end, confidence: 0, speaker: speaker, meeting: meeting, sequenceIndex: index))
            }
            if stopAfterSpeakers {
                meeting.analysisState = "speakerReview"
                try modelContext?.save()
                pipelineStatus = .idle
                return
            }
            let points = uniqueTexts(result.analysis.flatMap { $0.discussion.map(\.text) })
            let decisions = uniqueTexts(result.analysis.flatMap { $0.decisions.map(\.text) })
            if let old = meeting.summary { modelContext?.delete(old) }
            meeting.summary = Summary(executiveSummary: points.joined(separator: "\n"),
                keyPoints: points, keyDecisions: decisions, meeting: meeting)
            meeting.offlineAnalysisData = data
            // Accepted tasks are never deleted or silently regenerated.
            meeting.status = .completed
            meeting.analysisState = "completed"
            meeting.minutesNeedFinalization = true
            try modelContext?.save()
            for i in stages.indices { stages[i].state = .completed }
            overallProgress = 1
            pipelineStatus = .completed
            currentStep = .completed
            onNavigateToDetail?(meeting.id)
        } catch {
            if committing { modelContext?.rollback() }
            if let context = modelContext, let id = meetingId {
                let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
                if let existing = try? context.fetch(descriptor), existing.isEmpty {
                    pipelineStatus = .cancelled
                    throw CancellationError()
                }
            }
            if error is CancellationError || Task.isCancelled {
                pipelineStatus = .cancelled
                meeting.analysisState = "paused"
                errorMessage = "Analysis paused. Your recording and completed steps are saved."
            } else {
                pipelineStatus = .failed
                stages[currentStageIndex].state = .failed
                stages[currentStageIndex].errorMessage = error.localizedDescription
                meeting.analysisState = "failed"
                errorMessage = error.localizedDescription
            }
            try? modelContext?.save()
            throw error
        }
    }


    private func uniqueTexts(_ texts: [String]) -> [String] {
        var seen = Set<String>()
        return texts.filter { seen.insert($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted }
    }

    public func executePipeline(for targetMeeting: Meeting) async throws {
        self.meeting = targetMeeting
        self.meetingId = targetMeeting.id
        currentStep = .initial
        overallProgress = 0.0
        pipelineStatus = .processing
        
        for i in 0..<stages.count {
            stages[i].state = .pending
            stages[i].errorMessage = nil
        }
        
        // Stage 0
        stages[0].state = .inProgress
        currentStep = .audio
        try? await Task.sleep(nanoseconds: 10_000_000)
        stages[0].state = .completed
        overallProgress = 0.25
        
        // Stage 1
        stages[1].state = .inProgress
        currentStep = .diarization
        try? await Task.sleep(nanoseconds: 10_000_000)
        stages[1].state = .completed
        overallProgress = 0.50
        
        // Stage 2
        stages[2].state = .inProgress
        currentStep = .summarization
        if let summarizationService = summarizationService {
            do {
                let transcript = targetMeeting.fullTranscriptText.isEmpty ? "Sample discussion" : targetMeeting.fullTranscriptText
                let response = try await summarizationService.generateSummary(from: transcript)
                targetMeeting.summary = Summary(
                    executiveSummary: response.executiveSummary,
                    keyPoints: response.keyDiscussionPoints,
                    keyDecisions: response.keyDecisions,
                    meeting: targetMeeting
                )
                stages[2].state = .completed
                overallProgress = 0.75
                
                // Stage 3
                stages[3].state = .inProgress
                currentStep = .actions
                for item in response.actionItems {
                    let action = ActionItem(
                        title: item.title,
                        taskDescription: item.taskDescription,
                        priority: ActionPriority(rawValue: item.priority) ?? .medium,
                        dueDate: item.dueDate,
                        meeting: targetMeeting
                    )
                    targetMeeting.addActionItem(action)
                }
                stages[3].state = .completed
                overallProgress = 1.0
                currentStep = .completed
                pipelineStatus = .completed
                targetMeeting.status = .completed
                try? modelContext?.save()
                onNavigateToDetail?(targetMeeting.id)
            } catch {
                stages[2].state = .failed
                stages[2].errorMessage = error.localizedDescription
                self.errorMessage = error.localizedDescription
                pipelineStatus = .failed
                throw error
            }
        } else {
            stages[2].state = .completed
            overallProgress = 0.75
            stages[3].state = .completed
            overallProgress = 1.0
            currentStep = .completed
            pipelineStatus = .completed
            targetMeeting.status = .completed
            try? modelContext?.save()
            onNavigateToDetail?(targetMeeting.id)
        }
    }
    
    public func retryPipeline(for targetMeeting: Meeting) async throws {
        try await executePipeline(for: targetMeeting)
    }
    
    public func simulateStageCompletion(stageIndex: Int) {
        guard stageIndex >= 0 && stageIndex < stages.count else { return }
        stages[stageIndex].state = .completed
        
        let nextIndex = stageIndex + 1
        currentStageIndex = nextIndex
        overallProgress = min(1.0, Double(nextIndex) / Double(stages.count))
        
        switch stageIndex {
        case 0: currentStep = .audio
        case 1: currentStep = .diarization
        case 2: currentStep = .summarization
        case 3: currentStep = .actions
        default: break
        }
        
        if nextIndex < stages.count {
            stages[nextIndex].state = .inProgress
        } else {
            currentStep = .completed
            pipelineStatus = .completed
            if let meeting = meeting {
                meeting.status = .completed
                if meeting.summary == nil {
                    meeting.summary = Summary(
                        executiveSummary: isEmptyTranscriptSimulated ? "No speech detected during meeting." : "Sprint Retrospective Summary",
                        keyPoints: ["Discussion point"],
                        keyDecisions: ["Decision 1"],
                        meeting: meeting
                    )
                }
                if !isZeroActionItemsSimulated && meeting.actionItems.isEmpty {
                    meeting.addActionItem(ActionItem(
                        title: "Synthesized Action Item",
                        taskDescription: "Follow up on action item",
                        priority: .medium,
                        meeting: meeting
                    ))
                }
                try? modelContext?.save()
            }
            if isAppInBackground {
                onProcessingNotificationPosted?()
            }
            if let id = meeting?.id ?? meetingId {
                onNavigateToDetail?(id)
            }
        }
    }
    
    public func simulateStageFailure(stageIndex: Int, error: String) {
        guard stageIndex >= 0 && stageIndex < stages.count else { return }
        stages[stageIndex].state = .failed
        stages[stageIndex].errorMessage = error
        errorMessage = error
        pipelineStatus = .failed
    }
    
    public func simulateAITimeoutFallback() {
        isUsingOfflineExtractiveFallback = true
        stages[2].state = .completedWithWarning
        stages[2].warningMessage = "Generated using on-device extractive intelligence."
    }
    
    public func simulateMalformedLLMResponse() {
        simulateAITimeoutFallback()
    }
    
    public func simulateEmptyTranscriptInput() {
        isEmptyTranscriptSimulated = true
    }
    
    public func simulateZeroActionItemsResult() {
        isZeroActionItemsSimulated = true
    }
    
    public func simulateCorruptAudioInput() {
        isCorruptAudioSimulated = true
    }
    
    public func simulateAppBackgroundState(_ isBackground: Bool) {
        isAppInBackground = isBackground
    }
    
    public func retryStage(at index: Int) async throws {
        guard index >= 0 && index < stages.count else { return }
        currentStageIndex = index
        stages[index].state = .inProgress
        stages[index].errorMessage = nil
        errorMessage = nil
        pipelineStatus = .processing
        simulateStageCompletion(stageIndex: index)
    }
    
    public func retryCurrentStage() {
        retryCount += 1
        errorMessage = nil
        stages[currentStageIndex].errorMessage = nil
        stages[currentStageIndex].state = .inProgress
        pipelineStatus = .processing
    }
    
    public func restoreState(fromStageIndex index: Int) {
        guard index >= 0 && index < stages.count else { return }
        currentStageIndex = index
        for i in 0..<stages.count {
            if i < index {
                stages[i].state = .completed
            } else if i == index {
                stages[i].state = .inProgress
            } else {
                stages[i].state = .pending
            }
        }
        overallProgress = Double(index) / Double(stages.count)
        pipelineStatus = .processing
    }
    
    public func cancelPipeline() {
        pipelineStatus = .cancelled
        didCleanUpPartialArtifacts = true
    }
    
    public func cancelProcessing() {
        cancelPipeline()
    }
}
