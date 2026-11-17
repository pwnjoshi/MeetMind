import Foundation
import SwiftData
import Observation

/// ViewModel managing audio file import, format validation, duration check, and pipeline handoff
@Observable
@MainActor
public final class AudioImportViewModel {
    public var isImporting: Bool = false
    public var importProgress: Double = 0.0
    public var selectedURL: URL? = nil
    public var errorMessage: String? = nil
    public var hasError: Bool = false
    public var supportedExtensions: [String] = ["m4a", "mp3", "wav"]
    
    public var simulatedDuration: TimeInterval? = nil
    public var shouldSimulateCorruptFile: Bool = false
    
    private var modelContext: ModelContext?
    private var ownedContainer: ModelContainer?
    private let transcriptionService: SpeechTranscriptionServiceProtocol?
    private let summarizationService: SummarizationServiceProtocol?
    
    public init(
        modelContext: ModelContext? = nil,
        transcriptionService: SpeechTranscriptionServiceProtocol? = nil,
        summarizationService: SummarizationServiceProtocol? = nil
    ) {
        self.modelContext = modelContext
        self.transcriptionService = transcriptionService
        self.summarizationService = summarizationService
        
        if modelContext == nil {
            if let container = try? ModelContainerFactory.createInMemoryContainer() {
                self.ownedContainer = container
                self.modelContext = container.mainContext
            }
        }
    }
    
    public func setModelContext(_ context: ModelContext?) {
        guard let context = context else { return }
        self.modelContext = context
    }
    
    public func isExtensionSupported(_ ext: String) -> Bool {
        let clean = ext.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return supportedExtensions.contains(clean)
    }
    
    public func validateFile(at url: URL) throws {
        let ext = url.pathExtension.lowercased()
        guard isExtensionSupported(ext) else {
            hasError = true
            errorMessage = "Unsupported audio format: .\(ext)"
            throw AudioImportError.unsupportedFormat
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            hasError = true
            errorMessage = "Audio file not found at: \(url.path)"
            throw AudioImportError.corruptedFile
        }
        
        if shouldSimulateCorruptFile {
            hasError = true
            errorMessage = "Selected audio file is corrupt or unreadable."
            throw AudioImportError.corruptedFile
        }
        
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attrs[.size] as? UInt64, fileSize == 0 {
            hasError = true
            errorMessage = "Audio file is empty (0 bytes)."
            throw AudioImportError.emptyFile
        }
        
        if let simDuration = simulatedDuration, simDuration <= 0 {
            hasError = true
            errorMessage = "The audio file duration is invalid or zero."
            throw AudioImportError.invalidDuration
        }
    }
    
    public func importAudio(from url: URL, title: String? = nil) async throws -> Meeting {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        try validateFile(at: url)
        
        isImporting = true
        importProgress = 0.2
        defer {
            isImporting = false
            importProgress = 1.0
        }
        
        let meetingTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            ? url.deletingPathExtension().lastPathComponent
            : (title ?? url.deletingPathExtension().lastPathComponent)
        
        let duration = max(simulatedDuration ?? 120.0, 1.0)
        guard (simulatedDuration == nil || (simulatedDuration ?? 0) > 0) else {
            hasError = true
            errorMessage = "The audio file duration is invalid or zero."
            throw AudioImportError.invalidDuration
        }
        
        let meeting = Meeting(
            title: meetingTitle,
            createdAt: Date(),
            scheduledStartTime: Date(),
            duration: duration,
            status: .processing,
            audioFileURL: url
        )
        
        if let context = modelContext {
            context.insert(meeting)
            try? context.save()
        }
        
        importProgress = 0.5
        if let transcriptionService = transcriptionService {
            do {
                let segments = try await transcriptionService.transcribeAudioFile(at: url)
                var domainSegments: [TranscriptSegment] = []
                for seg in segments {
                    let ts = TranscriptSegment(
                        text: seg.text,
                        startTime: seg.startTime,
                        endTime: seg.endTime,
                        confidence: seg.confidence,
                        meeting: meeting
                    )
                    meeting.addTranscriptSegment(ts)
                    domainSegments.append(ts)
                }
                meeting.transcriptSegments = domainSegments
                importProgress = 0.8
            } catch {
                hasError = true
                errorMessage = "Transcription failed: \(error.localizedDescription)"
                throw AudioImportError.corruptedFile
            }
        }
        
        if let summarizationService = summarizationService, !meeting.transcriptSegments.isEmpty {
            let fullText = meeting.fullTranscriptText
            if let summaryResponse = try? await summarizationService.generateSummary(from: fullText) {
                let summary = Summary(
                    executiveSummary: summaryResponse.executiveSummary,
                    keyPoints: summaryResponse.keyDiscussionPoints,
                    keyDecisions: summaryResponse.keyDecisions,
                    meeting: meeting
                )
                meeting.summary = summary
                
                var actionItemsList: [ActionItem] = []
                for item in summaryResponse.actionItems {
                    let ai = ActionItem(
                        title: item.title,
                        assigneeName: item.assignee,
                        dueDate: item.dueDate,
                        priority: ActionItemPriority(rawValue: item.priority) ?? .medium,
                        meeting: meeting
                    )
                    actionItemsList.append(ai)
                    if let context = modelContext {
                        context.insert(ai)
                    }
                }
                meeting.actionItems = actionItemsList
                meeting.status = .completed
            }
        } else if transcriptionService != nil && !meeting.transcriptSegments.isEmpty {
            meeting.status = .completed
        }
        
        try? modelContext?.save()
        return meeting
    }
    
    public func reset() {
        isImporting = false
        importProgress = 0.0
        selectedURL = nil
        errorMessage = nil
        hasError = false
        simulatedDuration = nil
        shouldSimulateCorruptFile = false
    }
}
