# MeetMind

Native iOS 17+ meeting recorder built with SwiftUI and SwiftData. No account is
required; recordings, transcripts, notes, photos, and summaries are stored locally.

See [REPAIR_NOTES.md](REPAIR_NOTES.md) for the confirmed launch-crash diagnosis,
repairs, verification evidence, and remaining limitations.

## Features

- AAC recording, live microphone metering, pause/resume, and persistent audio.
- Offline multilingual Whisper transcription after recording; optional on-device Apple Speech live preview.
- Local Qwen-generated English discussion points, decisions, and source-linked task suggestions requiring review.
- Transcript editing, manual speaker attribution, playback, notes, and photos.
- Meeting scheduling, audio import, filtering, and cross-meeting search services.
- Action checklists, categories, and optional export to on-device Apple Reminders lists.
- PDF sharing, Markdown export, and email-draft text.

On-device recognition depends on device/language support and installed speech
models; unavailable local recognition fails visibly rather than using cloud speech.
Calendar and iCloud sync are not provided. Saved meeting storage is excluded from
device backups; sharing and Reminders export are explicit user actions.

Build 7 integrates offline WhisperKit transcription, FluidAudio speaker separation,
and local Qwen analysis into saved-meeting processing, with explicit model setup,
protected resume checkpoints, and human review before generated tasks are saved.
Build 10 uses the compact 4B trial profile after device comparisons exposed missed
commitments in the 1.7B candidate. Settings includes model management and a separate diagnostics lab. Real Hinglish
accuracy and long-meeting performance remain unqualified. See
[OFFLINE_QUALIFICATION.md](OFFLINE_QUALIFICATION.md) for device measurements and
outstanding Hinglish quality gates.

## Build and test

Use Xcode 26+ with Swift 6.2+ on macOS. Before opening the project, prepare the
checksummed native runtime and its matching simulator slice:

```sh
bash Scripts/prepare_llama.sh
```

Open `MeetMind.xcodeproj`, select the MeetMind scheme and an
iOS 17+ simulator or signed iPhone destination. Build with Cmd+B; run Swift XCTest
with Cmd+U. GitHub Actions also builds the Release app and runs simulator tests
and repeated-launch checks. Inspect the complete workflow outcome, not just the
compilation step.

Cross-platform structural checks:

```sh
python -X utf8 Scripts/verify_project.py
python Scripts/validate_ipa.py MeetMind/Resources/Info.plist
python Scripts/validate_ipa.py path/to/MeetMind.ipa
```

`Scripts/run_unit_tests.py` is a legacy Python domain simulation. It does not
compile or execute the Swift app and cannot certify iOS behavior.

## Sideloading

Download the IPA artifact for the current successful GitHub Actions run. The
artifact is **unsigned** and must be re-signed by Sideloadly or equivalent for your
device. Update using the same signing account and bundle identifier to preserve
app data. The old local `build/MeetMind.ipa` predates these repairs and should not
be used for verification. Do not commit IPA files or build outputs.

## Repository layout

- `MeetMind/App`: lifecycle and routing
- `MeetMind/Models`: SwiftData entities
- `MeetMind/Services`: audio, speech, persistence, summaries, export, integrations
- `MeetMind/ViewModels` and `MeetMind/Views`: app behavior and SwiftUI screens
- `MeetMind/DesignSystem` and `MeetMind/Resources`: UI tokens and bundled assets
- `MeetMindTests`: Swift XCTest unit and integration suites
- `OfflineEngineKit`: pinned local engines, model manifests, and qualification tests
- `Scripts`: project, package, and simulator launch checks
