# Evaluating a Manent build on real meetings

This measures one build on a fixed set of recorded meetings so two builds can be compared. It reports:

- transcript error per language and script (word error on Latin words, character error on Devanagari, and a script-agnostic word error)
- whether each turn was written in the right script
- speaker attribution error
- task, decision and open-issue precision, recall and F1
- owner and deadline accuracy on tasks that matched
- time per stage, real-time factor, and peak memory

Nothing here changes how the app behaves for users. The on-device run is a hidden launch mode (`--offline-evaluation`) that only a USB launch can start. It uses no meeting database and keeps its checkpoints in a temporary folder, so saved meetings are never read or changed.

## Golden set layout

One folder per meeting. The folder name is the meeting id (letters, digits, `-`, `_`).

```
golden/                      (git-ignored; keep it private)
  2025-02-04-standup/
    audio.m4a                (or audio.wav)
    labels.json
  2025-02-06-vendor-call/
    audio.wav
    labels.json
```

### labels.json

```json
{
  "id": "2025-02-04-standup",
  "languages": ["en", "hinglish"],
  "speakers": [{"label": "S1", "name": "Neha"}, {"label": "S2", "name": "Pawan"}],
  "turns": [
    {"start": 0.0, "end": 6.4, "speaker": "S1", "lang": "en",
     "text": "Hi Pawan, let's start with the launch date."},
    {"start": 6.4, "end": 12.0, "speaker": "S2", "lang": "hinglish",
     "text": "haan theek hai, main kal tak agenda bhej dunga"}
  ],
  "tasks": [{"title": "Send the agenda", "owner": "Pawan", "deadline": "tomorrow"}],
  "decisions": ["Launch on 20 November"],
  "openIssues": ["Marketing budget is not decided"],
  "participants": ["Neha", "Pawan"],
  "agenda": ["Launch date", "Vendor", "Budget"]
}
```

| Field | Meaning |
|---|---|
| `turns[].start/end` | Seconds from the start of `audio.*`. Each turn is one speaker's continuous speech. Accuracy to about 0.5 s is enough. |
| `turns[].speaker` | A `speakers[].label`. |
| `turns[].lang` | `en`, `hi` (Hindi), or `hinglish` (mixed). Used to group the error rates. |
| `tasks[]` | Every real commitment or request, with `owner` (a name or `null`) and `deadline` as spoken (`"Friday"`, `"kal tak"`, `"2025-11-20"`, or `null`). |
| `decisions[]`, `openIssues[]` | One short sentence each, in English or the meeting's language. |
| `participants` | Named attendees. Passed to the app as the attendee list, as a user would enter them. If empty, the speaker names are used. |
| `agenda` | Agenda points entered before the meeting. Passed to the app. Leave `[]` if the meeting had none. |

`Scripts/eval_labels_from_transcript.py` builds this file from a plain transcript (see below). Tasks, decisions, open issues and agenda are always filled in by hand.

## Labelling guide

**Transcribing Hinglish.** Write what a careful reader would expect to see in the app:

- Hindi words in Devanagari, English words in Latin script, inside the same sentence: `मुझे लगता है हमें 20 November को launch करना चाहिए।`
- Keep English words English even when they sit inside Hindi grammar (`budget`, `vendor`, `presentation`). Do not transliterate them into Devanagari.
- Use the same spelling for the same word everywhere. Use Devanagari digits only if the speaker spelled the number out in Hindi words; otherwise write digits as `20`.
- A turn spoken fully in Roman-script Hindi (`haan theek hai`) is allowed when the speaker's whole turn is conversational Hinglish and you want it scored script-agnostically. Mark it `hinglish`. The scorer reports script correctness separately, so choose one style per project and keep it.
- Names: write them the way the attendee list spells them.
- Skip fillers (`um`, `hmm`) and false starts. Keep numbers, dates and names exact.
- The nukta dot is ignored when scoring (`ज़` and `ज` compare equal), so do not spend time on it.

**What is a task.** A commitment or request that someone will do something after the meeting: "Pawan, please send the agenda by Friday", "I will share the deck tomorrow". Not tasks: things already done, ideas nobody picked up ("we could maybe look at it"), cancelled work ("don't do the redesign now"), and general discussion. Write the title as a short imperative phrase. Set `owner` only when the meeting makes it clear who; otherwise `null`. Set `deadline` only when a time was spoken.

**What is a decision.** Something the group explicitly settled: "let's go with the Pune vendor", "launch is 20 November". One decision per entry. A proposal that was not accepted is not a decision.

**What is an open issue.** A question raised and left unresolved, or deferred to later: "budget is not decided, we'll discuss it next meeting".

**Speakers.** Two to five people. Use consistent labels across the whole meeting. Overlapping speech: label the main speaker and leave the interruption out of `turns`.

**Consent.** Record only meetings where every participant has agreed, in writing or on the recording itself, to use of the audio and transcript for testing this app. Do not record anyone who has not agreed. Keep `golden/` off shared drives and out of git (it is git-ignored). Remove the audio from the iPhone after a run with `--clean-device`. Do not paste real meeting content into issues, chats or CI logs. Prefer first names or aliases in `labels.json`.

**Coverage.** For 10 to 15 meetings, aim for roughly: a few in English, a few in Hindi, most in Hinglish; two to five speakers; some quiet rooms and some noisy ones; at least one meeting with no tasks.

## Make labels.json from a transcript

Write the transcript once, with timestamps:

```
[00:00] Neha: Hi Pawan, let's start with the launch date.
[00:06] Pawan: haan theek hai, main kal tak agenda bhej dunga
```

```
python Scripts/eval_labels_from_transcript.py transcript.txt --id 2025-02-04-standup --duration 1840 --out golden/2025-02-04-standup/labels.json
```

Turn ends are the next turn's start. `lang` is a guess from the script and a few Roman Hindi words, so review it. Then add `tasks`, `decisions`, `openIssues` and `agenda`.

## Run an evaluation, step by step

1. Install the build to test on the iPhone, with the offline models already downloaded (do this once from the app's meeting setup). Unlock it, trust the computer, and keep it on charger with Low Power Mode off. The run refuses to start when the phone is hot.
2. Record the meetings (with consent). Export each audio file to your computer as `.m4a` or `.wav` (up to 60 minutes per file).
3. Create `golden/<id>/audio.m4a` and `golden/<id>/labels.json` for each meeting.
4. From the repository root, using the device-tools virtualenv:

   ```
   build\device-tools\Scripts\python.exe Scripts\device_eval.py --golden golden --clean-device
   ```

   It pushes the folders, launches MeetMind with `--offline-evaluation`, and prints `MEETMIND_EVAL` progress lines. Keep MeetMind in the foreground and the screen on until it prints `completed`. A 30-minute meeting takes several minutes. Then it pulls each `result.json` into `build/eval/runs/<commit>/<id>/` and scores them.
5. Read `build/eval/report-<commit>.md`. The machine-readable numbers are in `build/eval/summary-<commit>.json`.
6. After changing the code, build and install again, rerun step 4, and compare:

   ```
   python Scripts/eval_score.py --compare build/eval/summary-OLD.json build/eval/summary-NEW.json
   ```

   Each metric is marked `better`, `same`, or `WORSE`.

Useful options: `--only id1,id2` (subset), `--language hi` (force the transcription language instead of automatic detection), `--skip-run` (pull and score what is already on the phone), `--skip-push` (files already on the phone), `--task-source rawTasks` (score the reducer's raw tasks instead of the minutes actions).

Scoring alone, from results you already have: `python Scripts/eval_score.py --golden golden --results build/eval/runs/<commit>`.

## How the numbers are defined

- **Alignment.** Each recognised turn is assigned to the labelled turn it overlaps most in time (nearest by midpoint when none overlaps). Errors are pooled per language, never averaged across meetings.
- **WER Latin.** Word edit distance over the Latin-script words only. **CER Devanagari.** Character edit distance over Devanagari characters only (spaces and punctuation removed, nukta ignored).
- **WER Roman.** Both sides are transliterated to a Roman skeleton (Devanagari to ISO-like Roman, then spelling variants such as `ph/f`, `w/v`, `ee/i`, `e/i`, `o/u` and doubled letters are folded). It credits a correct word even if the app wrote it in the other script, and is deliberately lenient about spelling.
- **Right script.** A turn passes when its share of Devanagari words is within 0.35 of the labelled turn's share.
- **Speaker error.** Time-weighted over labelled speech: seconds with no recognised speaker plus seconds with the wrong speaker, divided by labelled speech seconds, after the best one-to-one mapping from the app's `Speaker N` labels to your labels (tried exhaustively for up to 8 speakers).
- **Tasks, decisions, open issues.** An item matches when the content-word overlap (Dice over word sets, near spellings and cross-script words count) is at least 0.6; matching is one-to-one. Precision and recall are pooled over all meetings. An empty side counts as 1.0 when the other side is also empty.
- **Owner, deadline accuracy.** Over matched tasks only. Owner matches on any shared name token. Deadline matches on word overlap of at least 0.5, or an exact resolved `dueDate`. No owner/deadline expected and none given counts as correct.
- **Timings.** From the app's own stage timers. Real-time factor is processing time divided by audio length. Peak memory is the highest `phys_footprint` sampled every 200 ms, so it is a lower bound of the true peak.

## What the on-device run does and does not cover

It runs the same transcription, speaker separation and minutes code as the app's final analysis pass, with the app's selected analysis model. It does not reproduce analysis during recording (pre-analysis chunks), the live captions, or any names a user assigns to speakers afterwards. Results from the simulator or a different iPhone are not comparable.

## Files

| File | Purpose |
|---|---|
| `Scripts/device_eval.py` | Push, launch, pull, score over USB |
| `Scripts/eval_score.py` | Scorer, report writer, `--compare` |
| `Scripts/eval_labels_from_transcript.py` | Transcript to labels skeleton |
| `Scripts/test_eval_score.py` | Scorer tests (run in CI) |
| `MeetMind/Services/Evaluation/` | On-device runner and hidden launch view |
| `OfflineEngineKit/.../Evaluation/MeetingEvaluation.swift` | Pipeline run, memory sampler, result format |

## Automatic evaluation on every build (simulator, synthetic meetings)

`.github/workflows/eval.yml` builds the app for the iOS Simulator, installs the three analysis models, speaks eight synthetic meetings with macOS `say`, runs `--offline-evaluation` in the simulator, scores the results and writes the report to the job summary and the `offline-evaluation-report` artifact. It runs on manual dispatch and on pushes to `codex/complete-offline-meeting-flow`. It is a separate workflow, so a failure never blocks the IPA build.

| File | Purpose |
|---|---|
| `Scripts/synth_meetings.py` | Generates `audio.wav` + `labels.json` for eight meetings (English, Hindi, Hinglish, 1 to 4 speakers) |
| `Scripts/ci_install_models.py` | Downloads and verifies whisper-large, diarization and qwen-1.7b, installs them into the simulator app container |
| `Scripts/ci_sim_eval.py` | `preflight` (models and memory visible to the app), `run` (push, launch, follow, collect, score), `summary` |

Simulator timings use the CPU only. Compare them between builds, never with an iPhone. Synthetic speech is cleaner than real rooms, so accuracy here is an upper bound. Run `python3 Scripts/synth_meetings.py --out golden-synth` on a Mac to get the same meetings for a USB run.