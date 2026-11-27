import Foundation
import SwiftData
import Observation
import AVFoundation
import OfflineEngineKit

public struct ModelDownloadProgress: Sendable, Equatable {
    public let downloadedBytes: Int64
    public let totalBytes: Int64
    public let currentModelID: String
    public let currentModelName: String
    public let currentModelFraction: Double

    public var fraction: Double {
        guard totalBytes > 0 else { return 1 }
        return min(1, max(0, Double(downloadedBytes) / Double(totalBytes)))
    }

    public init(downloadedBytes: Int64, totalBytes: Int64, currentModelID: String,
                currentModelName: String, currentModelFraction: Double) {
        self.downloadedBytes = max(0, min(downloadedBytes, max(0, totalBytes)))
        self.totalBytes = max(0, totalBytes)
        self.currentModelID = currentModelID
        self.currentModelName = currentModelName
        self.currentModelFraction = min(1, max(0, currentModelFraction))
    }
}

/// Converts the model store's per-model fractions into one byte-weighted,
/// monotonic transfer. The lock is needed because model-store callbacks are Sendable.
public final class ModelDownloadProgressAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let profiles: [ModelProfile]
    private let profileByID: [String: ModelProfile]
    private var fractions: [String: Double] = [:]
    private var lastDownloadedBytes: Int64 = 0

    public init(profiles: [ModelProfile]) {
        self.profiles = profiles
        self.profileByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    }

    public func initialProgress() -> ModelDownloadProgress {
        lock.lock()
        defer { lock.unlock() }
        return makeProgress(currentID: profiles.first?.id ?? "", currentFraction: 0)
    }

    public func update(modelID: String, fraction: Double) -> ModelDownloadProgress {
        lock.lock()
        defer { lock.unlock() }
        let clamped = min(1, max(0, fraction))
        if let index = profiles.firstIndex(where: { $0.id == modelID }), index > 0 {
            for completed in profiles[..<index] { fractions[completed.id] = 1 }
        }
        fractions[modelID] = max(fractions[modelID] ?? 0, clamped)
        return makeProgress(currentID: modelID, currentFraction: fractions[modelID] ?? clamped)
    }

    private func makeProgress(currentID: String, currentFraction: Double) -> ModelDownloadProgress {
        let total = profiles.reduce(Int64(0)) { $0 + $1.downloadBytes }
        let calculated = profiles.reduce(Int64(0)) { result, profile in
            result + Int64((Double(profile.downloadBytes) * (fractions[profile.id] ?? 0)).rounded(.down))
        }
        lastDownloadedBytes = max(lastDownloadedBytes, min(total, calculated))
        return ModelDownloadProgress(downloadedBytes: lastDownloadedBytes, totalBytes: total,
            currentModelID: currentID, currentModelName: Self.friendlyName(for: currentID),
            currentModelFraction: currentFraction)
    }

    public static func friendlyName(for id: String) -> String {
        switch id {
        case "whisper-large": return "Transcript model"
        case "diarization": return "Speakers model"
        case VidurModel.fast.rawValue: return "Minutes & Vidur model"
        default: return "On-device model"
        }
    }
}

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
    public private(set) var jobSnapshot: AnalysisJobRecord?
    public private(set) var modelStatuses: [AnalysisModelStatus] = []
    public private(set) var modelDownloadProgress: ModelDownloadProgress?
    
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
    private var coordinator: AnalysisCoordinator?
    
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
    
    #if DEBUG
    public func setSimulatedProgress(_ progress: Double) {
        overallProgress = max(0.0, min(1.0, progress))
    }
    #endif
    
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
    
    #if DEBUG
    public func startPipeline() {
        preparePipeline()
    }
    #endif
    
    public func startPipeline() async throws {
        if usesOfflinePipeline {
            try await runOfflinePipeline()
            return
        }
        #if DEBUG
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
        #else
        throw AnalysisCoordinatorError.failed(.stable(.processingFailed))
        #endif
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
        guard meeting != nil else { throw MeetingError.meetingNotFound }
        coordinator = AnalysisCoordinator(context: context)
    }

    @discardableResult
    public func refreshAnalysisState(speakersOnly: Bool = false) async throws -> AnalysisJobRecord {
        guard let coordinator, let meetingID = meeting?.id ?? meetingId else { throw MeetingError.meetingNotFound }
        let record = try await coordinator.prepare(meetingID: meetingID,
            languageCode: (settings?.savedRecordingLanguage ?? .hinglish).whisperCode,
            model: analysisModel, speakersOnly: speakersOnly)
        jobSnapshot = record
        modelStatuses = try await coordinator.modelStatus(meetingID: meetingID, model: analysisModel,
                                                           speakersOnly: speakersOnly)
        if modelStatuses.contains(where: { $0.readiness != .ready }) {
            try await coordinator.markModelsRequired(meetingID: meetingID)
            jobSnapshot = try await coordinator.snapshot(meetingID: meetingID)
        }
        return jobSnapshot ?? record
    }

    public func missingOfflineModels(speakersOnly: Bool = false) async throws -> [ModelProfile] {
        _ = try await refreshAnalysisState(speakersOnly: speakersOnly)
        return modelStatuses.compactMap { $0.readiness == .ready ? nil : $0.profile }
    }

    public func modelStorageCapacity(speakersOnly: Bool = false) async throws -> ModelStorageCapacity {
        _ = try await refreshAnalysisState(speakersOnly: speakersOnly)
        let profiles = modelStatuses.compactMap { $0.readiness == .ready ? nil : $0.profile }
        return try await OfflineModelStore.shared.storageCapacity(for: profiles)
    }

    /// Original callback shape retained for existing callers. Values remain the
    /// independent progress fraction for the named model.
    public func downloadAndContinueModels(speakersOnly: Bool = false,
                                          progress: @Sendable @escaping (String, Double) -> Void) async throws {
        try await downloadAndContinueModels(speakersOnly: speakersOnly) { aggregate in
            progress(aggregate.currentModelID, aggregate.currentModelFraction)
        }
    }

    /// Preferred callback reports byte-weighted progress across every model that
    /// was missing or damaged when this download began.
    public func downloadAndContinueModels(speakersOnly: Bool = false,
                                          progress: @Sendable @escaping (ModelDownloadProgress) -> Void) async throws {
        guard let coordinator, let meetingID = meeting?.id ?? meetingId else { throw MeetingError.meetingNotFound }
        _ = try await refreshAnalysisState(speakersOnly: speakersOnly)
        let profiles = modelStatuses.compactMap { $0.readiness == .ready ? nil : $0.profile }
        let accumulator = ModelDownloadProgressAccumulator(profiles: profiles)
        let initial = accumulator.initialProgress()
        modelDownloadProgress = initial
        progress(initial)
        do {
            try await coordinator.downloadAndVerify(meetingID: meetingID, model: analysisModel,
                                                    speakersOnly: speakersOnly, progress: { [weak self] id, value in
                let aggregate = accumulator.update(modelID: id, fraction: value)
                progress(aggregate)
                Task { @MainActor in
                    guard let self else { return }
                    self.applyModelDownloadProgress(aggregate)
                }
            }) { [weak self] state in
                guard var snapshot = self?.jobSnapshot else { return }
                snapshot.state = state
                self?.jobSnapshot = snapshot
            }
            let completedID = profiles.last?.id ?? ""
            let completed = accumulator.update(modelID: completedID, fraction: 1)
            applyModelDownloadProgress(completed)
            progress(completed)
            _ = try await refreshAnalysisState(speakersOnly: speakersOnly)
        } catch is CancellationError {
            markModelDownloadPaused()
            throw CancellationError()
        } catch let error as URLError {
            markModelDownloadPaused()
            throw error
        } catch {
            throw error
        }
    }

    public func markModelDownloadPaused() {
        if var snapshot = jobSnapshot {
            snapshot.state = .paused
            snapshot.failure = nil
            jobSnapshot = snapshot
        }
    }

    private func applyModelDownloadProgress(_ progress: ModelDownloadProgress) {
        guard progress.downloadedBytes >= (modelDownloadProgress?.downloadedBytes ?? 0) else { return }
        modelDownloadProgress = progress
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
        guard let coordinator, let meetingID = meeting?.id ?? meetingId else { throw MeetingError.meetingNotFound }
        preparePipeline()
        errorMessage = nil
        do {
            let snapshot = try await coordinator.run(meetingID: meetingID,
                languageCode: (settings?.savedRecordingLanguage ?? .hinglish).whisperCode,
                model: analysisModel, owner: .foreground, stopAfterSpeakers: stopAfterSpeakers) { [weak self] stage in
                    self?.updateOfflineStage(stage)
                }
            jobSnapshot = snapshot
            if stopAfterSpeakers {
                pipelineStatus = .idle
                if snapshot.warning != nil { stages[1].state = .completedWithWarning }
                return
            }
            for index in stages.indices { stages[index].state = .completed }
            overallProgress = 1
            pipelineStatus = .completed
            currentStep = .completed
            onNavigateToDetail?(meetingID)
        } catch is CancellationError {
            pipelineStatus = .cancelled
            errorMessage = "Analysis paused. Your recording and completed steps are saved."
            jobSnapshot = try? await coordinator.snapshot(meetingID: meetingID)
            throw CancellationError()
        } catch {
            jobSnapshot = try? await coordinator.snapshot(meetingID: meetingID)
            let message = jobSnapshot?.failure?.message ?? error.localizedDescription
            pipelineStatus = .failed
            stages[currentStageIndex].state = .failed
            stages[currentStageIndex].errorMessage = message
            errorMessage = message
            throw error
        }
    }

    private func replaceTranscript(of meeting: Meeting, with turns: [AnalysisTurn]) {
        let previousSegments = meeting.transcriptSegments
        meeting.transcriptSegments.removeAll()
        for segment in previousSegments { modelContext?.delete(segment) }
        var speakers: [String: Speaker] = [:]
        for (index, turn) in turns.enumerated() {
            var speaker: Speaker?
            if let label = turn.speaker {
                if let existing = speakers[label] ?? meeting.participants.first(where: {
                    $0.recordingVoiceLabel == label || ($0.recordingVoiceLabel == nil && $0.name == label)
                }) {
                    existing.recordingVoiceLabel = label
                    speaker = existing
                    speakers[label] = existing
                } else {
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
    }

    private func uniqueTexts(_ texts: [String]) -> [String] {
        var seen = Set<String>()
        return texts.filter { seen.insert($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted }
    }

    #if DEBUG
    
    
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
    #endif
}
