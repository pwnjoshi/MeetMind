import Foundation
import SwiftData
import Observation
import AVFoundation

public typealias TemplatePreset = MeetingTemplateType

/// Setup workflow options presented in the initial new meeting launcher sheet
public enum SetupOption: String, CaseIterable, Sendable {
    case quickStart = "quickStart"
    case schedule = "schedule"
    case importAudio = "importAudio"
    
    public var title: String {
        switch self {
        case .quickStart: return "Quick Start"
        case .schedule: return "Schedule Meeting"
        case .importAudio: return "Import Audio"
        }
    }
    
    public var iconName: String {
        switch self {
        case .quickStart: return "record.circle"
        case .schedule: return "calendar.badge.plus"
        case .importAudio: return "square.and.arrow.down"
        }
    }
}

/// Active stage of the new meeting setup modal
public enum SetupWorkflow: String, CaseIterable, Sendable {
    case launcher = "launcher"
    case scheduleForm = "scheduleForm"
    case audioImport = "audioImport"
    case quickMeeting = "quickMeeting"
}

/// Pre-configured meeting templates
public enum MeetingTemplateType: String, CaseIterable, Sendable {
    case standup = "standup"
    case oneOnOne = "oneOnOne"
    case clientSales = "clientSales"
    case brainstorm = "brainstorm"
    case general = "general"
    
    public static let teamStandup: MeetingTemplateType = .standup
    
    public var name: String {
        switch self {
        case .standup: return "Team Standup"
        case .oneOnOne: return "1-on-1 Review"
        case .clientSales: return "Client Sales"
        case .brainstorm: return "Brainstorm"
        case .general: return "General"
        }
    }
    
    public var defaultAgenda: String {
        switch self {
        case .standup:
            return "Yesterday:\n- What did you work on?\nToday:\n- What will you work on?\nBlockers:\n- Any blockers?"
        case .oneOnOne:
            return "Wins & Progress:\n- Key achievements\nChallenges & Support:\n- What can I help with?\nCareer & Growth:\n- Development goals"
        case .clientSales:
            return "Client Pain Points:\n- Challenges faced\nProduct Demo:\n- Feature showcase\nPricing & Next Steps:\n- Commercial proposal"
        case .brainstorm:
            return "Problem Statement:\n- Goal description\nDivergent Ideas:\n- Brainstorming notes\nAction Plan:\n- Prioritized roadmap"
        case .general:
            return "Discussion Topics:\n- Key agenda points\nAction Items:\n- Next steps"
        }
    }
}

/// Errors during audio import
public enum AudioImportError: LocalizedError, Sendable, Equatable {
    case unsupportedFormat
    case emptyFile
    case corruptedFile
    case readFailed(String)
    case invalidDuration
    
    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "The selected audio format is not supported. Please use .m4a, .mp3, or .wav files."
        case .emptyFile:
            return "The audio file is empty (0 bytes)."
        case .corruptedFile:
            return "Selected audio file is corrupt or unreadable."
        case .readFailed(let reason):
            return "Failed to read audio file: \(reason)"
        case .invalidDuration:
            return "The audio file duration is invalid or zero."
        }
    }
}

/// Meeting validation error
public enum MeetingValidationError: LocalizedError, Sendable, Equatable {
    case invalidTitle
    case invalidDateRange(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidTitle:
            return "Meeting title cannot be empty."
        case .invalidDateRange(let reason):
            return "Invalid date range: \(reason)"
        }
    }
}

/// Meeting template representation for pre-populating meeting metadata
public struct MeetingTemplate: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let description: String
    public let iconName: String
    public let defaultAgenda: String
    
    public var type: MeetingTemplateType {
        MeetingTemplateType.allCases.first(where: { $0.name == name }) ?? .general
    }
    
    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        iconName: String = "doc.text",
        defaultAgenda: String = ""
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
        self.defaultAgenda = defaultAgenda
    }
}

/// Errors thrown by the meeting setup workflow
public enum MeetingSetupError: LocalizedError, Sendable {
    case invalidTitle
    case invalidDateRange(String)
    case fileNotFound(URL)
    case contextUnavailable
    
    public var errorDescription: String? {
        switch self {
        case .invalidTitle:
            return "Meeting title cannot be empty."
        case .invalidDateRange(let reason):
            return "Invalid meeting dates: \(reason)"
        case .fileNotFound(let url):
            return "Audio file not found at: \(url.path)"
        case .contextUnavailable:
            return "Persistent storage context is unavailable."
        }
    }
}

/// ViewModel managing meeting creation, scheduling, template selection, and audio import
@Observable
@MainActor
public final class MeetingSetupViewModel {
    public var isSheetPresented: Bool = false
    public var isFormOpen: Bool = false
    public var availableSetupOptions: [SetupOption] = [.quickStart, .schedule, .importAudio]
    public var currentWorkflow: SetupWorkflow = .launcher
    
    public var title: String = ""
    public var startDate: Date = Date().addingTimeInterval(3600)
    public var endDate: Date = Date().addingTimeInterval(5400)
    public var agendaText: String = ""
    public var agenda: String {
        get { agendaText }
        set { agendaText = newValue }
    }
    
    public var participants: [Speaker] = []
    public var availableTemplates: [MeetingTemplate] = []
    public var selectedTemplate: MeetingTemplateType? = .general
    
    public var selectedFolder: Folder? = nil
    public var selectedTags: [Tag] = []
    public var defaultAudioQuality: AudioQuality = .standard
    
    public var isImportingAudio: Bool = false
    public var importProgress: Double = 0.0
    public var hasImportError: Bool = false
    public var importErrorMessage: String? = nil
    public var errorMessage: String? = nil
    
    // Warnings & Confirmations
    public var isShowingTemplateOverwriteConfirmation: Bool = false
    public var pendingTemplateSwitch: MeetingTemplateType? = nil
    
    public var onNavigateToRecording: ((UUID) -> Void)? = nil
    public var simulatedAudioDuration: TimeInterval? = nil
    public var shouldSimulateCorruptFile: Bool = false
    
    private var modelContext: ModelContext?
    private var ownedContainer: ModelContainer?
    private let transcriptionService: SpeechTranscriptionServiceProtocol?
    private let summarizationService: SummarizationServiceProtocol?
    private let audioRecordingService: AudioRecordingServiceProtocol?
    private let temporaryDirectory: URL
    private var dataStore: Any?
    
    public var areDatesValid: Bool {
        startDate < endDate
    }
    
    public var dateValidationError: String? {
        areDatesValid ? nil : "End time must be after start time."
    }
    
    public var validationErrorMessage: String? {
        areDatesValid ? nil : "End time must be after start time"
    }
    
    public var hasPastDateWarning: Bool {
        startDate < Date()
    }
    
    public var pastDateWarningMessage: String? {
        hasPastDateWarning ? "Scheduled time is in the past." : nil
    }
    
    public var isDurationExcessive: Bool {
        endDate.timeIntervalSince(startDate) > 86400
    }
    
    public var durationExcessiveWarning: String? {
        isDurationExcessive ? "Meeting duration exceeds 24 hours." : nil
    }
    
    public var isParticipantLimitReached: Bool {
        participants.count >= 50
    }
    
    public var isFormValid: Bool {
        areDatesValid
    }
    
    public init(
        modelContext: ModelContext? = nil,
        transcriptionService: SpeechTranscriptionServiceProtocol? = nil,
        summarizationService: SummarizationServiceProtocol? = nil,
        audioRecordingService: AudioRecordingServiceProtocol? = nil,
        temporaryDirectory: URL? = nil,
        dataStore: Any? = nil
    ) {
        self.modelContext = modelContext
        self.transcriptionService = transcriptionService
        self.summarizationService = summarizationService
        self.audioRecordingService = audioRecordingService
        self.temporaryDirectory = temporaryDirectory ?? FileManager.default.temporaryDirectory
        self.dataStore = dataStore
        
        if modelContext == nil && dataStore == nil {
            if let container = try? ModelContainerFactory.createInMemoryContainer() {
                self.ownedContainer = container
                self.modelContext = container.mainContext
            }
        }
        
        populateDefaultTemplates()
        resetTemplateSelection()
    }
    
    public func setModelContext(_ context: ModelContext?) {
        guard let context = context else { return }
        self.modelContext = context
    }
    
    private func populateDefaultTemplates() {
        availableTemplates = [
            MeetingTemplate(
                name: "Team Standup",
                description: "Quick daily sync on progress, blockers, and deliverables.",
                iconName: "person.3.fill",
                defaultAgenda: MeetingTemplateType.standup.defaultAgenda
            ),
            MeetingTemplate(
                name: "1-on-1 Review",
                description: "Manager and direct report check-in and goal alignment.",
                iconName: "person.2.fill",
                defaultAgenda: MeetingTemplateType.oneOnOne.defaultAgenda
            ),
            MeetingTemplate(
                name: "Client Sales",
                description: "Customer discovery, product demo, and commercial alignment.",
                iconName: "briefcase.fill",
                defaultAgenda: MeetingTemplateType.clientSales.defaultAgenda
            ),
            MeetingTemplate(
                name: "Brainstorm",
                description: "Collaborative ideation and architectural discussion.",
                iconName: "cpu",
                defaultAgenda: MeetingTemplateType.brainstorm.defaultAgenda
            ),
            MeetingTemplate(
                name: "General",
                description: "Standard meeting format with discussion and action items.",
                iconName: "doc.text",
                defaultAgenda: MeetingTemplateType.general.defaultAgenda
            )
        ]
    }
    
    public func openScheduleForm() {
        isSheetPresented = true
        isFormOpen = true
        currentWorkflow = .scheduleForm
    }
    
    public func presentSheet() {
        isSheetPresented = true
        currentWorkflow = .launcher
    }
    
    public func dismissSheet() {
        isSheetPresented = false
        isFormOpen = false
        currentWorkflow = .launcher
        title = ""
        agendaText = ""
        participants.removeAll()
        selectedTemplate = .general
        selectedFolder = nil
        selectedTags.removeAll()
        errorMessage = nil
        hasImportError = false
        importErrorMessage = nil
        simulatedAudioDuration = nil
        shouldSimulateCorruptFile = false
    }
    
    public func cancelAndDismiss() {
        dismissSheet()
        isFormOpen = false
    }
    
    public func selectSetupOption(_ option: SetupOption) {
        switch option {
        case .quickStart:
            currentWorkflow = .quickMeeting
        case .schedule:
            currentWorkflow = .scheduleForm
            isFormOpen = true
        case .importAudio:
            currentWorkflow = .audioImport
        }
    }
    
    // MARK: - Templates
    public func selectTemplate(_ templateType: MeetingTemplateType) {
        selectedTemplate = templateType
        title = templateType.name
        agendaText = templateType.defaultAgenda
    }
    
    public func selectTemplate(_ template: MeetingTemplate) {
        title = template.name
        agendaText = template.defaultAgenda
        if let match = MeetingTemplateType.allCases.first(where: { $0.name == template.name }) {
            selectedTemplate = match
        }
    }
    
    public func applyTemplate(_ templateType: MeetingTemplateType) {
        selectTemplate(templateType)
    }
    
    public func attemptTemplateSwitch(to templateType: MeetingTemplateType) {
        if !agendaText.isEmpty && agendaText != selectedTemplate?.defaultAgenda {
            pendingTemplateSwitch = templateType
            isShowingTemplateOverwriteConfirmation = true
        } else {
            selectTemplate(templateType)
        }
    }
    
    public func attemptTemplateSwitch(to template: MeetingTemplate) {
        if let match = MeetingTemplateType.allCases.first(where: { $0.name == template.name }) {
            attemptTemplateSwitch(to: match)
        } else {
            selectTemplate(template)
        }
    }
    
    public func confirmTemplateSwitch() {
        if let templateType = pendingTemplateSwitch {
            selectTemplate(templateType)
            pendingTemplateSwitch = nil
        }
        isShowingTemplateOverwriteConfirmation = false
    }
    
    public func cancelTemplateSwitch() {
        pendingTemplateSwitch = nil
        isShowingTemplateOverwriteConfirmation = false
    }
    
    public func applyCustomTemplate(title: String, sections: [String]) {
        if sections.isEmpty {
            selectTemplate(.general)
            return
        }
        self.title = title
        self.agendaText = sections.joined(separator: "\n")
    }
    
    public func applyCustomTemplate(named name: String) {
        if let custom = availableTemplates.first(where: { $0.name == name }) {
            self.title = custom.name
            self.agendaText = custom.defaultAgenda
        } else {
            selectTemplate(.general)
        }
    }
    
    public func createCustomTemplate(name: String, sections: [String], defaultDuration: TimeInterval = 3600) {
        let agenda = sections.joined(separator: "\n")
        let template = MeetingTemplate(
            name: name,
            description: "Custom user template",
            iconName: "doc.badge.gearshape",
            defaultAgenda: agenda
        )
        availableTemplates.append(template)
        self.endDate = self.startDate.addingTimeInterval(defaultDuration)
    }
    
    public func resetTemplateSelection() {
        selectedTemplate = .general
        agendaText = MeetingTemplateType.general.defaultAgenda
    }
    
    // MARK: - Participants
    @discardableResult
    public func addParticipant(name: String, email: String? = nil, role: String? = nil) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        
        if let email = email, !email.isEmpty {
            if let existingIndex = participants.firstIndex(where: {
                $0.email?.localizedCaseInsensitiveCompare(email) == .orderedSame
            }) {
                participants[existingIndex].name = trimmedName
                if let role = role, !role.isEmpty {
                    participants[existingIndex].role = role
                }
                return true
            }
        }
        
        guard participants.count < 50 else {
            return false
        }
        
        let colors = ["#3B82F6", "#10B981", "#8B5CF6", "#F59E0B", "#EF4444"]
        let colorHex = colors[participants.count % colors.count]
        let speaker = Speaker(
            name: trimmedName,
            email: email,
            role: role,
            avatarColorHex: colorHex
        )
        participants.append(speaker)
        return true
    }
    
    public func addParticipant(_ speaker: Speaker) {
        guard participants.count < 50 else { return }
        guard !participants.contains(where: {
            $0.id == speaker.id || ($0.email != nil && speaker.email != nil && $0.email?.lowercased() == speaker.email?.lowercased())
        }) else { return }
        participants.append(speaker)
    }
    
    public func removeParticipant(id: UUID) {
        participants.removeAll { $0.id == id }
    }
    
    public func removeParticipant(at index: Int) {
        if participants.indices.contains(index) {
            participants.remove(at: index)
        }
    }
    
    public func removeParticipant(_ speaker: Speaker) {
        participants.removeAll { $0.id == speaker.id }
    }
    
    public func updateParticipantRole(id: UUID, newRole: String) {
        if let idx = participants.firstIndex(where: { $0.id == id }) {
            participants[idx].role = newRole
        }
    }
    
    // MARK: - Folders & Tags
    public func selectFolder(_ folder: Folder?) {
        selectedFolder = folder
    }
    
    public func setFolder(_ folder: Folder?) {
        selectedFolder = folder
    }
    
    public func detachFolder(for meeting: Meeting) {
        meeting.folder = nil
        try? modelContext?.save()
    }
    
    public func addTag(_ tag: Tag) {
        if !selectedTags.contains(where: { $0.id == tag.id }) {
            selectedTags.append(tag)
        }
    }
    
    public func removeTag(_ tag: Tag) {
        selectedTags.removeAll { $0.id == tag.id }
    }
    
    public func toggleTag(_ tag: Tag) {
        if let idx = selectedTags.firstIndex(where: { $0.id == tag.id }) {
            selectedTags.remove(at: idx)
        } else {
            selectedTags.append(tag)
        }
    }
    
    @discardableResult
    public func createTag(name: String, colorHex: String) -> Tag {
        if let existing = selectedTags.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let tag = Tag(name: name, colorHex: colorHex)
        if let context = modelContext {
            context.insert(tag)
            try? context.save()
        }
        selectedTags.append(tag)
        return tag
    }
    
    // MARK: - Meeting Persistence
    public func saveScheduledMeeting() throws -> Meeting {
        guard areDatesValid else {
            throw MeetingValidationError.invalidDateRange("End time must be after start time.")
        }
        
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle: String
        if trimmedTitle.isEmpty {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            effectiveTitle = "Scheduled Meeting - \(formatter.string(from: startDate))"
        } else {
            effectiveTitle = trimmedTitle
        }
        
        let duration = max(0, endDate.timeIntervalSince(startDate))
        let meeting = Meeting(
            title: effectiveTitle,
            createdAt: Date(),
            scheduledStartTime: startDate,
            duration: duration,
            status: .scheduled,
            audioQuality: defaultAudioQuality,
            templateName: selectedTemplate?.name,
            folder: selectedFolder
        )
        meeting.tags = selectedTags
        meeting.participants = participants
        
        if let context = modelContext {
            context.insert(meeting)
            try context.save()
        }
        
        dismissSheet()
        return meeting
    }
    
    public func createScheduledMeeting() throws -> Meeting {
        try saveScheduledMeeting()
    }
    
    public func quickStartMeeting() -> Meeting {
        let quickTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Quick Meeting - \(Date().formatted(date: .abbreviated, time: .shortened))"
            : title
        let meeting = Meeting(
            id: UUID(),
            title: quickTitle,
            createdAt: Date(),
            scheduledStartTime: Date(),
            duration: 0,
            status: .recording,
            audioQuality: defaultAudioQuality,
            templateName: selectedTemplate?.name,
            folder: selectedFolder
        )
        meeting.tags = selectedTags
        meeting.participants = participants
        
        if let context = modelContext {
            context.insert(meeting)
            try? context.save()
        }
        
        let meetingId = meeting.id
        onNavigateToRecording?(meetingId)
        dismissSheet()
        return meeting
    }
    
    public func quickLaunchMeeting() -> Meeting {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        let timestamp = formatter.string(from: Date())
        let meeting = Meeting(
            id: UUID(),
            title: "Meeting - \(timestamp)",
            createdAt: Date(),
            scheduledStartTime: Date(),
            duration: 0,
            status: .recording,
            audioQuality: defaultAudioQuality,
            templateName: selectedTemplate?.name,
            folder: selectedFolder
        )
        meeting.tags = selectedTags
        meeting.participants = participants
        
        if let context = modelContext {
            context.insert(meeting)
            try? context.save()
        }
        
        onNavigateToRecording?(meeting.id)
        dismissSheet()
        return meeting
    }
    
    public func createQuickMeeting() -> Meeting {
        quickStartMeeting()
    }
    
    // MARK: - Audio Import
    public func isExtensionSupported(_ ext: String) -> Bool {
        let clean = ext.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return ["m4a", "mp3", "wav"].contains(clean)
    }
    
    public func isSupportedAudioExtension(_ ext: String) -> Bool {
        isExtensionSupported(ext)
    }
    
    public func setSimulatedAudioDuration(_ duration: TimeInterval) {
        self.simulatedAudioDuration = duration
    }
    
    public func importAudioFile(from url: URL) throws -> Meeting {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let ext = url.pathExtension.lowercased()
        guard isExtensionSupported(ext) else {
            hasImportError = true
            importErrorMessage = "Unsupported format"
            throw AudioImportError.unsupportedFormat
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            hasImportError = true
            importErrorMessage = "Audio file not found at: \(url.path)"
            throw AudioImportError.corruptedFile
        }
        
        if shouldSimulateCorruptFile {
            hasImportError = true
            importErrorMessage = "Selected audio file is corrupt or unreadable."
            throw AudioImportError.corruptedFile
        }
        
        
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attrs[.size] as? UInt64, fileSize == 0 {
            hasImportError = true
            importErrorMessage = "Audio file is empty"
            throw AudioImportError.emptyFile
        }
        
        if let simDuration = simulatedAudioDuration, simDuration <= 0 {
            hasImportError = true
            importErrorMessage = "The audio file duration is invalid or zero."
            throw AudioImportError.invalidDuration
        }
        
        // Duration retrieval using AVURLAsset or simulated
        var duration: TimeInterval = simulatedAudioDuration ?? 0.0
        if duration <= 0 {
            let asset = AVURLAsset(url: url)
            let assetDuration = CMTimeGetSeconds(asset.duration)
            if !assetDuration.isNaN && assetDuration > 0 {
                duration = assetDuration
            } else if simulatedAudioDuration != nil {
                hasImportError = true
                importErrorMessage = "The audio file duration is invalid or zero."
                throw AudioImportError.invalidDuration
            } else {
                hasImportError = true
                importErrorMessage = "The audio file could not be read. Choose another recording."
                throw AudioImportError.invalidDuration
            }
        }
        
        guard duration > 0 else {
            hasImportError = true
            importErrorMessage = "The audio file duration is invalid or zero."
            throw AudioImportError.invalidDuration
        }
        
        // Copy audio file to app sandbox directory for persistence
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? temporaryDirectory
        let targetURL = docs.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url, to: targetURL)
        do {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: targetURL.path)
        } catch {
            try? FileManager.default.removeItem(at: targetURL)
            throw error
        }
        let persistentAudioURL = targetURL
        
        let meetingTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? url.deletingPathExtension().lastPathComponent
            : title
        
        let meeting = Meeting(
            title: meetingTitle,
            createdAt: Date(),
            scheduledStartTime: Date(),
            duration: duration,
            status: .processing,
            audioFileURL: persistentAudioURL,
            audioQuality: defaultAudioQuality,
            templateName: selectedTemplate?.name,
            folder: selectedFolder
        )
        meeting.tags = selectedTags
        meeting.participants = participants
        
        if let context = modelContext {
            context.insert(meeting)
            do { try context.save() }
            catch {
                context.delete(meeting)
                try? FileManager.default.removeItem(at: persistentAudioURL)
                throw error
            }
        }
        
        return meeting
    }
    
    public func importAudioFile(at url: URL, title: String? = nil) async throws -> Meeting {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if let title = title {
            self.title = title
        }
        
        let ext = url.pathExtension.lowercased()
        guard isExtensionSupported(ext) else {
            hasImportError = true
            importErrorMessage = "Unsupported format"
            throw AudioImportError.unsupportedFormat
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            hasImportError = true
            importErrorMessage = "Audio file not found at: \(url.path)"
            throw AudioImportError.corruptedFile
        }
        
        if shouldSimulateCorruptFile {
            hasImportError = true
            importErrorMessage = "Selected audio file is corrupt or unreadable."
            throw AudioImportError.corruptedFile
        }
        
        if let simDuration = simulatedAudioDuration, simDuration <= 0 {
            hasImportError = true
            importErrorMessage = "The audio file duration is invalid or zero."
            throw AudioImportError.invalidDuration
        }
        
        
        let meeting = try importAudioFile(from: url)
        
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
            } catch {
                hasImportError = true
                importErrorMessage = "Selected audio file is corrupt or unreadable."
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
    
    public func importAudioFile(url: URL) async throws -> Meeting {
        try await importAudioFile(at: url, title: nil)
    }
}
