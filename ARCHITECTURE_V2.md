# Manent architecture v2

Status: implementation plan approved by product request, 21 November 2026

## Product contract

Manent is an account-free, local-first iPhone application. Meeting audio, transcripts, minutes, tasks, speaker identities, Vidur history, and processing diagnostics stay inside the app container. Network access is limited to downloading public model files. The user explicitly initiates every export or share operation.

Supported baseline:

- iOS 17 and later.
- SwiftUI, SwiftData, Swift concurrency.
- Offline speech recognition, speaker diarization, and minutes generation.
- Existing user recordings and SwiftData stores must survive upgrades.

Correctness order:

1. Preserve recordings and user edits.
2. Report the true state and a useful recovery action.
3. Finish transcription and minutes even when optional stages such as diarization fail.
4. Optimize speed only after physical-device qualification.
5. Match Figma within native iOS accessibility and local-only constraints.

## Architectural problems being replaced

- `ProcessingPipelineViewModel` contains production, legacy, and simulated pipelines.
- Foreground and background processing do not share one durable job contract.
- String values on `Meeting.analysisState` encode an incomplete state machine.
- Model readiness is a Boolean marker, while verification can still fail later.
- Recording chunk writing awaits inference and may stop draining audio buffers.
- SwiftData, JSON sidecars, UserDefaults, recordings, photos, templates, and checkpoints have independent lifecycles.
- Export has two implementations; one can write plain text with a `.pdf` extension.
- Tests often set UI state directly rather than invoking production orchestration.
- Settings promises complete deletion but leaves private sidecar and checkpoint data.

## Target layers

### 1. App composition

`AppEnvironment` owns live implementations and is the only composition root:

- Meeting repository
- Analysis coordinator
- Model manager
- User-content store
- Export service
- Calendar and reminders adapters
- Diagnostics and clock
- Background-task adapter

Views do not construct production services or reference global singletons. Temporary compatibility adapters are allowed while the transition is in progress.

### 2. Domain

Pure value types describe behavior independently of SwiftUI and SwiftData:

- `MeetingLifecycleState`
- `AnalysisJobSnapshot`
- `AnalysisStage`
- `AnalysisFailure` with stable code, display message, recovery action, and retryability
- `ModelReadiness`
- `MinutesReviewChecklist`
- `DocumentSnapshot`
- `ShareOutcome`

The lifecycle is:

`scheduled → readyToRecord → recording/paused → saved → needsModels/queued/processing/failed → speakerReview → draftReview → finalized`

Notes-only enters at `draftReview`. Share/export and approval are events attached to a finalized document version, not lifecycle states.

### 3. Persistence

For this release, the existing SwiftData graph remains unchanged to protect installed data. New orchestration state uses versioned Codable records in Application Support with atomic writes and file protection. No new `@Model` type is introduced until a versioned SwiftData schema and real legacy-store fixtures exist.

Repositories own all SwiftData reads and mutations. A mutation throws on failure, rolls back optimistic state, and supplies a user-visible error.

Sidecar stores must implement:

- `remove(meetingID:)`
- `eraseAll()`
- versioned decoding
- atomic writes
- corruption reporting rather than silently returning empty state

### 4. Analysis

One `AnalysisCoordinator` serves foreground UI, background tasks, and device diagnostics.

Its durable job record contains:

- meeting UUID and source fingerprint
- job state and current stage
- required model IDs/revisions
- attempt count and timestamps
- stable failure code/message/recovery action
- checkpoint format version
- execution owner lease
- non-sensitive stage metrics

`AnalysisCoordinator` invokes `MeetingAnalysisPipeline` and persists each stage transition. It commits the transcript as soon as transcription succeeds. Diarization is optional: failure yields unnamed speakers and a warning. Minutes generation can be retried without retranscribing.

ASR and diarization run serially by default. Concurrent execution is enabled only by a resource governor after measured device qualification.

### 5. Model lifecycle

Model state is explicit:

- absent
- downloading(progress)
- verifying
- ready
- corrupt(reason)
- incompatible(reason)

A missing/corrupt model never appears as a generic processing failure. The UI names required downloads, sizes, total free-space requirement, and whether network access is required. Repair quarantines corrupt files and installs atomically.

### 6. Recording and media

The canonical recorder writes the full audio file directly from the audio callback. A separate `RecordingChunkPump` only drains buffers and seals local chunks; it never awaits inference. A bounded preprocessing worker consumes sealed URLs opportunistically and can be cancelled immediately when Stop is tapped.

All media uses paths relative to a single `UserContentStore` root. Meeting deletion and erase-all remove audio, photos, preparation chunks, checkpoints, exports, and sidecars through one journaled coordinator.

### 7. Documents, share, and approval

`DocumentSnapshot` is the one reviewed representation of minutes. Minutes Studio, text export, PDF export, sharing, and approval use the same snapshot and finalization fingerprint.

- Generic activity completion is recorded as Shared or Exported.
- “Sent to …” is used only when Mail confirms `.sent`.
- Editing agenda, attendance, discussion, decisions, or action items invalidates finalization and returns the document to Draft.

### 8. Navigation and presentation

Top-level tabs remain Meetings, Actions, and Search. Settings is pushed from the profile button and is not a restorable phantom tab.

Each meeting UUID resolves to exactly one state-driven destination:

- Plan
- Capture setup
- Recording
- Processing
- Review checklist
- Final minutes

The router selects the destination from persisted lifecycle state; call sites do not guess.

### 9. Diagnostics and privacy

Diagnostics contain no transcript or audio content. They may include:

- build commit
- meeting UUID hash, not title
- stage and stable failure code
- model revision and verification state
- source audio duration/format/file size
- elapsed time, thermal state, low-power state, and memory admission decision

Errors shown to users persist across relaunch. Logs redact paths and titles.

## UI flow

### First launch

1. Record, Minutes, Vidur onboarding cards.
2. Local Profile (optional name/photo/role).
3. Capability Setup: microphone, speech recognition for live captions, notifications, calendar. Each permission is optional and explains its effect.
4. Meetings.

No sign-in, email verification, account deletion, or workspace-switching UI.

### Create meeting

Meetings `+` → Quick Meet / Schedule / Import.

- Quick Meet → Capture Setup → Recording or Notes Only.
- Schedule → Meeting Plan → Save → Meetings; Start Recording from the plan.
- Import → validate format/size/free space → copy → Processing.

### Processing

Processing presents one of these mutually exclusive states:

- Models Required: names, total size, free space, Download & Continue.
- Downloading / Verifying.
- Queued: Process Now.
- Running: Transcribing, Identifying Speakers, Writing Minutes, Saving.
- Failed: exact problem plus Retry, Repair Model, Change Language, or Open Transcript.
- Speaker Review: assign voices or keep unknown, correct transcript, continue.
- Complete → Review Checklist.

### Review and finalization

Review Checklist shows outstanding work with direct links:

- transcript available and corrected
- voices named or explicitly accepted as unknown
- suggested actions reviewed
- agenda and attendance checked
- decisions checked

Finalize stores the document fingerprint. Any material edit returns it to Draft.

### Final minutes

Minutes / Actions / Decisions segments. Secondary destinations are Transcript & Audio, People, Minutes Studio, Vidur, Series Comparison, Share & Export, and Approval.

### Settings

- Profile & Privacy
- Models
- Storage (recordings, models, templates, cache, total size)
- Integrations (Calendar, Reminders, Notifications)
- Vidur
- Appearance & Accessibility
- Diagnostics
- Erase All Local Data

## Implementation stages

### Stage A — Reliability and truthful state (release blocker)

- Introduce durable analysis job/failure records and coordinator.
- Use the coordinator from foreground, background, and diagnostics.
- Commit transcript after ASR, tolerate diarization failure, and retry stages independently.
- Add model readiness/repair and a Models Required UI state.
- Remove or isolate production simulation APIs.
- Default ASR/diarization to serial execution.

Acceptance: a saved recording can be retried after relaunch; a diarization failure still produces transcript/minutes; the exact failure survives relaunch.

### Stage B — Data lifecycle and export safety

- Introduce user-content inventory and journaled deletion.
- Add `remove(meetingID:)` and `eraseAll()` to every sidecar.
- Delete attachments before deleting Note rows.
- Make meeting deletion remove all owned assets.
- Replace invalid PDF fallback with one real document renderer.

Acceptance: erase-all leaves public models but no private content; every exported PDF has a PDF header and opens; cancellation never records “sent.”

### Stage C — Canonical UI journey

- State-driven meeting destination and Review Checklist.
- Consolidate speaker identity editing.
- Consolidate repeat/follow-up behavior.
- Restore Vidur history and open cross-meeting citations.
- Correct Search suggestion semantics and deep links.
- Add missing loading, empty, permission, storage, and error states.

Acceptance: every Figma-active screen has an entry path and back path; no remote/account copy remains; VoiceOver and Dynamic Type do not block primary actions.

### Stage D — Recording isolation and performance

- Split chunk draining from inference.
- Stop promptly without waiting for preprocessing.
- Add interruption/stopped-unsaved/retry-save states.
- Add resource governor and content-free metrics.

Acceptance: Stop returns promptly under blocked preprocessing; canonical audio duration remains within 1% of wall-clock capture; process survives qualified clips on iPhone 15.

### Stage E — Migration and release qualification

- Freeze current schema as V1 and capture synthetic legacy store fixtures.
- Add a versioned migration plan before the next model change.
- Gate IPA publication after all tests.
- Add physical-device pipeline qualification for synthetic and multi-speaker Hinglish fixtures.

Acceptance: old synthetic stores open without data loss; release artifact is published only after tests; physical-device pipeline reloads persisted output from a fresh context.

## Release definition

A release is complete only when:

- static verification passes
- package tests and XCTest pass
- simulator cold-launch/UI smoke passes
- IPA validates
- on-device storage check passes
- on-device production pipeline processes a known clip through a fresh-context reload
- a real multi-speaker recording completes or produces a specific recoverable error
- erase-all and export safety tests pass

A green UI screenshot is not processing qualification.
