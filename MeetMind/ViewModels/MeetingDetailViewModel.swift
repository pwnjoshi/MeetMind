import Foundation
import SwiftData
import Observation
import OfflineEngineKit

public typealias LocalQuestionAnswerer = @Sendable (String, [AnalysisTurn]) async throws -> [SupportedPoint]

/// Segmented tabs available in the meeting detail cockpit
public enum MeetingDetailTab: String, CaseIterable, Sendable {
    case summary = "summary"
    case transcript = "transcript"
    case actionItems = "actionItems"
    case notesMedia = "notesMedia"
    
    public var title: String {
        switch self {
        case .summary: return "Summary"
        case .transcript: return "Transcript"
        case .actionItems: return "Action Items"
        case .notesMedia: return "Notes & Media"
        }
    }
}

/// Toolbar actions menu options in meeting cockpit
public enum MeetingDetailAction: String, CaseIterable, Sendable {
    case exportMinutes = "exportMinutes"
    case share = "share"
    case rename = "rename"
    case delete = "delete"
}

/// Formats available for minutes export
public enum ExportFormat: String, Sendable {
    case pdf = "pdf"
    case markdownText = "markdownText"
    case plainText = "plainText"
}

/// Grounded AI citation with precise timestamp
public struct AICitation: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: TimeInterval
    public let formattedTimecode: String
    public let snippet: String
    
    public init(id: UUID = UUID(), timestamp: TimeInterval, formattedTimecode: String, snippet: String = "") {
        self.id = id
        self.timestamp = timestamp
        self.formattedTimecode = formattedTimecode
        self.snippet = snippet
    }
    
    public init(id: UUID = UUID(), timestamp: TimeInterval, segmentText: String = "", formattedTimecode: String? = nil, snippet: String = "") {
        self.id = id
        self.timestamp = timestamp
        self.snippet = snippet.isEmpty ? segmentText : snippet
        let min = Int(timestamp) / 60
        let sec = Int(timestamp) % 60
        self.formattedTimecode = formattedTimecode ?? String(format: "%02d:%02d", min, sec)
    }
}

/// Structured Ask AI answer with timecode citations
public struct AIAnswerResponse: Sendable, Equatable {
    public let answer: String
    public var text: String { answer }
    public let citations: [AICitation]
    
    public init(answer: String, citations: [AICitation] = []) {
        self.answer = answer
        self.citations = citations
    }
    
    public init(text: String, citations: [AICitation] = []) {
        self.answer = text
        self.citations = citations
    }
}

public typealias AIResponse = AIAnswerResponse

/// Email draft output for executive distribution
public struct EmailDraft: Sendable, Equatable {
    public let subject: String
    public let body: String
    
    public init(subject: String, body: String) {
        self.subject = subject
        self.body = body
    }
}

/// ViewModel coordinating meeting cockpit tabs, playback synchronization, transcript editing, AI Q&A, and exports
@Observable
@MainActor
public final class MeetingDetailViewModel {
    private let questionAnswerer: LocalQuestionAnswerer
    private var questionTask: Task<Void, Never>?
    public var isAnsweringQuestion = false
    public var isSyncingReminders = false
    public var meeting: Meeting?
    public var selectedTab: MeetingDetailTab = .summary
    
    public var headerTitle: String {
        meeting?.title ?? "Meeting Detail"
    }
    
    public var headerDurationText: String {
        meeting?.formattedDuration ?? "00:00"
    }
    
    public var statusBadgeTitle: String {
        meeting?.status.displayName ?? "Scheduled"
    }
    
    public var statusBadgeColorHex: String {
        meeting?.status.badgeColorHex ?? "#3B82F6"
    }
    
    public var availableToolbarActions: [MeetingDetailAction] = [.exportMinutes, .share, .rename, .delete]
    
    public var summary: Summary? {
        meeting?.summary
    }
    
    public var summaryText: String {
        summary?.executiveSummary ?? ""
    }
    
    public var keyDiscussionPoints: [String] {
        summary?.keyPoints ?? []
    }
    
    public var keyDecisions: [String] {
        summary?.keyDecisions ?? []
    }
    
    private var internalSegments: [TranscriptSegment]? = nil
    
    public var transcriptSegments: [TranscriptSegment] {
        get {
            if let custom = internalSegments {
                return custom
            }
            return meeting?.orderedTranscriptSegments ?? []
        }
        set {
            internalSegments = newValue
        }
    }
    
    public var filteredTranscriptSegments: [TranscriptSegment] = []
    public var activeSegmentId: UUID? = nil
    
    public var isEditingTranscript: Bool = false
    public var editingSegmentText: String = ""
    public var editingSegmentId: UUID? = nil
    
    public var actionItems: [ActionItem] {
        meeting?.actionItems ?? []
    }
    
    public var notes: [Note] {
        meeting?.notes ?? []
    }
    
    private static var sessionPlaybackRate: Float = 1.0
    
    public var playbackRate: Float {
        get {
            playbackService?.playbackRate ?? Self.sessionPlaybackRate
        }
        set {
            Self.sessionPlaybackRate = newValue
            playbackService?.playbackRate = newValue
        }
    }
    
    private var _isPlayingInternal: Bool = false
    public var isPlaying: Bool {
        get { playbackService?.isPlaying ?? _isPlayingInternal }
        set {
            _isPlayingInternal = newValue
            if newValue {
                try? playbackService?.play()
            } else {
                playbackService?.pause()
            }
        }
    }
    
    public var playbackTime: TimeInterval = 0.0
    
    public var currentPlayheadTime: TimeInterval {
        playbackService?.currentTime ?? playbackTime
    }
    
    public var totalDuration: TimeInterval {
        meeting?.duration ?? 300.0
    }
    
    public var playbackProgressRatio: Double {
        guard totalDuration > 0 else { return 0.0 }
        return playbackTime / totalDuration
    }
    
    public var currentTimeFormatted: String {
        formatTimestamp(playbackTime)
    }
    
    public var remainingTimeFormatted: String {
        let remaining = max(0.0, totalDuration - playbackTime)
        return "-" + formatTimestamp(remaining)
    }
    
    public var audioMissingMessage: String = "Audio recording file is unavailable."
    public var isShowingAudioMissingAlert: Bool = false
    
    public var emptySummaryPlaceholder: String = "Summary not yet generated."
    public var hasEmptySummary: Bool {
        guard let s = meeting?.summary else { return true }
        return s.executiveSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public var isShowingSpeakerReassignmentSheet: Bool = false
    public var speakerToReassign: String = ""
    
    public var isShowingAskAISheet: Bool = false
    public var suggestedPromptChips: [String] = [
        "What decisions were made?",
        "What action items were assigned?",
        "What was the main topic discussed?"
    ]
    
    public var emptyPhotosMessage: String = "No whiteboard photos attached."
    public var galleryPhotos: [Note] {
        meeting?.notes.filter { $0.hasImage } ?? []
    }
    public var galleryNotes: [Note] {
        meeting?.notes.filter { !$0.hasImage } ?? []
    }
    
    public var aiChatHistory: [(prompt: String, response: AIAnswerResponse)] = []
    
    private var originalSegmentTexts: [UUID: String] = [:]
    private var modelContext: ModelContext?
    private let playbackService: AudioPlaybackServiceProtocol?
    private let summarizationService: SummarizationServiceProtocol?
    private let exportService: ExportServiceProtocol?
    private let remindersService: RemindersSyncServiceProtocol?
    private var dataStore: Any?
    
    public init(
        meeting: Meeting? = nil,
        meetingId: UUID? = nil,
        modelContext: ModelContext? = nil,
        playbackService: AudioPlaybackServiceProtocol? = nil,
        summarizationService: SummarizationServiceProtocol? = nil,
        exportService: ExportServiceProtocol? = nil,
        remindersService: RemindersSyncServiceProtocol? = nil,
        questionAnswerer: LocalQuestionAnswerer? = nil,
        dataStore: Any? = nil
    ) {
        self.meeting = meeting
        self.questionAnswerer = questionAnswerer ?? { question, turns in
            try await MeetingAnalysisPipeline.shared.answer(question: question, turns: turns, model: VidurModel.selected)
        }
        self.modelContext = modelContext
        self.playbackService = playbackService ?? AudioPlaybackService()
        self.summarizationService = summarizationService ?? NaturalLanguageSummarizationService()
        self.exportService = exportService ?? ExportService()
        self.remindersService = remindersService
        self.dataStore = dataStore
        
        self.playbackRate = Self.sessionPlaybackRate
        
        if self.meeting == nil, let context = modelContext, let id = meetingId {
            var desc = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
            desc.fetchLimit = 1
            self.meeting = try? context.fetch(desc).first
        }
        
        if let meeting = self.meeting, let audioURL = meeting.resolvedAudioFileURL {
            try? self.playbackService?.loadAudio(url: audioURL)
        }
    }
    
    public func loadMeeting() {
        if let meeting = meeting {
            self.transcriptSegments = meeting.orderedTranscriptSegments
        }
    }
    
    public func selectTab(_ tab: MeetingDetailTab) {
        selectedTab = tab
    }
    
    public func renameMeeting(newTitle: String) {
        meeting?.title = newTitle
        try? modelContext?.save()
    }
    
    public func generateCopyableSummaryText() -> String {
        guard let summary = summary else { return "No summary available." }
        var result = "Executive Summary:\n\(summary.executiveSummary)\n\n"
        if !summary.keyPoints.isEmpty {
            result += "Key Points:\n" + summary.keyPoints.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if !summary.keyDecisions.isEmpty {
            result += "Key Decisions:\n" + summary.keyDecisions.map { "- \($0)" }.joined(separator: "\n")
        }
        return result
    }
    
    public func regenerateSummary(completion: @escaping (Result<Summary, Error>) -> Void) {
        Task {
            do {
                let updated = try await regenerateSummary()
                completion(.success(updated))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    public func regenerateSummary() async throws -> Summary {
        guard let summarizationService = summarizationService else {
            throw SummarizationError.serviceUnavailable
        }
        let transcriptText = meeting?.fullTranscriptText ?? ""
        let response = try await summarizationService.generateSummary(from: transcriptText)
        
        let newSummary: Summary
        if let existing = meeting?.summary {
            existing.executiveSummary = response.executiveSummary
            existing.keyPoints = response.keyDiscussionPoints
            existing.keyDecisions = response.keyDecisions
            newSummary = existing
        } else {
            newSummary = Summary(
                executiveSummary: response.executiveSummary,
                keyPoints: response.keyDiscussionPoints,
                keyDecisions: response.keyDecisions,
                meeting: meeting
            )
            meeting?.summary = newSummary
        }
        try? modelContext?.save()
        return newSummary
    }
    
    public func updatePlaybackTime(_ time: TimeInterval) {
        self.playbackTime = time
        if let active = transcriptSegments.first(where: { time >= $0.startTime && time < $0.endTime }) {
            activeSegmentId = active.id
        }
    }
    
    public func beginScrubbing() {
        if isPlaying {
            playbackService?.pause()
            _isPlayingInternal = false
        }
    }
    
    public func endScrubbing() {
        playbackService?.seek(to: playbackTime)
    }
    
    public func updateScrubPosition(ratio: Double) {
        let clampedRatio = max(0.0, min(1.0, ratio))
        playbackTime = clampedRatio * totalDuration
        playbackService?.seek(to: playbackTime)
    }
    
    public func skipForward(seconds: Double = 15.0) {
        let target = playbackTime + seconds
        if target >= totalDuration {
            playbackTime = totalDuration
            playbackService?.seek(to: totalDuration)
            if isPlaying {
                playbackService?.pause()
                _isPlayingInternal = false
            }
        } else {
            playbackTime = target
            playbackService?.seek(to: target)
        }
    }
    
    public func skipBackward(seconds: Double = 15.0) {
        let target = max(0.0, playbackTime - seconds)
        playbackTime = target
        playbackService?.seek(to: target)
    }
    
    public func cyclePlaybackSpeed() {
        let rates: [Float] = [1.0, 1.25, 1.5, 2.0, 0.75]
        let current = playbackRate
        if let idx = rates.firstIndex(of: current) {
            let next = rates[(idx + 1) % rates.count]
            setPlaybackRate(next)
        } else {
            setPlaybackRate(1.0)
        }
    }
    
    public func handleAudioPlaybackDidFinish() {
        playbackTime = 0.0
        playbackService?.seek(to: 0.0)
        playbackService?.pause()
        _isPlayingInternal = false
    }
    
    public func filterTranscript(by query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            filteredTranscriptSegments = []
        } else {
            filteredTranscriptSegments = transcriptSegments.filter { $0.text.lowercased().contains(trimmed) }
        }
    }
    
    public func tapToSeek(segment: TranscriptSegment) {
        if meeting?.audioFileURL == nil {
            isShowingAudioMissingAlert = true
            return
        }
        let targetTime = min(segment.startTime, totalDuration)
        playbackTime = targetTime
        activeSegmentId = segment.id
        playbackService?.seek(to: targetTime)
        try? playbackService?.play()
        _isPlayingInternal = true
    }
    
    public func seek(to time: TimeInterval) {
        let clamped = max(0.0, min(time, totalDuration))
        playbackTime = clamped
        playbackService?.seek(to: clamped)
        updatePlaybackTime(clamped)
    }
    
    public func togglePlayPause() {
        if isPlaying {
            playbackService?.pause()
            _isPlayingInternal = false
        } else {
            try? playbackService?.play()
            _isPlayingInternal = true
        }
    }

    public func refreshPlaybackPosition() {
        guard let playbackService else { return }
        updatePlaybackTime(playbackService.currentTime)
        _isPlayingInternal = playbackService.isPlaying
    }

    public func stopPlayback() { playbackService?.pause() }

    public func syncReviewedTasksToReminders() async throws {
        guard !isSyncingReminders, let meeting else { return }
        let items = meeting.actionItems.filter { !$0.isCompleted }
        guard !items.isEmpty else { return }
        isSyncingReminders = true
        defer { isSyncingReminders = false }
        let service = remindersService ?? SystemRemindersSyncService()
        let ids = try await service.syncActionItems(items, toList: "MeetMind")
        guard ids.count == items.count else {
            throw OfflineError.unavailable("Some confirmed tasks could not be synced. Please retry.")
        }
        for (item, id) in zip(items, ids) { item.reminderIdentifier = id }
        try modelContext?.save()
    }

    public func deleteMeeting() throws {
        guard let meeting, let modelContext else { return }
        playbackService?.stop()
        let id = meeting.id
        modelContext.delete(meeting)
        try modelContext.save()
        Task { try? await MeetingAnalysisPipeline.shared.discardCheckpoint(meetingID: id) }
    }
    
    public func setPlaybackRate(_ rate: Float) {
        self.playbackRate = rate
    }
    
    public func beginEditingTranscript(segment: TranscriptSegment) {
        isEditingTranscript = true
        editingSegmentText = segment.text
        editingSegmentId = segment.id
        originalSegmentTexts[segment.id] = segment.text
    }
    
    @discardableResult
    public func saveTranscriptEdit(newText: String) -> Bool {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isEditingTranscript = false
            editingSegmentId = nil
            return false
        }
        if let id = editingSegmentId, let segment = transcriptSegments.first(where: { $0.id == id }) {
            segment.updateText(trimmed)
            try? modelContext?.save()
        }
        isEditingTranscript = false
        editingSegmentId = nil
        return true
    }
    
    public func cancelTranscriptEdit() {
        isEditingTranscript = false
        editingSegmentId = nil
    }
    
    public func undoTranscriptEdit(segmentId: UUID) {
        if let original = originalSegmentTexts[segmentId],
           let segment = transcriptSegments.first(where: { $0.id == segmentId }) {
            segment.text = original
            segment.isEdited = false
            try? modelContext?.save()
        }
    }
    
    public func saveInlineTranscriptEdit(segmentId: UUID, newText: String) {
        if let segment = transcriptSegments.first(where: { $0.id == segmentId }) {
            segment.updateText(newText)
            try? modelContext?.save()
        }
    }
    
    public func openSpeakerReassignment(forSpeakerName: String) {
        speakerToReassign = forSpeakerName
        isShowingSpeakerReassignmentSheet = true
    }
    
    public func cancelSpeakerReassignment() {
        isShowingSpeakerReassignmentSheet = false
    }
    
    public func reassignSpeaker(from oldName: String, to newName: String) {
        let newSpeaker = Speaker(name: newName)
        if let context = modelContext {
            context.insert(newSpeaker)
        }
        for segment in transcriptSegments where segment.speakerName == oldName || segment.speaker?.name == oldName {
            segment.speaker = newSpeaker
        }
        try? modelContext?.save()
    }
    
    public func reassignSpeaker(from oldSpeaker: Speaker, to newSpeaker: Speaker) {
        for segment in transcriptSegments where segment.speaker?.id == oldSpeaker.id {
            segment.speaker = newSpeaker
        }
        try? modelContext?.save()
    }
    
    public func reassignSpeaker(segment: TranscriptSegment, newSpeaker: Speaker) {
        segment.speaker = newSpeaker
        try? modelContext?.save()
    }
    
    public func setTranscriptSegments(_ segments: [TranscriptSegment]) {
        for seg in segments {
            if seg.speaker == nil {
                seg.speaker = Speaker(name: "Speaker 1")
            }
        }
        self.transcriptSegments = segments
        self.meeting?.transcriptSegments = segments
        try? modelContext?.save()
    }
    
    public func toggleActionItemCompletion(_ item: ActionItem) {
        item.toggleCompleted()
        try? modelContext?.save()
    }
    
    public func exportPDF() throws -> Data {
        guard let meeting = meeting else { throw ExportError.emptyMeetingData }
        if let exportService = exportService {
            return try exportService.generatePDFReport(for: meeting)
        }
        return Data("MeetMind PDF Report".utf8)
    }
    
    public func exportMarkdown() -> String {
        guard let meeting = meeting else { return "" }
        if let exportService = exportService {
            return exportService.generateMarkdown(for: meeting)
        }
        return "# \(meeting.title)\n\n\(generateCopyableSummaryText())"
    }
    
    public func exportPlainText() -> String {
        guard let meeting = meeting else { return "" }
        if let exportService = exportService {
            return exportService.generatePlainText(for: meeting)
        }
        return "MEETING MINUTES\nTITLE: \(meeting.title)\n\n\(generateCopyableSummaryText())"
    }
    
    public func exportMeeting(as format: ExportFormat) throws -> Data {
        switch format {
        case .pdf:
            return try exportPDF()
        case .markdownText:
            return Data(exportMarkdown().utf8)
        case .plainText:
            return Data(exportPlainText().utf8)
        }
    }
    
    public func exportMeeting(as format: ExportFormat) throws -> String {
        switch format {
        case .pdf:
            throw ExportError.pdfGenerationFailed("PDF export returns Data, not String")
        case .markdownText:
            return exportMarkdown()
        case .plainText:
            return exportPlainText()
        }
    }
    
    public func openAskAISheet() {
        isShowingAskAISheet = true
    }
    
    public func canSubmitAIQuery(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public func submitAIQuery(_ query: String, completion: @escaping @MainActor (AIAnswerResponse) -> Void) {
        guard !isAnsweringQuestion, canSubmitAIQuery(query) else { return }
        isAnsweringQuestion = true
        questionTask = Task { @MainActor in
            defer { isAnsweringQuestion = false }
            do { completion(try await askAI(prompt: query)) }
            catch is CancellationError { }
            catch {
                let response = AIAnswerResponse(answer: error.localizedDescription, citations: [])
                aiChatHistory.append((prompt: query, response: response))
                completion(response)
            }
        }
    }

    public func cancelQuestion() {
        questionTask?.cancel()
    }

    public func askAI(prompt: String) async throws -> AIAnswerResponse {
        let turns = transcriptSegments.enumerated().map { index, segment in
            AnalysisTurn(id: "t\(index + 1)", text: segment.text, start: segment.startTime,
                         end: segment.endTime, speaker: segment.speaker?.name)
        }
        let points = try await questionAnswerer(prompt, turns)
        try Task.checkCancellation()
        var citations: [AICitation] = []
        var seen = Set<String>()
        for point in points {
            guard !point.evidence.isEmpty else { throw OfflineError.unavailable("The answer lacked transcript evidence. Please retry.") }
            for evidence in point.evidence {
                guard !evidence.quote.isEmpty, let turn = turns.first(where: {
                    (evidence.turnID == $0.id || evidence.turnID.hasPrefix($0.id + ".")) && $0.text.contains(evidence.quote)
                }) else { throw OfflineError.unavailable("The answer contained invalid transcript evidence. Please retry.") }
                if seen.insert(evidence.turnID + evidence.quote).inserted {
                    citations.append(AICitation(timestamp: turn.start, segmentText: evidence.quote))
                }
            }
        }
        let response = AIAnswerResponse(answer: points.isEmpty ? "Not discussed in this meeting." : points.map(\.text).joined(separator: "\n"), citations: citations)
        aiChatHistory.append((prompt: prompt, response: response))
        return response
    }

    public func seekToCitation(_ citation: AICitation) {
        seek(to: citation.timestamp)
        try? playbackService?.play()
    }
    
    public func tapCitation(_ citation: AICitation) {
        seekToCitation(citation)
    }
    
    public func clearGalleryPhotos() {
        if let photos = meeting?.notes.filter({ $0.hasImage }) {
            for p in photos {
                modelContext?.delete(p)
            }
            meeting?.notes.removeAll { $0.hasImage }
            try? modelContext?.save()
        }
    }
    
    public func clampZoomScale(_ scale: CGFloat) -> CGFloat {
        max(1.0, min(5.0, scale))
    }
    
    public func formatTimestamp(_ time: TimeInterval) -> String {
        let total = Int(max(0, time))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 || totalDuration >= 3600 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    public func simulateNilSummary() {
        meeting?.summary = nil
    }
    
    public func simulateEmptySummaryText() {
        meeting?.summary?.executiveSummary = ""
    }
    
    public func simulateMissingAudioFile() {
        meeting?.audioFileURL = nil
        isShowingAudioMissingAlert = true
    }
    
    public func renderMarkdownSummary(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
    }
    
    public func generateEmailDraft() -> EmailDraft {
        let title = meeting?.title ?? "Meeting"
        let subject = "[MeetMind Minutes] \(title)"
        var body = "Hi Team,\n\nHere are the minutes from \(title):\n\n"
        if let summary = summary {
            body += "Executive Summary:\n\(summary.executiveSummary)\n\n"
            if !summary.keyDecisions.isEmpty {
                body += "Key Decisions:\n" + summary.keyDecisions.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
            }
        }
        if !actionItems.isEmpty {
            body += "Action Items:\n"
            for item in actionItems {
                body += "- \(item.title) (Assignee: \(item.assigneeName))\n"
            }
        }
        return EmailDraft(subject: subject, body: body)
    }
}
