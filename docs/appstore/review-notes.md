# App Review notes (paste into App Store Connect, "App Review Information")

## Notes text

```
Manent records meetings and writes minutes entirely on the device. There is no account, no sign-in and no server, so no demo credentials are needed.

HOW TO TEST
1. Launch and tap through onboarding. Allow Microphone and Speech Recognition when asked. Calendar, Reminders and Camera are optional and only requested if you use those features.
2. Models: the first analysis downloads the on-device models it needs (the app shows progress). You can also download them in advance from Settings (Profile) > Offline Analysis Models. Sizes: Whisper small about 489 MB, Whisper large about 629 MB, speaker model about 22 MB, minutes model (Qwen3 1.7B, Qwen_Qwen3-1.7B-Q4_K_M.gguf) about 1.3 GB. Use Wi-Fi. Models come from huggingface.co and each file is checked against a SHA-256 hash. This is the app's only network use.
3. Tap Record, speak for 30 to 60 seconds (any language; Hindi and English are supported), then stop. Live captions appear while recording. Minutes are written on the device afterwards.
   - Suggested test audio if you prefer not to speak: play any short two-person conversation from another device near the microphone, or use Import Audio with an audio file from the Files app.
4. Open the finished meeting to see the summary, decisions and action items, then try Export (PDF) and Vidur (ask "What were the action items?").

WHY EACH CAPABILITY IS NEEDED
- Microphone: the core feature is recording meetings.
- Speech Recognition: live captions during recording, using Apple's on-device recognizer (requiresOnDeviceRecognition is set; no audio is sent to Apple).
- Background audio (UIBackgroundModes audio): a meeting recording must continue when the screen locks or the user switches apps. Recording is always started by the user and iOS shows its recording indicator.
- Background processing (UIBackgroundModes processing, BGTaskScheduler): after a meeting, the app transcribes and writes minutes on the device, which can take several minutes. A BGProcessingTask lets iOS finish an interrupted analysis. On iOS 26 the app uses a continued processing task for analysis the user started.
- Calendar (full access): optional. Shows upcoming meetings to record and adds a follow-up event when the user asks.
- Reminders (full access): optional. Exports action items the user selects and keeps their completed state in sync.
- Camera and Photos: optional. Attach whiteboard or slide photos to a meeting.

PRIVACY
All recordings, transcripts and minutes stay on the iPhone. No analytics, no tracking, no ads. The privacy manifest declares no collected data. Encryption: only standard HTTPS and Apple system cryptography (ITSAppUsesNonExemptEncryption = NO).

OFFLINE
After the models are downloaded, every feature works in airplane mode. Before the models are downloaded, recording and live captions work, but minutes need the models.

OPEN SOURCE
Whisper (MIT), WhisperKit (MIT), FluidAudio (Apache 2.0), llama.cpp (MIT), Qwen3 (Apache 2.0), pyannote segmentation (MIT), WeSpeaker (CC BY 4.0). Licences are in Settings > About and Licences.
```

## Reviewer setup checklist (do this before submitting)

- Test the exact build on a physical iPhone with a clean install, including the model download over Wi-Fi.
- Confirm there is a visible message and a retry when the download fails or storage is low.
- Make sure the notes name the same model sizes the app shows. Sizes come from `OfflineEngineKit/Sources/OfflineEngineKit/Resources/models.json`.
- Attach a 60 to 90 second screen recording of the flow (App Store Connect allows an attachment up to 4 files). It helps because review devices may be slow to download 1.3 GB.
- Put the support email in the "Contact" fields.

## Likely reviewer questions and answers

| Question | Answer |
|---|---|
| Does the app record other people? | It records meetings the user chooses to start. The app shows an on-screen recording state. The user is responsible for obtaining consent where the law requires it. The description states this. |
| Why a large download? | The AI models run on the device so no audio leaves it. |
| Is there AI-generated content? | Minutes and Vidur answers are generated on-device and are labelled as drafts to review. |
| Where is the account? | There is none by design. |
