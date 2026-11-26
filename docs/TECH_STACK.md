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

## Transcription and minutes architecture

Pipeline, in order:

```
Recording
  -> Whisper large-v3 turbo transcription in the spoken language
       (prompt = agenda terms + attendee names via SpeechVocabulary,
        per-meeting language memory, live-caption cross-check)
  -> diarization (FluidAudio, separate model)
  -> Hindi detection per turn
  -> Qwen3 1.7B text translation of Hindi turns to English
       (validated: numbers and names must survive; the original Hindi turn is always kept)
  -> chunked grounded extraction (Qwen3 1.7B + deterministic rules)
  -> reducer (merges model output with the rule extractors)
  -> deterministic overview, at most one checked model sentence
  -> every item's evidence maps back to the original words, plus a language note
       that says which turns were machine translated
```

Why each step is built this way:

- **Transcribe in the spoken language, translate as a separate text step.** Whisper large-v3 turbo was
  fine-tuned without translation data, so its built-in translate task is not expected to work well
  ([openai/whisper discussion 2363](https://github.com/openai/whisper/discussions/2363)). Hindi audio is
  therefore transcribed as Hindi and translated by the text model, which sees the whole turn and can be
  checked.
- **Context-primed ASR.** Commercial speech-to-text works the same way. OpenAI's speech-to-text accepts a
  free-text prompt, keyword hints and expected languages, carries context from the previous chunk of long
  audio, returns detected languages, and offers diarization as a separate model
  ([OpenAI speech-to-text guide](https://developers.openai.com/api/docs/guides/speech-to-text)). Wispr Flow
  runs cloud ASR plus an LLM formatting pass within roughly 700 ms, conditions the ASR on context (speaker,
  surrounding text, user history), learns from corrections, calls code-switching a hard open problem, and
  invests in showing uncertainty
  ([Wispr Flow technical challenges](https://wisprflow.ai/post/technical-challenges)). Manent applies the
  same layers on the phone: agenda and names prime Whisper, language is remembered per meeting, speakers
  are separated by a different model, and a text LLM formats and extracts.
- **Honest about uncertainty.** The original Hindi is never replaced. Translated turns are listed in the
  result, turns that failed validation are listed as untranslated and fall back to the Hindi phrase rules,
  and the minutes carry a language note. Evidence quotes point at the original words.
- **One resident LLM.** Qwen3 1.7B does translation, extraction and Vidur answers, so only one language
  model has to fit in memory next to the speech model. Qwen3.5 2B stays available only as
  `--model qwen-3.5-2b` for comparison. On the same saved transcripts it was about 3.4x slower per run
  (minutes generation 93 s vs 23 s, 190 s vs 53 s, 221 s vs 77 s on three test recordings) with no gain in
  accuracy.
- **Rules where a small model is weak.** Owners, deadlines, cancellations and Hindi requests come from
  deterministic extractors. The overview is composed from checked items, with at most one model sentence
  that must pass grounding checks.

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

### In CI (every push)
Release build, about 1,100 app tests, engine tests (minutes, Hindi, Vidur fixtures), launch smoke test with
screenshots, IPA privacy and encryption checks. The synthetic-audio accuracy run (`eval.yml`) is manual only,
because CI Macs have no Neural Engine.
