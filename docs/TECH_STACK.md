# Manent technology stack and how to test it

Everything runs on the iPhone. No account, no server, no cloud AI. The only network use is the
one-time model download from Hugging Face.

## App

| Layer | Technology |
|---|---|
| UI | SwiftUI (iOS 17+, iOS 26 Liquid Glass where available), iPhone only |
| Data | SwiftData (meetings, people, actions, summaries) plus small JSON side files (checkpoints, records, MoM, voice profiles), all protected and excluded from backup |
| Background | iOS 26 continued-processing task (Lock Screen progress), BGProcessingTask fallback |
| Engine | Swift package `OfflineEngineKit` |

## Models (total download about 1.9 GB)

| Job | Model / API | Size | Runs on |
|---|---|---|---|
| Live captions while recording | Apple SpeechAnalyzer + SpeechTranscriber (iOS 26), English (en-IN) and Hindi (hi-IN) together, a language arbiter picks per phrase; SFSpeechRecognizer on-device on older iOS | system | Neural Engine |
| Final transcript | Whisper large-v3 turbo (626 MB build) via WhisperKit / Core ML. Audio split at pauses; each region detects its own language | 629 MB | Neural Engine (+ CPU for the mel step) |
| Speakers | FluidAudio offline diarization (segmentation, WeSpeaker embeddings, VBx clustering) | 22 MB | Neural Engine / CPU |
| Speaker names | Voice profiles from the same embeddings, cosine match + optimal assignment | none extra | CPU |
| Minutes (tasks, decisions, open issues, summary) | Deterministic Hindi/English rules + Qwen3 1.7B Q4_K_M via llama.cpp, grammar-constrained JSON, prompt prefix reuse | 1.28 GB | GPU in the app, CPU in the background |
| Vidur answers | Instant structured answers + retrieval (BM25 + metadata filters + rank fusion) over minutes and transcript windows, then the same Qwen3 1.7B for open questions, streamed | none extra | GPU |

## Why these choices

- **Light:** one language model shared by minutes and Vidur; only one large model is loaded at a time;
  the speech model is kept warm between recording chunks and released before the language model loads.
- **Accurate:** Whisper large-v3 turbo is the most accurate on-device Hindi/English option at this size;
  rules handle what the small model gets wrong (owners, deadlines, Hindi requests, cancellations);
  every task and decision must quote the transcript exactly or it is dropped.
- **Fast:** recording-time transcription of 30 s chunks; fast grammar sampling (2.5x faster minutes);
  instant answers for factual Vidur questions.

## Measured on iPhone 15 (latest runs)

| Check | Result |
|---|---|
| English 4 s clip, warm | transcript 3.8 s, minutes 7.2 s |
| Hindi 74 s dialogue | transcript 40–108 s, minutes 49–56 s, no fallback |
| Vidur | not yet measured on device (log line `Vidur answer tier=… first_token_ms=… total_ms=…`) |

## How to test

### On the iPhone (connected by USB, app installed)
1. `build\device-tools\Scripts\python.exe Scripts\device_benchmark.py --storage-check` — store opens.
2. `build\device-tools\Scripts\python.exe build\capture_analysis_log.py` — English pipeline + timings.
3. `build\device-tools\Scripts\python.exe build\capture_hindi.py` — Hindi dialogue, tasks, decisions, timings.
4. Real meetings: put `audio.m4a` + `labels.json` in `golden\<id>\` (see `docs/EVALUATION.md`) and run
   `build\device-tools\Scripts\python.exe Scripts\device_eval.py --golden golden --clean-device`
   for word error rate (English and Hindi separately), speaker error, task/decision precision and recall.

### Manual test checklist
- Record 2 minutes switching English and Hindi: captions follow the language; the transcript writes English
  in English and Hindi in Devanagari.
- Finish: processing starts by itself; leave the app; Lock Screen shows progress; notification on finish.
- Meeting record: Minutes / Actions / Decisions are correct, owners and deadlines set, no duplicates.
- Name speakers once; record again with the same people: names suggested by voice.
- Vidur: "hi", "what did we decide about X?", "what are my tasks?", "how did the budget discussion go?",
  "schedule a review tomorrow at 4 with Maya". Check sources and that nothing is invented.

### In CI
Pull-request and main-branch CI builds the Release app, runs app and engine tests, captures launch-smoke
screenshots, and checks IPA privacy and encryption metadata. The full synthetic-audio accuracy workflow
(`eval.yml`) is manual only because CI Macs have no Neural Engine; it does not run on every push.
