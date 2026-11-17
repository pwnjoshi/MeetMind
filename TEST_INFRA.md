# E2E Test Infra: MeetMind (iOS 17+ SwiftUI Meeting Intelligence)

## Test Philosophy
- **Opaque-Box & Requirement-Driven**: Tests are designed directly from `ORIGINAL_REQUEST.md` and the authoritative Figma design specification (`Tar6q6zhuhMDIOBlSKzkdI`, Node `8:2`). Tests do not assume or couple to private implementation internals, but validate contracts, public view model states, domain services, persistence entities, and end-to-end user workflows.
- **Progressive Testability**: Verification does not require features more complex than the tested feature. Tier 1 unit verification functions reliably from early scaffolding onwards.
- **Methodology**: Systematic 4-Tier test design integrating:
  1. *Category-Partition Testing* for equivalence classes.
  2. *Boundary Value Analysis (BVA)* for edge conditions, empty values, capacity limits, extreme duration, and error fallbacks.
  3. *Pairwise Combinatorial Testing* for cross-feature interactions and state transitions.
  4. *Real-World Workload Testing* for end-to-end user journeys (recording, live streaming transcription, audio scrubbing, AI summarization, Reminders sync, export, and search).

---

## Feature Inventory & 4-Tier Test Matrix

Every feature from `PROJECT.md § Feature Inventory` is mapped to its 4-tier coverage requirements:

| # | Feature | Source (Requirement) | Tier 1 (>=5) | Tier 2 (>=5) | Tier 3 (Pairwise) | Tier 4 (Scenario) |
|---|---------|---------------------|:------------:|:------------:|:-----------------:|:-----------------:|
| 1 | SwiftData Models & Schemas | ORIGINAL_REQUEST §R1, R3; M1 | 5 | 5 | ✓ | S1, S2, S7 |
| 2 | Design System & Theme Tokens | ORIGINAL_REQUEST §R2; M1 | 5 | 5 | ✓ | S1, S5 |
| 3 | Audio Recording Service | ORIGINAL_REQUEST §R3; M1 | 5 | 5 | ✓ | S2, S3, S6 |
| 4 | Audio Playback Service | ORIGINAL_REQUEST §R3; M1 | 5 | 5 | ✓ | S4, S7, S11 |
| 5 | Speech Transcription Service | ORIGINAL_REQUEST §R3; M1 | 5 | 5 | ✓ | S2, S3, S10 |
| 6 | Summarization & Intelligence Service | ORIGINAL_REQUEST §R3; M1 | 5 | 5 | ✓ | S3, S8, S12 |
| 7 | Export Service Engine | ORIGINAL_REQUEST §R3; M1 | 5 | 5 | ✓ | S9, S13 |
| 8 | Service Protocols & Mock Implementations | ORIGINAL_REQUEST §R1, R4; M1 | 5 | 5 | ✓ | All Scenarios |
| 9 | App Lifecycle & Routing | ORIGINAL_REQUEST §R1, R2; M2 | 5 | 5 | ✓ | S1, S14 |
| 10 | Onboarding Welcome Carousel | ORIGINAL_REQUEST §R2; M2 | 5 | 5 | ✓ | S1, S15 |
| 11 | Profile & Voice Setup | ORIGINAL_REQUEST §R2, R3; M2 | 5 | 5 | ✓ | S1, S16 |
| 12 | Permissions Primer View | ORIGINAL_REQUEST §R2, R3; M2 | 5 | 5 | ✓ | S1, S17 |
| 13 | Main Tab Navigation Shell | ORIGINAL_REQUEST §R2; M2 | 5 | 5 | ✓ | S1, S18 |
| 14 | Settings View: Audio Quality | ORIGINAL_REQUEST §R2, R3; M2 | 5 | 5 | ✓ | S5, S19 |
| 15 | Settings View: Speech & AI Options | ORIGINAL_REQUEST §R2, R3; M2 | 5 | 5 | ✓ | S5, S20 |
| 16 | Settings View: Storage & Cache | ORIGINAL_REQUEST §R2, R3; M2 | 5 | 5 | ✓ | S5, S21 |
| 17 | Settings View: Theme & Appearance | ORIGINAL_REQUEST §R2; M2 | 5 | 5 | ✓ | S5, S22 |
| 18 | Central Dashboard Feed | ORIGINAL_REQUEST §R2; M3 | 5 | 5 | ✓ | S6, S23 |
| 19 | Meeting Status Badges | ORIGINAL_REQUEST §R2; M3 | 5 | 5 | ✓ | S6, S24 |
| 20 | Quick Filter Chips | ORIGINAL_REQUEST §R2; M3 | 5 | 5 | ✓ | S6, S25 |
| 21 | Meeting Card Swipe Actions | ORIGINAL_REQUEST §R2; M3 | 5 | 5 | ✓ | S6, S26 |
| 22 | New Meeting Modal Launcher | ORIGINAL_REQUEST §R2; M3 | 5 | 5 | ✓ | S2, S27 |
| 23 | Schedule Meeting Form | ORIGINAL_REQUEST §R2; M3 | 5 | 5 | ✓ | S2, S28 |
| 24 | Meeting Templates Selector | ORIGINAL_REQUEST §R2; M3 | 5 | 5 | ✓ | S2, S29 |
| 25 | Participant Manager | ORIGINAL_REQUEST §R2; M3 | 5 | 5 | ✓ | S2, S30 |
| 26 | Quick Meeting Launcher | ORIGINAL_REQUEST §R2; M3 | 5 | 5 | ✓ | S2, S31 |
| 27 | Audio File Import | ORIGINAL_REQUEST §R3; M3 | 5 | 5 | ✓ | S10, S32 |
| 28 | Folders & Tags Organization | ORIGINAL_REQUEST §R2, R3; M3 | 5 | 5 | ✓ | S7, S33 |
| 29 | Live Recording Console | ORIGINAL_REQUEST §R2, R3; M4 | 5 | 5 | ✓ | S3, S6 |
| 30 | Live Dynamic Waveform Visualizer | ORIGINAL_REQUEST §R2, R3; M4 | 5 | 5 | ✓ | S3, S6 |
| 31 | Live Streaming Transcript Feed | ORIGINAL_REQUEST §R2, R3; M4 | 5 | 5 | ✓ | S3, S6 |
| 32 | Live Note-Taking Dock Tool | ORIGINAL_REQUEST §R2; M4 | 5 | 5 | ✓ | S3, S6 |
| 33 | Live Bookmark / Flag Tool | ORIGINAL_REQUEST §R2; M4 | 5 | 5 | ✓ | S3, S6 |
| 34 | Live Speaker Tag Switcher | ORIGINAL_REQUEST §R2, R3; M4 | 5 | 5 | ✓ | S3, S6 |
| 35 | Whiteboard / Media Capture | ORIGINAL_REQUEST §R2; M4 | 5 | 5 | ✓ | S3, S6 |
| 36 | Pause & Resume Controls | ORIGINAL_REQUEST §R2, R3; M4 | 5 | 5 | ✓ | S3, S6 |
| 37 | Finish / Stop Recording | ORIGINAL_REQUEST §R2, R3; M4 | 5 | 5 | ✓ | S3, S6 |
| 38 | Discard Confirmation Dialog | ORIGINAL_REQUEST §R2; M4 | 5 | 5 | ✓ | S3, S34 |
| 39 | Post-Recording Synthesis HUD | ORIGINAL_REQUEST §R2, R3; M4 | 5 | 5 | ✓ | S3, S6 |
| 40 | Meeting Detail Cockpit & Tabs | ORIGINAL_REQUEST §R2; M5 | 5 | 5 | ✓ | S4, S7 |
| 41 | Executive Summary View | ORIGINAL_REQUEST §R2, R3; M5 | 5 | 5 | ✓ | S4, S8 |
| 42 | Diarized Transcript Feed | ORIGINAL_REQUEST §R2, R3; M5 | 5 | 5 | ✓ | S4, S7 |
| 43 | Tap-to-Seek Audio Playback | ORIGINAL_REQUEST §R2, R3; M5 | 5 | 5 | ✓ | S4, S11 |
| 44 | Inline Transcript Editor | ORIGINAL_REQUEST §R2; M5 | 5 | 5 | ✓ | S4, S7 |
| 45 | Speaker Reassignment Sheet | ORIGINAL_REQUEST §R2; M5 | 5 | 5 | ✓ | S4, S7 |
| 46 | Sticky Audio Player Bar | ORIGINAL_REQUEST §R2, R3; M5 | 5 | 5 | ✓ | S4, S11 |
| 47 | Variable Speed Playback | ORIGINAL_REQUEST §R2, R3; M5 | 5 | 5 | ✓ | S4, S11 |
| 48 | Action Items Interactive Checklist | ORIGINAL_REQUEST §R2, R3; M5 | 5 | 5 | ✓ | S4, S8 |
| 49 | Add / Edit Action Item Sheet | ORIGINAL_REQUEST §R2; M5 | 5 | 5 | ✓ | S4, S8 |
| 50 | Sync to Apple Reminders | ORIGINAL_REQUEST §R3; M5 | 5 | 5 | ✓ | S4, S8 |
| 51 | Whiteboard & Notes Gallery | ORIGINAL_REQUEST §R2; M5 | 5 | 5 | ✓ | S4, S7 |
| 52 | Interactive Ask AI Assistant Sheet | ORIGINAL_REQUEST §R2, R3; M5 | 5 | 5 | ✓ | S4, S12 |
| 53 | PDF Minutes & Markdown Export | ORIGINAL_REQUEST §R2, R3; M5 | 5 | 5 | ✓ | S4, S9, S13 |
| 54 | Cross-Meeting Action Console | ORIGINAL_REQUEST §R2, R3; M5 | 5 | 5 | ✓ | S8, S35 |
| 55 | Universal Search Engine | ORIGINAL_REQUEST §R2, R3; M5 | 5 | 5 | ✓ | S11, S36 |

---

## Test Architecture & Directory Layout

### Directory Structure
```
c:\Users\joshi\Desktop\MeetMind\
├── MeetMindTests/
│   ├── Models/
│   │   ├── MeetingModelTests.swift             # Schema validation, cascade deletes, relationships
│   │   ├── ActionItemModelTests.swift          # Priority, completion, reminders mapping
│   │   └── SpeakerAndNotesModelTests.swift     # Speaker profiles, tags, folders, media
│   ├── Services/
│   │   ├── AudioRecordingServiceTests.swift    # Buffer taps, power metering, pause/resume
│   │   ├── AudioPlaybackServiceTests.swift     # Variable speed (0.75-2.0x), pitch, scrubbing
│   │   ├── SpeechTranscriptionServiceTests.swift # Streaming chunks, offline fallback, diarization
│   │   ├── SummarizationServiceTests.swift     # Apple NL vs LLM mock, JSON schema parsing
│   │   └── ExportServiceTests.swift            # PDF graphics, Markdown, email formatting
│   ├── ViewModels/
│   │   ├── HomeViewModelTests.swift            # Feed querying, filter chips, swipe mutations
│   │   ├── MeetingSetupViewModelTests.swift    # Templates, validation, attendee management
│   │   ├── LiveRecordingViewModelTests.swift   # Timer cadence, waveform power, tool dock
│   │   ├── ProcessingPipelineViewModelTests.swift # Synthesis HUD progression, error retry
│   │   ├── MeetingDetailViewModelTests.swift   # Audio seek synchronization, transcript edits
│   │   ├── ActionItemsViewModelTests.swift     # Cross-meeting aggregation, Reminders export
│   │   ├── SearchViewModelTests.swift          # Tokenized search, filter scopes, highlights
│   │   └── SettingsViewModelTests.swift        # Audio encoding, theme switching, storage purge
│   └── E2E/
│       ├── RecordingToSummaryE2ETests.swift     # Instant record -> stream -> synthesis -> detail
│       ├── ActionItemLifecycleE2ETests.swift   # Audio extraction -> check toggle -> Reminders sync
│       ├── AudioPlaybackSyncE2ETests.swift     # Transcript tap-to-seek -> scrub -> speed adjust
│       └── UniversalSearchE2ETests.swift       # Cross-meeting transcript and action item discovery
└── Scripts/
    ├── verify_project.py                       # Project structure, Xcode project integrity, code standards
    └── run_unit_tests.py                       # Host-side execution harness validating all test suites
```

### Test Invocation & Semantics
- **Automated Host Test Runner**: `python Scripts/run_unit_tests.py`
  - Validates Swift test suites, syntax contracts, mock implementations, model behaviors, and user workflows.
  - Returns exit code `0` on 100% test pass.
  - Returns non-zero exit code on any failure, emitting concise diagnostic logs with failure file, line, and assertion reason.
- **Project Structure Verifier**: `python Scripts/verify_project.py`
  - Verifies Xcode project bundle configuration, file references, compilation sources, and asset bundles.

---

## Real-World Application Scenarios (Tier 4)

The test suite validates 36 comprehensive application scenarios exercising multiple interconnected features:

1. **S1 (First Run Experience)**: Fresh install -> Onboarding carousel -> Profile creation with voice sample -> Permissions primer (mic + speech + reminders) -> Welcome landing on Home tab.
2. **S2 (Scheduled Standup Meeting)**: Home tab -> New Meeting -> Schedule Form -> Select "Team Standup" template -> Add 4 participants -> Save to SwiftData -> Card appears in Upcoming carousel.
3. **S3 (Live Interactive Recording)**: Quick Start -> Live recording screen activates -> Waveform reacts to audio levels -> Speech streams live transcript -> User flags 2 bookmarks -> User writes live note -> User takes whiteboard snap -> Stop recording -> Post-processing synthesis HUD animates -> Meeting detail opens.
4. **S4 (Post-Meeting Audio & Transcript Review)**: Meeting detail cockpit -> Play audio -> Tap transcript bubble at 02:45 -> Player seeks immediately to 02:45 -> Change rate to 1.5x -> Verify audio rate changes with pitch correction -> Edit typo in transcript -> Reassign speaker from "Speaker 2" to "Sarah Connor".
5. **S5 (Settings Customization & Persistence)**: Open Settings tab -> Switch audio quality from High (128kbps) to Standard (64kbps) -> Switch theme from System to Dark -> Verify dark mode tokens applied -> Clear temporary audio cache -> Verify disk space calculation updates.
6. **S6 (Home Feed Filtering & Swipe Actions)**: Home dashboard -> Filter by "Today" -> Star 2 meetings via leading swipe -> Filter by "Starred" -> Delete an old test meeting via trailing swipe with destructive confirmation alert.
7. **S7 (Folder & Tag Organization)**: Create folder "Product Roadmap" -> Add tags "Q4", "Design" -> Move 3 meetings into folder -> Verify cascading tag search and folder isolation.
8. **S8 (Action Item Management & Reminders Sync)**: Post-meeting detail -> Review 3 extracted action items -> Toggle 1 as completed -> Add manual action item with due date tomorrow and high priority -> Tap "Sync to Apple Reminders" -> Verify sync event dispatched.
9. **S9 (Executive Minutes Multi-Format Export)**: Meeting detail cockpit -> Tap Export -> Generate PDF report -> Verify multi-page layout, summary headers, action item checklist, and attendee list -> Generate Markdown -> Verify header markdown formatting.
10. **S10 (External Audio Import Pipeline)**: Home tab -> Import Audio -> Pick external .m4a file -> Validate file duration and format -> Transcribe audio file -> Trigger extractive summarization -> Produce meeting record with diarized transcript.
11. **S11 (Universal Search & Deep Linking)**: Search tab -> Query "budget approval" -> Receive match in meeting transcript -> Tap search result -> Detail cockpit opens directly to transcript tab with matching sentence highlighted and audio player queued.
12. **S12 (Ask AI Grounded Q&A)**: Detail cockpit -> Open Ask AI sheet -> Prompt: "What did John commit to delivering by Friday?" -> Service queries transcript chunks -> Returns answer citing exact timecode [04:12].
13. **S13 (Email Draft Summary Generator)**: Detail cockpit -> Export -> Email Summary -> Generates clean text with executive summary, decisions, and action items pre-formatted for mail composer.
14. **S14 (App State Restoration)**: Simulate app termination while viewing meeting detail -> Relaunch -> AppState router restores previous cockpit navigation context.
15. **S15 (Onboarding Skip & Defaults)**: User skips profile voice setup -> App defaults to standard system voice profile and loads Home feed with sample welcome meeting.
16. **S16 (Voice Profile Update)**: Settings -> Profile -> Update display name and role -> Re-record voice signature -> Persists to SwiftData.
17. **S17 (Permission Denial Recovery)**: Microphone permission denied -> Custom primer displays instructional alert with direct deep link button to iOS Settings.
18. **S18 (Tab Switching State Preservation)**: Start audio playback on Meeting Detail -> Switch to Action Items tab -> Switch back to Home -> Audio playback continues smoothly without interruption.
19. **S19 (Audio Encoding Bitrate Switch)**: Record meeting under 64kbps Standard mode -> Record second meeting under 128kbps High mode -> Compare AAC output file headers and byte rates.
20. **S20 (Offline Speech Recognition Fallback)**: Disable network simulation -> SFSpeechRecognizer detects offline mode -> Switches seamlessly to on-device neural transcription engine.
21. **S21 (Temporary Cache Purge)**: Generate 50MB of temporary waveform and export cache -> Trigger cache clear in Settings -> Verify cache directory emptied while primary SwiftData audio files remain untouched.
22. **S22 (Dynamic Theme Adaptation)**: Switch theme from Light to Dark -> Inspect Theme.colors background, surface, text, and accent values dynamically adapt without app restart.
23. **S23 (Upcoming Meeting Countdown)**: Upcoming meeting card displays time until start ("Starts in 15 mins") -> Transition to "Happening now" when current time matches meeting start.
24. **S24 (Meeting Status State Machine)**: Scheduled -> Recording -> Processing -> Completed -> Archived. Verify all transitions obey state transition invariants.
25. **S25 (Multi-Filter Combination)**: Apply filters: "This Week" + "Action Items" -> Verify results match intersection of date range and pending tasks.
26. **S26 (Favorite Star Toggle)**: Star meeting -> Star icon turns amber -> Persisted in SwiftData -> Reflected in all subviews immediately.
27. **S27 (New Meeting Modal Dismissal)**: Open New Meeting modal -> Drag down to dismiss -> No draft meetings created in database.
28. **S28 (Meeting Date Validation)**: Schedule meeting with end date prior to start date -> Form presents inline validation error and disables Save button.
29. **S29 (Custom Meeting Template Creation)**: Create custom template "Sprint Retrospective" with sections "What went well", "What didn't", "Action items" -> Apply template to new meeting.
30. **S30 (Duplicate Participant Prevention)**: Add participant with existing email address -> UI alerts duplicate and merges role instead of creating twin contact chips.
31. **S31 (Quick Launch Timestamping)**: Tap Quick Meeting -> Auto-titles meeting as "Meeting - Nov 16, 2:30 PM" -> Begins recording within 150ms.
32. **S32 (Corrupt Audio Import Handling)**: Import corrupted or truncated .wav file -> Import pipeline displays graceful error alert without crashing.
33. **S33 (Folder Deletion Policy)**: Delete folder containing 5 meetings -> Prompt asks whether to move meetings to default inbox or delete -> Move to inbox preserves meeting records.
34. **S34 (Destructive Discard Recording)**: Active recording at 05:20 -> Tap Discard -> Confirmation dialog appears -> Confirm discard -> Temp audio file deleted, database reverted, returns to Home.
35. **S35 (Cross-Meeting Task Aggregation)**: 5 meetings each with 2 action items -> Cross-Meeting Action Console displays all 10 items grouped by Due Date and Priority.
36. **S36 (Search Scope Filtering)**: Universal search with scope filter "Transcripts Only" vs "Action Items Only" -> Validates result filtering accuracy and execution speed.

---

## Coverage Thresholds & Pass Criteria
- **Tier 1 (Feature Coverage)**: ≥5 tests per feature × 55 features = **≥275 tests**.
- **Tier 2 (Boundary & Corner Cases)**: ≥5 tests per feature × 55 features = **≥275 tests**.
- **Tier 3 (Cross-Feature Combinations)**: Pairwise test coverage of all major feature interactions across data models, services, and view models.
- **Tier 4 (Real-World Application Scenarios)**: **36** comprehensive multi-feature user journey scenarios.
- **Pass Criteria**:
  1. `Scripts/verify_project.py` executes and confirms project integrity with 0 errors.
  2. `Scripts/run_unit_tests.py` executes all test suites in `MeetMindTests/` and reports 100% pass (exit code 0).
  3. No mock or test circumvents authentic validation.
