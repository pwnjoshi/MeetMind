# MeetMind

An intelligent, production-grade meeting intelligence application for iOS 17+ built natively in SwiftUI.

MeetMind transforms your meetings through real-time audio recording, dynamic waveform visualization, live streaming transcription, on-device extractive summaries, automated action item tracking with Apple Reminders synchronization, synchronized audio scrubbing, and universal cross-meeting search.

## Features

- **Real-Time Audio Recording**: High-fidelity AAC recording via `AVAudioEngine` with 60Hz linear power metering.
- **Dynamic Waveform Visualizer**: Smooth, reactive 32-bar visualizer mirroring microphone input.
- **Live Diarized Transcription**: Streaming speech recognition powered by Apple's `Speech` framework with offline neural engine fallback.
- **Intelligent Summaries & Decisions**: Dual-engine synthesis using Apple `NaturalLanguage` and structured JSON intelligence models.
- **Action Items & Reminders Sync**: Interactive task checklists with one-tap sync to Apple Reminders (`EventKit`).
- **Synchronized Playback Engine**: Variable playback speed (0.75x–2.0x) with pitch correction and tap-to-seek transcript scrubbing.
- **Multi-Format Export**: Professional PDF minutes generation (`UIGraphicsPDFRenderer`), Markdown, and email summaries.
- **Universal Search**: Deep full-text search across meeting titles, spoken sentences, and action items.

## Architecture

- **Clean Architecture + Protocol-Oriented MVVM + Observation (`@Observable`)**
- **Persistence**: SwiftData (`@Model`) with relational schemas and cascade delete rules.
- **Strict Concurrency**: Built with Swift 5.9 strict concurrency checking (`SWIFT_STRICT_CONCURRENCY = complete`).
- **Test-Driven Design**: Protocol abstractions with full mock implementations for deterministic automated testing.

## Requirements

- **iOS**: 17.0+
- **Xcode**: 15.0+
- **Swift**: 5.9+

## Project Layout

```
MeetMind/
├── App/                 # App lifecycle, state router, navigation
├── DesignSystem/        # Color, typography, and spacing tokens + reusable UI components
├── Models/              # SwiftData entities (Meeting, Transcript, Speaker, Summary, ActionItem)
├── Services/            # Audio recording/playback, Speech transcription, Summarization, Export
├── ViewModels/          # Observable view models for dashboard, recording, cockpit, search
├── Views/               # SwiftUI screens, cards, modals, and player bars
└── Resources/           # Assets catalog and Info.plist
MeetMindTests/           # Unit, integration, and E2E test suites
Scripts/                 # Verification and test runner scripts
```

## Building and Testing

1. Open `MeetMind.xcodeproj` in Xcode 15+.
2. Select target `MeetMind` and choose an iOS 17+ Simulator (e.g. iPhone 15 Pro).
3. Press `Cmd + B` to build, or `Cmd + R` to run.
4. Press `Cmd + U` to execute the automated unit test suite.

To verify project structure and run tests via command line:
```bash
python Scripts/verify_project.py
python Scripts/run_unit_tests.py
```
