# Offline intelligence qualification

Status: **NOT QUALIFIED — no real-device model measurements or held-out audio collected.**
The existing application still uses Apple Speech and heuristic extraction. These
tools do not install or activate replacement inference engines.

## Locked product requirements

- Regular iPhone 15 (`iPhone15,4`), Hindi/English mixed, 2–6 participants, ≤60 minutes.
- Preserve original-language transcript; English summaries and task suggestions.
- One-time public-model download; no meeting-content uploads, no account.
- Accuracy-first post-meeting processing. User reviews suggestions before acceptance.
- Categories: Follow-up, Research, Create/Update, Review/Approve, Coordination, Other.
- Model candidates: WhisperKit multilingual small and compressed large-v3
  (`large-v3-v20240930_626MB`); FluidAudio offline diarization; llama.cpp
  Qwen3-1.7B/4B Q4_K_M with thinking disabled.
- Do not pick a winner before measuring. Freeze exact engine revisions, model
  checksums, licenses, prompt version, and normalization rules before held-out evaluation.

## Qualification input

Run locally (no network libraries are used):

```powershell
python Scripts/evaluate_offline.py build/private-evaluation/report.json
python -m unittest discover -s Scripts -p test_evaluate_offline.py
```

Keep all real recordings, text, annotations, and reports inside the ignored
`build/private-evaluation/` directory. Do not commit them or upload them to Actions.
Keep a separate development set; never tune against held-out annotations.

The report is a JSON object with `schema_version: 1`, `device: "iPhone15,4"`,
`airplane_mode: true`, human `reviewer`, `normalization_aliases` (explicit token
equivalences), `engines` and `cases`. Each engine (`asr`, `diarization`, `analysis`)
must include a pinned `revision` and model `sha256`.

Each case must include:

| Field | Meaning |
| --- | --- |
| id, split | Unique recording ID, `held_out` |
| scenarios | Coverage tags listed below |
| consented, human_reviewed | Explicit booleans |
| duration_seconds, participants | Source recording properties |
| reference_text, predicted_text | Human transcription and engine transcription |
| turns | Object mapping source turn IDs to exact original text |
| reference_task_ids | IDs of human-annotated actionable commitments |
| tasks | Predictions, including false positives |
| decisions | Generated decisions, including unsupported ones |
| summary_factual, summary_readable_english | Human review booleans |
| diarization_error_seconds | Missed speech + false alarm + speaker-confusion duration |
| diarization_reference_seconds | Reference speaker-time denominator, counting overlap |
| processing_seconds, peak_memory_bytes, crashed | Target-device measurements |

Task predictions contain unique `id`, nullable `matched_reference_id` (human
semantic adjudication), nullable `owner`/`date`, `owner_correct`/`date_correct`,
`supported`, and `evidence: [{"turn_id": "...", "quote": "..."}]`.
One reference can match at most one prediction. Decisions require `supported` and
the same evidence format. Preserve every prediction; dropping false positives
would invalidate precision. Valid substring citations do not establish entailment:
the human `supported` judgment is required separately.

## Gates and selection

The scorer fails closed on missing measurements. Require ≥20 held-out recordings,
≥3 hours total, and a six-person ≥60-minute fixture. WER ≤25%, DER ≤20%, task
precision ≥90%, recall ≥80%, populated owner/date correctness ≥90%, all task and
decision evidence valid/supported, and all summaries factually reviewed/readable.
No-task recordings are required in the corpus but cannot alone establish recall.
Required coverage tags: `code_switching`, `names_numbers`, `room_noise`, `overlap`,
`negation`, `reassignment`, `cancellation`, `relative_dates`, `ambiguous_owner`,
`no_tasks`, `no_decisions`. Negative cases must actually have empty predictions.
Processing must take no longer than recording duration; peak memory <3 GB; no crash.

WER uses NFC/case normalization, punctuation removal preserving Devanagari marks,
and explicitly reviewed token aliases. Do not alias unrelated words to improve
scores. Also manually report Hindi/English errors separately, overlap DER,
thermal behavior, battery use, and ambiguous-deadline handling; these require
additional human/device evidence beyond the numeric scorer.

Among candidates passing every gate, select lowest WER for ASR and highest task
F1 for analysis; ties use lower processing time, then lower memory. Run each engine
sequentially and unload before loading the next. If none passes, report failures;
do not substitute cloud processing or call heuristic output qualified.

## Remaining device work before production integration

Compile the benchmark-enabled iOS app using Mac/Xcode (including the existing
GitHub Actions runner), then sign/install it through Sideloadly. The connected
iPhone executes Core ML/Metal; Windows can launch it and collect process metrics
through pymobiledevice3's USB userspace developer tunnel. This transport was
verified on the connected iPhone15,4 running iOS 26.5.2 with MeetMind build 3.
App queries, DVT process listing, app launch, running-state checks, and a memory
snapshot succeeded. This corrects the earlier assumption that Windows could not
control target-device tests. The replacement models and benchmark entrypoint are
not installed yet; startup measurements are not inference benchmarks.
Simulator success is not an iPhone memory, speed, thermal, diarization, or
Hinglish accuracy measurement.

After qualification, implement structured analysis interfaces, resumable processing,
protected local storage/backup exclusion, additive SwiftData migrations, source-linked
task review, and explicit accepted-task reminder export. Regression-test an existing
populated database and interrupted processing before distributing a new IPA.

Synthetic scorer unit tests are only tests of scoring logic. They must never be
included in the quality corpus or cited as model benchmarks.
