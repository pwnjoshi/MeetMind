# Project: MeetMind (iOS 17+ SwiftUI Meeting Intelligence Application)

## Architecture
MeetMind is an end-to-end, production-grade meeting intelligence application for iOS 17+ built in SwiftUI. It provides real-time audio recording, dynamic waveform visualizer, live streaming speech transcription, automated executive summaries and key decision extraction, interactive action item tracking, synchronized audio playback with variable speed scrubbing, and universal cross-meeting search.

The architecture follows **Clean Architecture + Protocol-Oriented Programming + MVVM + Observation** (`@Observable`), strictly decoupling SwiftUI user interfaces from Apple hardware and platform engines (`AVFoundation`, `Speech`, `NaturalLanguage`, `EventKit`, `SwiftData`).

```
┌────────────────────────────────────────────────────────────────────────┐
│                        SwiftUI Views (iOS 17+)                        │
│   (Home, Onboarding, Recording, DetailCockpit, ActionHub, Search, ...) │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ @Bindable / @State
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                  View Models (@Observable Classes)                     │
│  (HomeVM, RecordingVM, PlaybackVM, MeetingDetailVM, ActionVM, ...)    │
└───────────────────┬───────────────────────────────┬────────────────────┘
                    │ Protocol Invocations          │ @Query / ModelContext
                    ▼                               ▼
┌──────────────────────────────────────┐  ┌──────────────────────────────┐
│          Domain Services             │  │      SwiftData Storage       │
│  - AudioRecordingServiceProtocol     │  │  - Meeting                   │
│  - AudioPlaybackServiceProtocol      │  │  - TranscriptSegment         │
│  - SpeechTranscriptionServiceProtocol│  │  - Speaker                   │
│  - SummarizationServiceProtocol      │  │  - Summary / ActionItem      │
│  - ExportServiceProtocol             │  │  - Note / Tag / Folder       │
└───────────────────┬──────────────────┘  └──────────────────────────────┘
                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        iOS Native Frameworks                           │
│   AVFoundation (AVAudioEngine, AVAudioSession, AVAudioPlayer)          │
│   Speech (SFSpeechRecognizer, On-Device Neural Model)                  │
│   NaturalLanguage (NLTagger, NLTokenizer, Extractive Summarizer)       │
│   EventKit (Reminders & Calendar Sync)                                 │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Production iOS Architecture & Best Practices Standards
*(Mandatory reference standards: gurhub/ios-best-practices & dpearson2699/swift-ios-skills)*

All modules, view models, services, and tests across all milestones must strictly follow these engineering standards:

### 1. Clean Architecture & Protocol-Based Dependency Injection
- Strict separation between Domain Models, Business Logic Services, View Models, and Views.
- Every external dependency (Audio, Speech, Summarization, Export, Persistence, Reminders) MUST be defined as a protocol.
- View Models and consumers accept protocols via initializer injection; default to production implementations while facilitating 100% deterministic mock injection in tests and previews.
- No singleton abuse: avoid hidden global shared instances except for explicit system facade wrappers (`AVAudioSession.sharedInstance()`) isolated within dedicated actor/service boundaries.

### 2. Modern Swift Concurrency & Thread Safety
- Swift 6 strict concurrency readiness: explicit `Sendable` conformance on all data transfer objects, immutable value types (`struct`), and thread-safe protocols.
- `@MainActor` applied to all ViewModels, UI state holders, and presentation callbacks.
- Background services and asynchronous audio/buffer workers utilize `actor` or dedicated background tasks to prevent data races.
- Structured concurrency: prefer `async/await`, `TaskGroup`, and `AsyncStream` over completion-handler closures.
- Always check `Task.isCancelled` during long loops, audio processing, or chunked transcription.

### 3. Idiomatic iOS 17+ SwiftUI Design System
- Modern Observation framework: use `@Observable` class macro for ViewModels, eliminating Combine boilerplate (`ObservableObject`, `@Published`).
- Use `@Bindable` in parent views to create 2-way bindings to `@Observable` properties.
- Modular, lightweight views: decompose complex views into small reusable subviews (<100 lines each) to maximize SwiftUI view diffing performance.
- Full Dynamic Type support: use semantic typography tokens (`.title`, `.headline`, `.subheadline`, `.caption`) and scalable layouts.
- System Accessibility: provide accessibility labels, values, and traits on custom interactive components (recording button, waveform, audio scrubber, transcript bubbles).

### 4. Robust Domain Error Handling
- Define domain-specific Swift Error enums (`AudioRecordingError`, `TranscriptionError`, `SummarizationError`, `ExportError`, `PersistenceError`) adopting `LocalizedError` with user-friendly descriptions.
- Zero force-unwrapping (`!`) and zero empty `catch {}` blocks in production code.
- Present actionable error banners or alerts to users with retry options when system operations fail.

### 5. Memory Management & Lifecycle Hygiene
- Avoid retain cycles: use `[weak self]` in non-escaping closures and Combine sinks.
- Ensure audio hardware sessions (`AVAudioSession`), audio engines (`AVAudioEngine`), and speech recognition tasks (`SFSpeechRecognitionTask`) are properly cleaned up and reset in `deinit` or cancel/stop handlers.

### 6. Production-Grade Testing Standards
- Comprehensive automated test suites across all 4 tiers (Unit, Boundary, Pairwise, Real-World Workflows).
- Tests run against in-memory `ModelContainer` (`isStoredInMemoryOnly: true`) and deterministic mock services.
- Clean pass criteria: 100% test pass with zero flaky or timing-dependent failures.

---

## Feature Inventory
Every feature extracted from the authoritative Figma design (`Tar6q6zhuhMDIOBlSKzkdI`, Node `8:2`) and user requirements is accounted for and assigned to a specific milestone.

| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | SwiftData Models & Schemas | Core schema models (Meeting, TranscriptSegment, Speaker, Summary, ActionItem, Note, Tag, Folder) with cascade delete rules | M1 | Survey Spec Miner 3 |
| 2 | Design System & Theme Tokens | Color palette (#1E2E28 slate, warm amber, live blue, AI purple, mint green, coral red), typography, spacing, card styles | M1 | Survey Spec Miner 2 |
| 3 | Audio Recording Service | AVAudioSession management, AVAudioEngine dual-stream input tap, AAC file writer, real-time power metering (RMS->dB->linear) | M1 | Survey Spec Miner 3 |
| 4 | Audio Playback Service | AVAudioPlayer engine, variable rate (0.75x-2.0x) with pitch correction, debounced scrubbing, timecode synchronization | M1 | Survey Spec Miner 3 |
| 5 | Speech Transcription Service | SFSpeechRecognizer, streaming buffer recognition, on-device offline recognition fallback, pause-based diarization | M1 | Survey Spec Miner 3 |
| 6 | Summarization & Intelligence Service | Dual-engine: Apple NaturalLanguage offline extractive summary + rule-based action parser, and LLM structured JSON schema | M1 | Survey Spec Miner 3 |
| 7 | Export Service Engine | UIGraphicsPDFRenderer multi-page PDF generator, Markdown/text exporter, email summary builder | M1 | Survey Spec Miner 2 |
| 8 | Service Protocols & Mock Implementations | Full protocol abstraction with mock services for deterministic automated tests and SwiftUI previews | M1 | Survey Explorer 1 |
| 9 | App Lifecycle & Routing | MeetMindApp entry point with SwiftData container injection, AppState router, first-launch routing check | M2 | Survey Spec Miner 2 |
| 10 | Onboarding Welcome Carousel | Paged TabView carousel highlighting live transcription, AI minutes, and action items | M2 | Survey Spec Miner 2 |
| 11 | Profile & Voice Setup | User profile setup, display name, email/role, optional voice enrollment sample | M2 | Survey Spec Miner 2 |
| 12 | Permissions Primer View | Custom UI primer requesting mic, speech, calendar, notifications with fallback to system settings | M2 | Survey Spec Miner 2 |
| 13 | Main Tab Navigation Shell | 4-tab root navigation (Home, Action Items, Search, Settings) with badges and smooth transitions | M2 | Survey Spec Miner 2 |
| 14 | Settings View: Audio Quality | High (128kbps) vs Standard (64kbps) AAC picker, background noise suppression toggle | M2 | Survey Spec Miner 2 |
| 15 | Settings View: Speech & AI Options | Transcription language picker, on-device offline toggle, summary detail style picker | M2 | Survey Spec Miner 2 |
| 16 | Settings View: Storage & Cache | Local storage usage meter, clear temporary audio cache, iCloud sync toggle | M2 | Survey Spec Miner 2 |
| 17 | Settings View: Theme & Appearance | System / Light / Dark theme picker with instant dynamic color scheme adaptation | M2 | Survey Spec Miner 2 |
| 18 | Central Dashboard Feed | Home view displaying greeting, upcoming meeting carousel, recent meeting feed with AI summaries | M3 | Survey Spec Miner 2 |
| 19 | Meeting Status Badges | Color-coded status capsules (Scheduled, Recording, Processing, Completed) on meeting cards | M3 | Survey Spec Miner 2 |
| 20 | Quick Filter Chips | Horizontal scrolling filter pills: "All", "Today", "This Week", "Action Items", "Starred" | M3 | Survey Spec Miner 2 |
| 21 | Meeting Card Swipe Actions | Leading swipe to toggle Favorite (Star); trailing swipe for Delete (with confirmation) or Move to Folder | M3 | Survey Spec Miner 2 |
| 22 | New Meeting Modal Launcher | Sheet presenting 3 creation paths: Quick Start, Schedule Meeting, and Audio File Import | M3 | Survey Spec Miner 2 |
| 23 | Schedule Meeting Form | Form to schedule future meeting with title, DatePicker, agenda, template selector | M3 | Survey Spec Miner 2 |
| 24 | Meeting Templates Selector | Pre-configured templates: 1-on-1, Team Standup, Client Sales, Brainstorm, General | M3 | Survey Spec Miner 2 |
| 25 | Participant Manager | Add/invite attendees with name, email, role, and avatar token chips | M3 | Survey Spec Miner 2 |
| 26 | Quick Meeting Launcher | One-tap instant meeting start with auto-generated title and immediate transition to recording | M3 | Survey Spec Miner 2 |
| 27 | Audio File Import | Import external .m4a/.mp3/.wav files via UIDocumentPicker, format validation, duration check | M3 | Survey Spec Miner 2 |
| 28 | Folders & Tags Organization | Custom folders ("Engineering", "Clients") and tags for meeting categorization | M3 | Survey Spec Miner 2 |
| 29 | Live Recording Console | Full-screen recording view with header, elapsed timer (HH:MM:SS), pulsing indicator, active mic badge | M4 | Survey Spec Miner 2 |
| 30 | Live Dynamic Waveform Visualizer | 32-bar animated waveform visualizer reacting to 60Hz linear audio power levels (0.0 - 1.0) | M4 | Survey Spec Miner 2 |
| 31 | Live Streaming Transcript Feed | Auto-scrolling feed of streaming speech chunks; interim results in italics, final in bold | M4 | Survey Spec Miner 2 |
| 32 | Live Note-Taking Dock Tool | Floating sheet to capture timestamped notes during active recording | M4 | Survey Spec Miner 2 |
| 33 | Live Bookmark / Flag Tool | One-tap marker flagging key moments with timecode and star badge | M4 | Survey Spec Miner 2 |
| 34 | Live Speaker Tag Switcher | On-the-fly active speaker tag switcher chips for conversational turns | M4 | Survey Spec Miner 2 |
| 35 | Whiteboard / Media Capture | Capture camera photo of whiteboard/slides or pick photo pinned to recording timecode | M4 | Survey Spec Miner 2 |
| 36 | Pause & Resume Controls | Pause recording without terminating session; freezes timer, flattens waveform | M4 | Survey Spec Miner 2 |
| 37 | Finish / Stop Recording | Flushes audio buffers, writes final AAC file, advances to post-processing pipeline | M4 | Survey Spec Miner 2 |
| 38 | Discard Confirmation Dialog | Destructive confirmation alert preventing accidental loss of meeting recordings | M4 | Survey Spec Miner 2 |
| 39 | Post-Recording Synthesis HUD | Animated transition view displaying multi-stage pipeline status (audio, speech, summary, tasks) | M4 | Survey Spec Miner 2 |
| 40 | Meeting Detail Cockpit & Tabs | Master post-meeting cockpit with segmented tabs (Summary, Transcript, Action Items, Notes & Media) | M5 | Survey Spec Miner 2 |
| 41 | Executive Summary View | High-level executive overview card, key discussion topics with timecode links, key decisions card | M5 | Survey Spec Miner 2 |
| 42 | Diarized Transcript Feed | Speaker bubbles with avatars, names, timestamps, and active sentence teal highlighting during playback | M5 | Survey Spec Miner 2 |
| 43 | Tap-to-Seek Audio Playback | Tapping any transcript sentence seeks audio player directly to that spoken second | M5 | Survey Spec Miner 2 |
| 44 | Inline Transcript Editor | Tap-to-edit sheet allowing users to correct speech recognition errors inline | M5 | Survey Spec Miner 2 |
| 45 | Speaker Reassignment Sheet | Sheet to reassign all segments of a speaker to a named participant across the entire meeting | M5 | Survey Spec Miner 2 |
| 46 | Sticky Audio Player Bar | Bottom player bar with scrub slider, 15s skip backward/forward, play/pause, timecodes | M5 | Survey Spec Miner 2 |
| 47 | Variable Speed Playback | Toggle audio rate between 0.75x, 1.0x, 1.25x, 1.5x, 2.0x with pitch correction | M5 | Survey Spec Miner 2 |
| 48 | Action Items Interactive Checklist | Checklist with round checkbox toggle, task title, assignee chip, due date, priority pill | M5 | Survey Spec Miner 2 |
| 49 | Add / Edit Action Item Sheet | Modal sheet to create or edit action items, assignees, due dates, and priority | M5 | Survey Spec Miner 2 |
| 50 | Sync to Apple Reminders | One-tap sync exporting all meeting action items into the native iOS Reminders app | M5 | Survey Spec Miner 2 |
| 51 | Whiteboard & Notes Gallery | Grid of whiteboard photos and manual notes with full-screen pinch-to-zoom modal | M5 | Survey Spec Miner 2 |
| 52 | Interactive Ask AI Assistant Sheet | Conversational bottom sheet answering meeting questions grounded in transcript with timecode citations | M5 | Survey Spec Miner 2 |
| 53 | PDF Minutes & Markdown Export | Export meeting minutes as formatted multi-page PDF, Markdown, text, or email draft | M5 | Survey Spec Miner 2 |
| 54 | Cross-Meeting Action Console | Dedicated tab aggregating pending and completed action items from all meetings | M5 | Survey Spec Miner 2 |
| 55 | Universal Search Engine | Cross-meeting search across titles, transcripts, summaries, and tasks with keyword jump-to-timecode | M5 | Survey Spec Miner 2 |

---

## Milestones

| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Core Scaffolding, Models, Design System & Services | Xcode project structure, SwiftData models (Meeting, TranscriptSegment, Speaker, Summary, ActionItem, Note, Tag, Folder), DesignSystem tokens & components, Service protocols (Audio, Speech, Summarization, Export) and production + mock implementations, XCTest baseline | none | DONE |
| M2 | Navigation Shell, Onboarding, Permissions & Settings | MeetMindApp entry, AppState navigation router, OnboardingWelcomeView, ProfileSetupView, PermissionsPrimerView, MainTabView shell, SettingsView (Audio, Speech, Storage, Theme) | M1 | DONE |
| M3 | Home Dashboard, Meeting Creation & Audio Import | HomeDashboardView (upcoming carousel, recent feed, status badges, swipe actions, filter chips), NewMeetingSheet, ScheduleMeetingView (templates, participant manager), AudioImportView, Folder & Tag management | M1, M2 | DONE |
| M4 | Live Recording Console, Waveform & Speech Streaming | LiveRecordingView (header, timer, mic badge), dynamic 60Hz WaveformVisualizerView, live streaming transcript feed, in-recording tool dock (notes, bookmarks, speaker switcher, photo capture), pause/resume, discard dialog, MeetingProcessingView synthesizer | M1, M3 | DONE |
| M5 | Post-Meeting Review Cockpit, Audio Player, Actions & Search | MeetingDetailView (Summary, Transcript, Action Items, Notes & Media tabs), StickyAudioPlayerBar (scrubbing, 0.75x-2.0x variable speed), tap-to-seek, transcript editor, speaker reassignment, Reminders sync, Ask AI sheet, PDF/Markdown export, ActionItemsConsoleView, SearchConsoleView | M1, M4 | DONE |
| M6 | Final Milestone: 100% E2E Test Suite Pass & Adversarial Hardening | Phase 1: Pass 100% of automated E2E tests (Tiers 1-4) published in TEST_READY.md. Phase 2: Tier 5 adversarial coverage hardening via Challenger -> Worker -> Reviewer loop | M1-M5, TEST_READY.md | DONE |

---

## Interface Contracts

### Audio Services ↔ View Models
```swift
public protocol AudioRecordingServiceProtocol: AnyObject, Sendable {
    var state: RecordingState { get }
    var currentDuration: TimeInterval { get }
    var audioMeterStream: AsyncStream<Float> { get }
    func startRecording(destinationURL: URL) async throws
    func pauseRecording() throws
    func resumeRecording() throws
    func stopRecording() async throws -> URL
    func cancelRecording() throws
}

public protocol AudioPlaybackServiceProtocol: AnyObject, Sendable {
    var state: PlaybackState { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var playbackRate: Float { get set }
    var isPlaying: Bool { get }
    func loadAudio(url: URL) throws
    func play() throws
    func pause()
    func stop()
    func seek(to time: TimeInterval)
    func addTimeObserver(interval: TimeInterval, handler: @Sendable @escaping (TimeInterval) -> Void) -> UUID
    func removeTimeObserver(id: UUID)
}
```

### Speech Transcription ↔ View Models
```swift
public struct LiveTranscriptChunk: Sendable, Equatable {
    public let text: String
    public let isFinal: Bool
    public let segments: [LiveTranscriptSegment]
}

public struct LiveTranscriptSegment: Sendable, Equatable {
    public let text: String
    public let startTime: TimeInterval
    public let duration: TimeInterval
    public let confidence: Float
}

public protocol SpeechTranscriptionServiceProtocol: AnyObject, Sendable {
    var isAvailable: Bool { get }
    var supportsOnDeviceRecognition: Bool { get }
    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus
    func startLiveTranscription(audioBufferStream: AsyncStream<AVAudioPCMBuffer>) -> AsyncThrowingStream<LiveTranscriptChunk, Error>
    func stopLiveTranscription()
    func transcribeAudioFile(at url: URL) async throws -> [LiveTranscriptSegment]
}
```

### Summarization & Intelligence ↔ View Models
```swift
public struct MeetingSummaryResponse: Codable, Sendable, Equatable {
    public let executiveSummary: String
    public let keyDiscussionPoints: [String]
    public let keyDecisions: [String]
    public let actionItems: [ParsedActionItem]
    public let topics: [String]
}

public struct ParsedActionItem: Codable, Sendable, Equatable {
    public let title: String
    public let taskDescription: String
    public let assignee: String?
    public let dueDate: Date?
    public let priority: String
}

public protocol SummarizationServiceProtocol: AnyObject, Sendable {
    func generateSummary(from transcriptText: String) async throws -> MeetingSummaryResponse
}
```

### Export Service ↔ Detail View
```swift
public protocol ExportServiceProtocol: AnyObject, Sendable {
    func generatePDFReport(for meeting: Meeting) throws -> Data
    func generateMarkdown(for meeting: Meeting) -> String
    func generatePlainText(for meeting: Meeting) -> String
}
```

---

## Production iOS Architecture & Best Practices Standards
*(Mandatory reference standards: gurhub/ios-best-practices & dpearson2699/swift-ios-skills)*

All modules, view models, services, and tests across all milestones must strictly follow these engineering standards:

### 1. Clean Architecture & Protocol-Based Dependency Injection
- Strict separation between Domain Models, Business Logic Services, View Models, and Views.
- Every external dependency (Audio, Speech, Summarization, Export, Persistence, Reminders) MUST be defined as a protocol.
- View Models and consumers accept protocols via initializer injection; default to production implementations while facilitating 100% deterministic mock injection in tests and previews.
- No singleton abuse: avoid hidden global shared instances except for explicit system facade wrappers (`AVAudioSession.sharedInstance()`) isolated within dedicated actor/service boundaries.

### 2. Modern Swift Concurrency & Thread Safety
- Swift 6 strict concurrency readiness: explicit `Sendable` conformance on all data transfer objects, immutable value types (`struct`), and thread-safe protocols.
- `@MainActor` applied to all ViewModels, UI state holders, and presentation callbacks.
- Background services and asynchronous audio/buffer workers utilize `actor` or dedicated background tasks to prevent data races.
- Structured concurrency: prefer `async/await`, `TaskGroup`, and `AsyncStream` over completion-handler closures.
- Always check `Task.isCancelled` during long loops, audio processing, or chunked transcription.

### 3. Idiomatic iOS 17+ SwiftUI Design System
- Modern Observation framework: use `@Observable` class macro for ViewModels, eliminating Combine boilerplate (`ObservableObject`, `@Published`).
- Use `@Bindable` in parent views to create 2-way bindings to `@Observable` properties.
- Modular, lightweight views: decompose complex views into small reusable subviews (<100 lines each) to maximize SwiftUI view diffing performance.
- Full Dynamic Type support: use semantic typography tokens (`.title`, `.headline`, `.subheadline`, `.caption`) and scalable layouts.
- System Accessibility: provide accessibility labels, values, and traits on custom interactive components (recording button, waveform, audio scrubber, transcript bubbles).

### 4. Robust Domain Error Handling
- Define domain-specific Swift Error enums (`AudioRecordingError`, `TranscriptionError`, `SummarizationError`, `ExportError`, `PersistenceError`) adopting `LocalizedError` with user-friendly descriptions.
- Zero force-unwrapping (`!`) and zero empty `catch {}` blocks in production code.
- Present actionable error banners or alerts to users with retry options when system operations fail.

### 5. Memory Management & Lifecycle Hygiene
- Avoid retain cycles: use `[weak self]` in non-escaping closures and Combine sinks.
- Ensure audio hardware sessions (`AVAudioSession`), audio engines (`AVAudioEngine`), and speech recognition tasks (`SFSpeechRecognitionTask`) are properly cleaned up and reset in `deinit` or cancel/stop handlers.

### 6. Production-Grade Testing Standards
- Comprehensive automated test suites across all 4 tiers (Unit, Boundary, Pairwise, Real-World Workflows).
- Tests run against in-memory `ModelContainer` (`isStoredInMemoryOnly: true`) and deterministic mock services.
- Clean pass criteria: 100% test pass with zero flaky or timing-dependent failures.

---

## Code Layout

```
c:\Users\joshi\Desktop\MeetMind\
├── .gitignore
├── README.md
├── PROJECT.md
├── TEST_INFRA.md
├── TEST_READY.md
├── MeetMind.xcodeproj/
│   └── project.pbxproj
├── MeetMind/
│   ├── App/
│   │   ├── MeetMindApp.swift
│   │   ├── AppState.swift
│   │   └── NavigationRouter.swift
│   ├── DesignSystem/
│   │   ├── Theme.swift
│   │   ├── Typography.swift
│   │   ├── Spacing.swift
│   │   └── Components/
│   │       ├── Buttons/
│   │       ├── Cards/
│   │       ├── Badges/
│   │       ├── Inputs/
│   │       └── Audio/
│   ├── Models/
│   │   ├── Meeting.swift
│   │   ├── TranscriptSegment.swift
│   │   ├── Speaker.swift
│   │   ├── Summary.swift
│   │   ├── ActionItem.swift
│   │   ├── Note.swift
│   │   ├── Tag.swift
│   │   ├── Folder.swift
│   │   └── FilterOptions.swift
│   ├── Services/
│   │   ├── Audio/
│   │   │   ├── AudioRecordingServiceProtocol.swift
│   │   │   ├── AudioRecordingService.swift
│   │   │   ├── AudioPlaybackServiceProtocol.swift
│   │   │   ├── AudioPlaybackService.swift
│   │   │   ├── MockAudioRecordingService.swift
│   │   │   └── MockAudioPlaybackService.swift
│   │   ├── Transcription/
│   │   │   ├── SpeechTranscriptionServiceProtocol.swift
│   │   │   ├── SpeechTranscriptionService.swift
│   │   │   └── MockSpeechTranscriptionService.swift
│   │   ├── Intelligence/
│   │   │   ├── SummarizationServiceProtocol.swift
│   │   │   ├── NaturalLanguageSummarizationService.swift
│   │   │   └── MockSummarizationService.swift
│   │   ├── Export/
│   │   │   ├── ExportServiceProtocol.swift
│   │   │   ├── ExportService.swift
│   │   │   └── MockExportService.swift
│   │   └── Persistence/
│   │       └── ModelContainerFactory.swift
│   ├── ViewModels/
│   │   ├── HomeViewModel.swift
│   │   ├── MeetingSetupViewModel.swift
│   │   ├── LiveRecordingViewModel.swift
│   │   ├── ProcessingPipelineViewModel.swift
│   │   ├── MeetingDetailViewModel.swift
│   │   ├── ActionItemsViewModel.swift
│   │   ├── SearchViewModel.swift
│   │   └── SettingsViewModel.swift
│   ├── Views/
│   │   ├── Navigation/
│   │   │   ├── MainTabView.swift
│   │   │   └── RootView.swift
│   │   ├── Onboarding/
│   │   │   ├── OnboardingWelcomeView.swift
│   │   │   ├── ProfileSetupView.swift
│   │   │   └── PermissionsPrimerView.swift
│   │   ├── Home/
│   │   │   ├── HomeDashboardView.swift
│   │   │   ├── UpcomingMeetingCard.swift
│   │   │   ├── RecentMeetingCard.swift
│   │   │   └── FilterChipBar.swift
│   │   ├── Setup/
│   │   │   ├── NewMeetingSheet.swift
│   │   │   ├── ScheduleMeetingView.swift
│   │   │   └── AudioImportView.swift
│   │   ├── Recording/
│   │   │   ├── LiveRecordingView.swift
│   │   │   ├── WaveformVisualizerView.swift
│   │   │   ├── LiveTranscriptScrollView.swift
│   │   │   ├── LiveActionToolDock.swift
│   │   │   └── MeetingProcessingView.swift
│   │   ├── Detail/
│   │   │   ├── MeetingDetailView.swift
│   │   │   ├── SummaryTabView.swift
│   │   │   ├── TranscriptTabView.swift
│   │   │   ├── ActionItemsTabView.swift
│   │   │   ├── NotesMediaTabView.swift
│   │   │   ├── StickyAudioPlayerBar.swift
│   │   │   ├── AskAIAssistantSheet.swift
│   │   │   ├── InlineTranscriptEditorSheet.swift
│   │   │   ├── ReassignSpeakerSheet.swift
│   │   │   └── ExportMeetingSheet.swift
│   │   ├── Actions/
│   │   │   ├── ActionItemsView.swift
│   │   │   └── ActionItemRow.swift
│   │   ├── Search/
│   │   │   ├── SearchConsoleView.swift
│   │   │   └── SearchResultCard.swift
│   │   └── Settings/
│   │       └── SettingsView.swift
│   └── Resources/
│       ├── Assets.xcassets/
│       └── Info.plist
├── MeetMindTests/
│   ├── MeetingModelTests.swift
│   ├── ActionItemModelTests.swift
│   ├── AudioRecordingServiceTests.swift
│   ├── AudioPlaybackServiceTests.swift
│   ├── SpeechTranscriptionServiceTests.swift
│   ├── SummarizationServiceTests.swift
│   ├── ExportServiceTests.swift
│   ├── HomeViewModelTests.swift
│   ├── LiveRecordingViewModelTests.swift
│   ├── MeetingDetailViewModelTests.swift
│   └── SearchViewModelTests.swift
└── Scripts/
    ├── verify_project.py
    └── run_unit_tests.py
```
