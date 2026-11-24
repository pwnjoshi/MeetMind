import Foundation
import SwiftData
import Observation
import OfflineEngineKit

/// Segment item displayed in the live transcript stream
public struct LiveTranscriptSegmentItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let speakerName: String
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float
    
    public init(
        id: UUID = UUID(),
        speakerName: String,
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float = 1.0
    ) {
        self.id = id
        self.speakerName = speakerName
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}

/// Note item captured during live recording
public struct NoteItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let timestamp: TimeInterval
    public let isFlagged: Bool
    
    public init(id: UUID = UUID(), text: String, timestamp: TimeInterval, isFlagged: Bool = false) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.isFlagged = isFlagged
    }
}

/// Bookmark item flagged during live recording
public struct BookmarkItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: TimeInterval
    
    public init(id: UUID = UUID(), timestamp: TimeInterval) {
        self.id = id
        self.timestamp = timestamp
    }
}

/// Speaker item for live speaker switching
public struct SpeakerItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let colorHex: String
    
    public init(id: UUID = UUID(), name: String, colorHex: String = "#3B82F6") {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

/// Photo item attached during live recording
public struct PhotoAttachmentItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let url: URL
    public let timestamp: TimeInterval
    public let isCompressed: Bool
    
    public init(id: UUID = UUID(), url: URL, timestamp: TimeInterval, isCompressed: Bool = false) {
        self.id = id
        self.url = url
        self.timestamp = timestamp
        self.isCompressed = isCompressed
    }
}

/// One note or photo captured during the current recording, shown in the live
/// "Notes & photos" list. `id` matches the persisted `Note.id`.
public struct LiveCaptureItem: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case note, photo }
    public let id: UUID
    public let kind: Kind
    public var text: String
    public let timestamp: TimeInterval
    public let photoURL: URL?

    public init(id: UUID, kind: Kind, text: String, timestamp: TimeInterval, photoURL: URL? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.timestamp = timestamp
        self.photoURL = photoURL
    }
}

/// System audio interruption type
public enum InterruptionType: Sendable, Equatable {
    case began
    case ended
}

/// Optional persistence seam used by tests and alternate local stores. The
/// default path continues to save through the injected SwiftData context.
@MainActor
public protocol RecordingMeetingSaving: AnyObject {
    func saveRecording(meeting: Meeting, audioURL: URL, duration: TimeInterval) throws
}

public enum RecordingSaveError: LocalizedError {
    case persistenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .persistenceFailed(let reason):
            return "The audio is safe on this iPhone, but the meeting could not be saved: \(reason)"
        }
    }
}

/// ViewModel powering the live recording console HUD, dynamic waveforms, notes, and transcription
@Observable
@MainActor
public final class LiveRecordingViewModel {
    public var meetingId: UUID
    public var meetingTitle: String = "Live Meeting"
    public var recordingState: RecordingState = .idle
    public var elapsedDuration: TimeInterval = 0.0
    
    public var elapsedTime: TimeInterval {
        get { elapsedDuration }
        set { elapsedDuration = newValue }
    }
    
    public var isRecording: Bool { recordingState == .recording }
    public var isPaused: Bool { recordingState == .paused }
    
    public var formattedDuration: String {
        let total = Int(elapsedDuration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    public var activeAudioRoute: String = "Built-In Microphone"
    public var audioRouteBadgeTitle: String = "Built-In Mic"
    
    public var waveformLevels: [Float] = Array(repeating: 0.05, count: 32)
    public var audioPowerLevels: [Float] {
        get { waveformLevels }
        set { waveformLevels = newValue }
    }
    
    public var interimTranscriptText: String = ""
    public var interimTranscript: String {
        get { interimTranscriptText }
        set { interimTranscriptText = newValue }
    }
    public var hasInterimText: Bool { !interimTranscriptText.isEmpty }
    
    public var finalTranscriptSegments: [LiveTranscriptSegmentItem] = []
    public var transcriptSegments: [LiveTranscriptSegmentItem] {
        get { finalTranscriptSegments }
        set { finalTranscriptSegments = newValue }
    }
    public var liveTranscriptChunks: [LiveTranscriptChunk] = []
    
    public var activeSpeaker: Speaker? = Speaker(name: "Speaker 1")
    public var activeSpeakerName: String? {
        get { activeSpeaker?.name }
        set {
            if let name = newValue {
                activeSpeaker = Speaker(name: name)
            } else {
                activeSpeaker = nil
            }
        }
    }
    
    public var availableSpeakers: [SpeakerItem] = [
        SpeakerItem(name: "Speaker 1", colorHex: "#3B82F6"),
        SpeakerItem(name: "Speaker 2", colorHex: "#10B981")
    ]
    
    public var bookmarks: [BookmarkItem] = []
    public var isBookmarkButtonHighlighted: Bool = false
    public var isBookmarkLimitReached: Bool = false
    private var lastBookmarkTimestamp: TimeInterval? = nil
    
    public var isNoteSheetPresented: Bool = false
    public var noteCaptureTimestamp: TimeInterval = 0.0
    public var capturedNotes: [NoteItem] = []
    public var notes: [NoteItem] {
        get { capturedNotes }
        set { capturedNotes = newValue }
    }
    public var notesCount: Int { capturedNotes.count }
    
    public var whiteboardPhotos: [URL] = []
    public var capturedPhotos: [PhotoAttachmentItem] = []
    public var photoAttachments: [PhotoAttachmentItem] {
        get { capturedPhotos }
        set { capturedPhotos = newValue }
    }
    public var photosCount: Int { capturedPhotos.count }

    /// Notes and photos captured in this recording only, in capture order.
    public private(set) var sessionCaptures: [LiveCaptureItem] = []
    /// Newest first, for the live "Notes & photos" list.
    public var liveCaptureFeed: [LiveCaptureItem] { Array(sessionCaptures.reversed()) }
    
    public var isShowingDiscardAlert: Bool = false
    public var showDiscardConfirmationAlert: Bool {
        get { isShowingDiscardAlert }
        set { isShowingDiscardAlert = newValue }
    }
    public var didCompleteDismissal: Bool = false
    
    public var isShowingShortRecordingAlert: Bool = false
    public var shortRecordingPrompt: String = ""
    public var shouldPromptForShortRecordingDiscard: Bool {
        elapsedDuration < 3.0
    }
    
    public var wasInterruptedBySystem: Bool = false
    public var isInterrupted: Bool = false
    public private(set) var interruptionCanResume: Bool = false
    public private(set) var pendingAudioURL: URL?
    public private(set) var recordingMetrics = RecordingMetrics()
    
    public var isUsingOnDeviceSpeechFallback: Bool = false
    public var hasOfflineIndicatorPill: Bool = false
    /// Number of durable 30-second audio windows saved while recording. These
    /// are preparation checkpoints, not a user-visible transcript.
    public private(set) var preparedAudioChunkCount: Int = 0
    public private(set) var preprocessedTranscriptChunkCount: Int = 0
    
    /// True when recording could not start because microphone access is denied.
    public var isMicrophoneUnavailable: Bool = false

    public var isShowingCameraPermissionAlert: Bool = false
    public var cameraAlertMessage: String = ""
    
    private var meeting: Meeting?
    private var modelContext: ModelContext?
    private var recordingService: AudioRecordingServiceProtocol?
    private var transcriptionService: SpeechTranscriptionServiceProtocol?
    public var errorMessage: String?
    private var sessionTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var speechTask: Task<Void, Never>?
    /// Audio-time boundary of the immutable live-caption prefix.
    private var liveTranscriptCommittedEnd: TimeInterval = 0
    private var interruptionTask: Task<Void, Never>?
    private var chunkPump: RecordingChunkPump?
    private var preprocessingWorker: RecordingPreprocessingWorker?
    private var metricsCollector = RecordingMetricsCollector()
    private let chunkPreprocessor: any RecordingChunkPreprocessing
    private var destinationAudioURL: URL?
    private var offlineLanguageCode: String? = "hi"
    private let updatesFromRecordingClock: Bool
    private var dataStore: Any?
    
    public init(
        meeting: Meeting? = nil,
        meetingId: UUID? = nil,
        modelContext: ModelContext? = nil,
        recordingService: AudioRecordingServiceProtocol? = nil,
        transcriptionService: SpeechTranscriptionServiceProtocol? = nil,
        audioService: AudioRecordingServiceProtocol? = nil,
        speechService: SpeechTranscriptionServiceProtocol? = nil,
        dataStore: Any? = nil,
        destinationAudioURL: URL? = nil,
        updatesFromRecordingClock: Bool = true,
        chunkPreprocessor: any RecordingChunkPreprocessing = PipelineRecordingChunkPreprocessor()
    ) {
        let actualMeetingId = meeting?.id ?? meetingId ?? UUID()
        self.meetingId = actualMeetingId
        self.meeting = meeting
        if let meeting = meeting {
            self.meetingTitle = meeting.title
        }
        self.modelContext = modelContext
        self.recordingService = recordingService ?? audioService
        self.transcriptionService = transcriptionService ?? speechService
        self.dataStore = dataStore
        self.destinationAudioURL = destinationAudioURL
        self.updatesFromRecordingClock = updatesFromRecordingClock
        self.chunkPreprocessor = chunkPreprocessor
    }
    
    /// The final analysis pass resolves relative dates against this day and time
    /// zone, so results prepared during recording are reusable only when they match.
    /// Without a persisted meeting there is nothing to match, so pre-analysis stays off.
    private func recordingPreAnalysisContext() -> RecordingPreAnalysisContext? {
        guard let meeting else { return nil }
        return RecordingPreAnalysisContext(
            meetingDate: meeting.scheduledStartTime ?? meeting.createdAt,
            timezone: meeting.analysisTimezone ?? TimeZone.current.identifier
        )
    }

    public func startSession() {
        guard recordingState == .idle || recordingState == .stopped || recordingState == .saved else { return }
        errorMessage = nil
        isMicrophoneUnavailable = false
        isInterrupted = false
        interruptionCanResume = false
        pendingAudioURL = nil
        metricsCollector = RecordingMetricsCollector()
        recordingMetrics = RecordingMetrics()
        guard let recordingService else {
            errorMessage = "Audio recording is unavailable. Please reopen this meeting."
            return
        }
        recordingState = .preparing
        sessionTask = Task {
            do {
                let dest = destinationAudioURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Recordings", isDirectory: true)
                    .appendingPathComponent("recording_\(meetingId.uuidString).m4a")
                try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                destinationAudioURL = dest
                try await recordingService.startRecording(destinationURL: dest)
                guard !Task.isCancelled else {
                    try recordingService.cancelRecording()
                    return
                }
                recordingState = .recording
                // Keep capture persistence transactional: the meeting is not
                // marked as owning this take until Stop validates the file.
                do {
                    try? await MeetingAnalysisPipeline.shared.discardCheckpoint(meetingID: meetingId)
                    let writer = try RollingAudioChunkWriter(meetingID: meetingId)
                    let pump = RecordingChunkPump(writer: writer, metrics: metricsCollector)
                    let worker = RecordingPreprocessingWorker(
                        chunks: pump.sealedChunks,
                        meetingID: meetingId,
                        languageCode: offlineLanguageCode,
                        preprocessor: chunkPreprocessor,
                        metrics: metricsCollector,
                        preAnalysis: recordingPreAnalysisContext()
                    )
                    chunkPump = pump
                    preprocessingWorker = worker
                    preparedAudioChunkCount = 0
                    preprocessedTranscriptChunkCount = 0
                    pump.start(draining: recordingService.audioBufferStream)
                    worker.start()
                } catch {
                    // Rolling chunks accelerate later processing. Their setup
                    // must never prevent or stop canonical capture.
                    chunkPump = nil
                    preprocessingWorker = nil
                    metricsCollector.recordWriteFailure(code: "rolling_chunk_setup_failed")
                }
                if let transcriptionService {
                    speechTask = Task { [weak self] in
                        guard await transcriptionService.requestAuthorization() == .authorized else {
                            guard !Task.isCancelled else { return }
                            self?.interimTranscriptText = "Allow Speech Recognition in iPhone Settings to see a live transcript."
                            return
                        }
                        do {
                            for try await chunk in transcriptionService.startLiveTranscription(audioBufferStream: recordingService.audioBufferStream) {
                                guard !Task.isCancelled else { break }
                                self?.receiveLiveTranscriptChunk(chunk)
                            }
                        } catch {
                            guard !Task.isCancelled else { return }
                            self?.interimTranscriptText = "Live captions couldn’t start. You can transcribe the saved recording after you finish."
                        }
                    }
                }
                meterTask = Task { [weak self] in
                    for await power in recordingService.audioMeterStream {
                        guard !Task.isCancelled else { break }
                        self?.updateWaveformLevels(with: power)
                    }
                }
                interruptionTask = Task { [weak self] in
                    for await event in recordingService.interruptionStream {
                        guard !Task.isCancelled else { break }
                        self?.receiveInterruption(event)
                    }
                }
                if updatesFromRecordingClock {
                    clockTask = Task { [weak self] in
                        while !Task.isCancelled {
                            do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
                            self?.elapsedDuration = recordingService.currentDuration
                        }
                    }
                }
            } catch {
                recordingState = .idle
                if let recordingError = error as? AudioRecordingError, recordingError == .permissionDenied {
                    isMicrophoneUnavailable = true
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Bind the routed screen to its persisted meeting before starting hardware.
    public func prepareSession(context: ModelContext, settings: SettingsViewModel? = nil) throws {
        modelContext = context
        if meeting == nil {
            let id = meetingId
            var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            meeting = try context.fetch(descriptor).first
        }
        guard let meeting else {
            throw AudioRecordingError.invalidState("This meeting no longer exists.")
        }
        meetingTitle = meeting.title
        if recordingService == nil {
            recordingService = AudioRecordingService(bitRate: settings?.audioQuality.bitRate ?? 128_000,
                                                     noiseSuppression: settings?.isNoiseSuppressionEnabled ?? false)
        }
        if transcriptionService == nil {
            transcriptionService = SpeechTranscriptionService(locale: Locale(identifier: settings?.speechLanguageLocale ?? "en-US"))
        }
        offlineLanguageCode = (settings?.savedRecordingLanguage ?? .hinglish).whisperCode
    }

    public func leaveSession() {
        sessionTask?.cancel()
        meterTask?.cancel()
        clockTask?.cancel()
        speechTask?.cancel()
        interruptionTask?.cancel()
        transcriptionService?.stopLiveTranscription()
        if recordingState == .recording || recordingState == .paused || recordingState == .interrupted {
            // Keep captured audio when leaving; it can be processed from the meeting later.
            Task {
                do { _ = try await finishSession() }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }

    public func startRecording() {
        startSession()
    }

    public func waitUntilRecordingStarted() async throws {
        if let sessionTask { await sessionTask.value }
        guard recordingState == .recording else {
            throw AudioRecordingError.recordingFailed(errorMessage ?? "Recording did not start.")
        }
    }
    
    public func startSession(for targetMeeting: Meeting) async throws {
        self.meeting = targetMeeting
        self.meetingId = targetMeeting.id
        self.meetingTitle = targetMeeting.title
        startSession()
        try await waitUntilRecordingStarted()
        targetMeeting.status = .recording
        try? modelContext?.save()
    }
    
    
    public func simulateTimerTick(seconds: Double) {
        guard recordingState == .recording else { return }
        elapsedDuration += seconds
    }
    
    
    public func simulateAudioPowerUpdate(power: Float) {
        guard recordingState == .recording else { return }
        let clamped: Float
        if !power.isFinite {
            clamped = 0.0
        } else {
            clamped = max(0.0, min(1.0, power))
        }
        if !waveformLevels.isEmpty { waveformLevels.removeLast() }
        waveformLevels.insert(clamped, at: 0)
    }
    
    
    public func updateWaveformLevels(with level: Float) {
        simulateAudioPowerUpdate(power: level)
    }
    
    public func simulateSilenceDecay() {
        waveformLevels = waveformLevels.map { max(0.02, $0 * 0.7) }
    }
    
    public func simulateRouteChange(newRoute: String) {
        activeAudioRoute = newRoute
        if newRoute.contains("AirPods") {
            audioRouteBadgeTitle = "AirPods Pro"
        } else if newRoute.contains("Headphones") {
            audioRouteBadgeTitle = "Headphones"
        } else {
            audioRouteBadgeTitle = "Built-In Mic"
        }
    }
    
    public func updateMeetingTitle(_ newTitle: String) {
        let previousTitle = meeting?.title ?? meetingTitle
        meetingTitle = newTitle
        meeting?.title = newTitle
        do { try modelContext?.save() }
        catch {
            meetingTitle = previousTitle
            meeting?.title = previousTitle
            errorMessage = "The meeting title could not be saved. Your recording continues."
        }
    }
    
    public func simulateSpeechChunk(text: String, isFinal: Bool, confidence: Float = 0.95) {
        if isFinal {
            interimTranscriptText = ""
            let speaker = activeSpeaker?.name ?? "Speaker 1"
            let start = max(0.0, elapsedDuration - 5.0)
            let seg = LiveTranscriptSegmentItem(
                speakerName: speaker,
                text: text,
                startTime: start,
                endTime: elapsedDuration,
                confidence: confidence
            )
            finalTranscriptSegments.append(seg)
            let chunk = LiveTranscriptChunk(
                text: text,
                isFinal: true,
                segments: [LiveTranscriptSegment(text: text, startTime: start, duration: 5.0, confidence: confidence)]
            )
            liveTranscriptChunks.append(chunk)
            
            if let meeting = meeting {
                let speakerModel = meeting.participants.first(where: { $0.name == speaker }) ?? Speaker(name: speaker)
                let transcriptSegment = TranscriptSegment(
                    text: text,
                    startTime: start,
                    endTime: elapsedDuration,
                    confidence: confidence,
                    speaker: speakerModel,
                    meeting: meeting
                )
                meeting.addTranscriptSegment(transcriptSegment)
                try? modelContext?.save()
            }
        } else {
            interimTranscriptText = text
        }
    }

    /// Live recognition is deliberately a preview. We retain only confirmed
    /// phrases here, then replace them with the selected-language offline
    /// transcript after the recording stops. This prevents a partial hypothesis
    /// from becoming a permanent incorrect minute or task source.
    public func receiveLiveTranscriptChunk(_ chunk: LiveTranscriptChunk) {
        let incomingText = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // CaptionAssembler uses an empty non-final chunk as an explicit mutable-tail clear.
        if !chunk.isFinal, incomingText.isEmpty {
            interimTranscriptText = ""
            return
        }
        guard !incomingText.isEmpty else { return }

        var acceptedSegments = chunk.segments
        if !acceptedSegments.isEmpty, liveTranscriptCommittedEnd > 0 {
            acceptedSegments = acceptedSegments.filter {
                ($0.startTime + $0.endTime) / 2 >= liveTranscriptCommittedEnd
            }
            // A delayed alternate recognizer or restarted request cannot alter the committed UI.
            guard !acceptedSegments.isEmpty else { return }
        }

        let acceptedText: String
        if acceptedSegments.count == chunk.segments.count || chunk.segments.isEmpty {
            acceptedText = incomingText
        } else {
            acceptedText = acceptedSegments.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !acceptedText.isEmpty else { return }

        if !chunk.isFinal {
            interimTranscriptText = acceptedText
            return
        }

        let start = acceptedSegments.map(\.startTime).min() ?? max(0, elapsedDuration - 5)
        let end = acceptedSegments.map(\.endTime).max() ?? elapsedDuration
        let confidence = acceptedSegments.map(\.confidence).min() ?? 0
        let speaker = activeSpeaker?.name ?? "Speaker"
        finalTranscriptSegments.append(LiveTranscriptSegmentItem(speakerName: speaker, text: acceptedText,
            startTime: start, endTime: max(start, end), confidence: confidence))
        let acceptedChunk = LiveTranscriptChunk(text: acceptedText, isFinal: true, segments: acceptedSegments)
        liveTranscriptChunks.append(acceptedChunk)
        if !acceptedSegments.isEmpty {
            liveTranscriptCommittedEnd = max(liveTranscriptCommittedEnd, end)
        }
        interimTranscriptText = ""
    }
    
    public func openNoteDock() {
        noteCaptureTimestamp = elapsedDuration
        isNoteSheetPresented = true
    }
    
    public func saveNote(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isNoteSheetPresented = false
            return
        }
        isNoteSheetPresented = false
        let noteID = UUID()
        let noteItem = NoteItem(id: noteID, text: text, timestamp: noteCaptureTimestamp, isFlagged: false)
        capturedNotes.append(noteItem)
        sessionCaptures.append(LiveCaptureItem(id: noteID, kind: .note, text: trimmed, timestamp: noteCaptureTimestamp))
        
        if let meeting = meeting {
            let note = Note(id: noteID, content: text, timestamp: noteCaptureTimestamp, meeting: meeting)
            meeting.addNote(note)
            try? modelContext?.save()
        }
    }
    
    public func addLiveNote(text: String) {
        noteCaptureTimestamp = elapsedDuration
        saveNote(text: text)
    }
    
    
    public func addBookmark() {
        if bookmarks.count >= 100 {
            isBookmarkLimitReached = true
            return
        }
        if let lastTime = lastBookmarkTimestamp, abs(elapsedDuration - lastTime) < 1.0 {
            return
        }
        lastBookmarkTimestamp = elapsedDuration
        let b = BookmarkItem(timestamp: elapsedDuration)
        bookmarks.append(b)
        bookmarks.sort { $0.timestamp < $1.timestamp }
        isBookmarkButtonHighlighted = true
        
        if let meeting = meeting {
            let note = Note(content: "Bookmark", timestamp: elapsedDuration, isBookmark: true, meeting: meeting)
            meeting.addNote(note)
            try? modelContext?.save()
        }
    }
    
    
    public func resetBookmarkHighlight() {
        isBookmarkButtonHighlighted = false
    }
    
    public func switchSpeaker(to name: String) {
        activeSpeaker = Speaker(name: name)
        if !availableSpeakers.contains(where: { $0.name == name }) {
            availableSpeakers.append(SpeakerItem(name: name))
        }
    }
    
    public func switchActiveSpeaker(to speaker: Speaker) {
        activeSpeaker = speaker
        if !availableSpeakers.contains(where: { $0.name == speaker.name }) {
            availableSpeakers.append(SpeakerItem(name: speaker.name, colorHex: speaker.avatarColorHex))
        }
    }
    
    public func switchActiveSpeaker(to name: String) {
        switchSpeaker(to: name)
    }
    
    public func clearActiveSpeaker() {
        activeSpeaker = nil
    }
    
    public func addNewSpeaker(name: String, colorHex: String = "#3B82F6") {
        let speaker = SpeakerItem(name: name, colorHex: colorHex)
        availableSpeakers.append(speaker)
        activeSpeaker = Speaker(name: name, avatarColorHex: colorHex)
    }
    
    public func attachPhoto(url: URL, originalSizeBytes: Int? = nil, caption: String = "") {
        let isCompressed = (originalSizeBytes ?? 0) > 10 * 1024 * 1024
        let photoID = UUID()
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = PhotoAttachmentItem(id: photoID, url: url, timestamp: elapsedDuration, isCompressed: isCompressed)
        capturedPhotos.append(item)
        whiteboardPhotos.append(url)
        sessionCaptures.append(LiveCaptureItem(id: photoID, kind: .photo, text: trimmedCaption,
                                               timestamp: elapsedDuration, photoURL: url))
        if let meeting = meeting {
            let content = trimmedCaption.isEmpty ? "Whiteboard photo: \(url.lastPathComponent)" : trimmedCaption
            let note = Note(id: photoID, content: content, timestamp: elapsedDuration, imageAttachmentPath: url.path, meeting: meeting)
            meeting.addNote(note)
            try? modelContext?.save()
        }
    }
    
    public func captureWhiteboardPhoto(data: Data, caption: String = "") {
        let filename = "whiteboard_\(UUID().uuidString).jpg"
        do {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Attachments", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            attachPhoto(url: url, originalSizeBytes: data.count, caption: caption)
        } catch { errorMessage = error.localizedDescription }
    }
    
    /// Edits the text of a note, or the caption of a photo, captured in this recording.
    public func updateCapture(id: UUID, text: String) {
        guard let index = sessionCaptures.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = sessionCaptures[index]
        if item.kind == .note && trimmed.isEmpty { return }
        sessionCaptures[index].text = trimmed
        if let noteIndex = capturedNotes.firstIndex(where: { $0.id == id }) {
            let old = capturedNotes[noteIndex]
            capturedNotes[noteIndex] = NoteItem(id: old.id, text: trimmed, timestamp: old.timestamp, isFlagged: old.isFlagged)
        }
        if let note = meeting?.notes.first(where: { $0.id == id }) {
            if item.kind == .photo && trimmed.isEmpty, let url = item.photoURL {
                note.content = "Whiteboard photo: \(url.lastPathComponent)"
            } else {
                note.content = trimmed
            }
            try? modelContext?.save()
        }
    }

    /// Removes a note or photo captured in this recording, including the photo file.
    public func deleteCapture(id: UUID) {
        guard let item = sessionCaptures.first(where: { $0.id == id }) else { return }
        sessionCaptures.removeAll { $0.id == id }
        capturedNotes.removeAll { $0.id == id }
        if let url = item.photoURL {
            capturedPhotos.removeAll { $0.id == id }
            whiteboardPhotos.removeAll { $0 == url }
            try? FileManager.default.removeItem(at: url)
        }
        if let meeting, let note = meeting.notes.first(where: { $0.id == id }) {
            meeting.notes.removeAll { $0.id == id }
            modelContext?.delete(note)
            try? modelContext?.save()
        }
    }

    
    public func handleCameraPermissionDenied() {
        isShowingCameraPermissionAlert = true
        cameraAlertMessage = "Camera access is required to capture whiteboards."
    }
    
    public func pauseSession() {
        guard recordingState == .recording, let recordingService else { return }
        do {
            try recordingService.pauseRecording()
            recordingState = .paused
            waveformLevels = Array(repeating: 0.05, count: 32)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    public func pause() {
        pauseSession()
    }
    
    public func pauseRecording() {
        pauseSession()
    }
    
    public func resumeSession() {
        guard recordingState == .paused || (recordingState == .interrupted && interruptionCanResume),
              let recordingService else { return }
        do {
            try recordingService.resumeRecording()
            recordingState = .recording
            isInterrupted = false
            interruptionCanResume = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    public func resume() {
        resumeSession()
    }
    
    public func resumeRecording() {
        resumeSession()
    }

    public func receiveInterruption(_ event: RecordingInterruptionEvent) {
        wasInterruptedBySystem = true
        isInterrupted = true
        recordingState = .interrupted
        interruptionCanResume = event.hasEnded && event.canResume
        waveformLevels = Array(repeating: 0.05, count: 32)
        metricsCollector.recordInterruption(code: event.code.rawValue)
        syncMetrics()
    }
    
    public func handleAudioSessionInterruption(began: Bool) {
        receiveInterruption(RecordingInterruptionEvent(
            code: .audioSession,
            canResume: !began,
            hasEnded: !began
        ))
    }
    
    
    public func simulateNetworkDrop() {
        isUsingOnDeviceSpeechFallback = true
        hasOfflineIndicatorPill = true
    }
    
    public func simulateAppDidEnterBackground() {}
    public func simulateAppWillEnterForeground() {}
    
    public func isDurationUnderThreshold(seconds: Double) -> Bool {
        return elapsedDuration < seconds
    }
    
    public func requestStop() {
        if isDurationUnderThreshold(seconds: 3.0) {
            isShowingShortRecordingAlert = true
            shortRecordingPrompt = "Recording is very short (\(String(format: "%.1f", elapsedDuration))s). Save or Discard?"
        }
    }
    
    public func stopSession() async throws -> URL {
        try await finishSession()
    }
    
    public func finishSession() async throws -> URL {
        if recordingState == .saveFailed || recordingState == .stoppedUnsaved {
            return try retrySave()
        }
        if let sessionTask { await sessionTask.value }
        guard let service = recordingService else {
            throw AudioRecordingError.invalidState("No audio recorder is active.")
        }

        let stopStarted = Date()
        elapsedDuration = service.currentDuration
        metricsCollector.recordElapsed(elapsedDuration)
        recordingState = .stopping
        preprocessingWorker?.cancel()
        preprocessingWorker = nil

        let url: URL
        do {
            url = try await service.stopRecording()
            pendingAudioURL = url
        } catch {
            pendingAudioURL = destinationAudioURL
            recordingState = .stoppedUnsaved
            metricsCollector.recordWriteFailure(code: "canonical_stop_failed")
            metricsCollector.recordStopLatency(Date().timeIntervalSince(stopStarted))
            syncMetrics()
            throw error
        }

        meterTask?.cancel()
        clockTask?.cancel()
        speechTask?.cancel()
        interruptionTask?.cancel()
        transcriptionService?.stopLiveTranscription()

        // The pump only waits for buffer-to-disk writes. Its inference consumer
        // was cancelled above and is deliberately not awaited.
        if let chunkPump {
            do {
                let chunks = try await chunkPump.finishAfterSourceEnds()
                preparedAudioChunkCount = chunks.count
            } catch {
                metricsCollector.recordWriteFailure(code: "rolling_chunk_finish_failed")
            }
        }
        preprocessedTranscriptChunkCount = metricsCollector.snapshot.preprocessedChunkCount

        do {
            let info = try CanonicalRecordingValidator.validate(url)
            metricsCollector.recordCanonicalAudio(frameCount: info.frameCount, duration: info.duration)
        } catch {
            recordingState = .stoppedUnsaved
            metricsCollector.recordWriteFailure(code: canonicalValidationCode(for: error))
            metricsCollector.recordStopLatency(Date().timeIntervalSince(stopStarted))
            syncMetrics()
            throw error
        }

        recordingState = .stoppedUnsaved
        do {
            try persistStoppedRecording(url)
            recordingState = .saved
            metricsCollector.recordStopLatency(Date().timeIntervalSince(stopStarted))
            syncMetrics()
            metricsCollector.logSummary()
            return url
        } catch {
            recordingState = .saveFailed
            metricsCollector.recordStopLatency(Date().timeIntervalSince(stopStarted))
            syncMetrics()
            throw RecordingSaveError.persistenceFailed(error.localizedDescription)
        }
    }

    /// Retries only meeting persistence. The recorder is never restarted and
    /// the previously validated canonical URL remains intact.
    public func retrySave() throws -> URL {
        guard let url = pendingAudioURL else {
            throw AudioRecordingError.invalidState("There is no stopped recording to save.")
        }
        recordingState = .stopping
        do {
            let info = try CanonicalRecordingValidator.validate(url)
            metricsCollector.recordCanonicalAudio(frameCount: info.frameCount, duration: info.duration)
            try persistStoppedRecording(url)
            recordingState = .saved
            syncMetrics()
            metricsCollector.logSummary()
            return url
        } catch let error as CanonicalRecordingValidationError {
            recordingState = .stoppedUnsaved
            metricsCollector.recordWriteFailure(code: canonicalValidationCode(for: error))
            syncMetrics()
            throw error
        } catch {
            recordingState = .saveFailed
            throw RecordingSaveError.persistenceFailed(error.localizedDescription)
        }
    }

    private func persistStoppedRecording(_ url: URL) throws {
        guard let meeting else { return }
        meeting.setAudioFileURL(url)
        meeting.duration = elapsedDuration
        meeting.status = .processing
        if let saver = dataStore as? RecordingMeetingSaving {
            try saver.saveRecording(meeting: meeting, audioURL: url, duration: elapsedDuration)
        } else {
            try modelContext?.save()
        }
    }

    private func canonicalValidationCode(for error: Error) -> String {
        switch error as? CanonicalRecordingValidationError {
        case .fileMissing: return "canonical_file_missing"
        case .unreadableAudio: return "canonical_file_unreadable"
        case .emptyAudio: return "canonical_file_empty"
        case .invalidDuration: return "canonical_duration_invalid"
        case nil: return "canonical_validation_failed"
        }
    }

    private func syncMetrics() {
        recordingMetrics = metricsCollector.snapshot
    }
    
    
    public func requestDiscard() {
        isShowingDiscardAlert = true
    }
    
    public func cancelDiscard() {
        isShowingDiscardAlert = false
    }
    
    public func confirmDiscard(for targetMeeting: Meeting? = nil) {
        sessionTask?.cancel()
        meterTask?.cancel()
        clockTask?.cancel()
        speechTask?.cancel()
        interruptionTask?.cancel()
        preprocessingWorker?.cancel()
        chunkPump?.cancelAndDiscard()
        transcriptionService?.stopLiveTranscription()
        isShowingDiscardAlert = false
        recordingState = .idle
        try? recordingService?.cancelRecording()
        chunkPump = nil
        preprocessingWorker = nil
        pendingAudioURL = nil
        preparedAudioChunkCount = 0
        preprocessedTranscriptChunkCount = 0
        elapsedDuration = 0
        finalTranscriptSegments.removeAll()
        capturedNotes.removeAll()
        sessionCaptures.removeAll()
        bookmarks.removeAll()
        capturedPhotos.removeAll()
        didCompleteDismissal = true
        
        // Deleting is permanent: remove the audio file and attached photos too.
        let fileManager = FileManager.default
        if let url = destinationAudioURL { try? fileManager.removeItem(at: url) }
        for photoURL in whiteboardPhotos { try? fileManager.removeItem(at: photoURL) }
        if let audioURL = (targetMeeting ?? meeting)?.resolvedAudioFileURL { try? fileManager.removeItem(at: audioURL) }
        whiteboardPhotos.removeAll()

        let toDelete = targetMeeting ?? meeting ?? (modelContext != nil ? try? modelContext?.fetch(FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })).first : nil)
        if let m = toDelete {
            modelContext?.delete(m)
            try? modelContext?.save()
        }
    }
    
    
}
