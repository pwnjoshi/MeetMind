# Offline intelligence qualification

Status: **NOT QUALITY-QUALIFIED — synthetic device engine tests completed; held-out meeting evaluation remains outstanding.**

Build 7 connects the normal saved-audio processing flow to compressed multilingual
Whisper large-v3, FluidAudio offline speaker separation, and Qwen3-1.7B Q4_K_M.
This is an integrated evaluation build, not a claim that the accuracy, one-hour
performance, memory, or full production-readiness gates below have passed.
The 4B model remains excluded from the normal flow because of device memory pressure.

## Integrated app flow (build 7)

- Record/import audio, then open processing. Missing models require an explicit
  one-time public download. Settings → Offline analysis models supports download,
  repair, removal, size/status, and license review without opening the lab.
- Audio inference has no network fallback. Keep the app foreground; backgrounding
  cancels work. Resume reuses protected checkpoints after transcription, speaker
  separation, and each successfully analyzed chunk. Partial downloads also resume.
- Recordings must be local, readable, nonempty, and at most 60 minutes. Engine
  stages run sequentially; Qwen admission checks available memory before loading.
  Hindi input chunks are bounded using encoded JSON bytes, not character count.
- Anonymous speaker labels are assigned only for sufficiently clear overlap.
  Ambiguous speech stays unassigned; voices are not matched to named attendees.
- Successful analysis saves the original-language transcript and English discussion
  points/decisions. Suggested tasks remain private drafts, outside Action Items and
  Reminders, until the user reviews their exact source quotes and confirms edits.
  Owner and due date are optional. Spoken relative deadlines require explicit date
  confirmation; unspecified priority stays unspecified. Category is persisted and
  available as a grouping in the cross-meeting task list.
- Accepted/rejected suggestions persist across reopening. Chunk-overlap duplicates
  use normalized title/owner identity. Accepted/manual tasks survive reanalysis.
  This is deterministic duplicate suppression, not qualified semantic reconciliation
  of later cancellations, contradictions, or differently worded commitments.
- Ask AI uses Qwen3-1.7B against bounded transcript chunks, with validated source
  quotes and real timestamps. Hard-coded answers/citations have been removed.
  Question accuracy and cross-chunk answer reconciliation remain unqualified.
- Optional Apple Reminders sync targets on-device local lists only, preserving the
  no-cloud requirement. If no local account exists, tasks stay in MeetMind and the
  app explains why sync is unavailable. Unspecified priority is not invented on export.
- New persistence fields are optional additions; existing records keep legacy data.
  Installation and a real existing-store open still need physical-device validation.

The content-free integrated smoke command is:

```powershell
build/device-tools/Scripts/python.exe Scripts/device_benchmark.py --pipeline-check
```

It requires build 7 and downloaded models. It runs a public synthetic clip through
normal processing into a separate in-memory database, confirms one suggested task
and reloads it, checks duplicate confirmation, and prints only numeric/status markers.
It never selects or exports a private meeting. This smoke test does not measure
Hindi-English meeting accuracy. Actual results must be reviewed on the iPhone.

## Integrated validation in progress

The first integrated source `363c04b` passed 744 app tests, 20 engine tests, and
onboarding plus three main-tab simulator launches in Actions run `44275309276`.
Later source adds restart/failure checkpoint tests, explicit task-category behavior,
grounded question answering, and synthetic end-to-end device checks. See the latest
CI result for their final counts; the first run does not validate later changes.

Build 6 opened the iPhone's existing production store and remained running. Its
memory guard rejected both the unsafe 4B estimate and a 1.7B attempt with about
1.91 GB available versus a 2.03 GB estimated requirement. Build 7 bounds Foundation
FileHandle temporary buffers with a per-chunk autorelease pool during multi-GB
model verification. The memory reserve and 3 GB cap are unchanged. Physical-device
confirmation of this fix and the integrated pipeline is still pending.

## Build 7 physical integration findings

Build 7 (`da893b5`, Actions `44281481468`) passed 749 app tests and 28 engine
tests. It was installed over build 6 through the same Sideloadly account/bundle ID.
The existing production store opened and the app remained alive. A foreground
synthetic pipeline run completed transcription, speaker separation, and analysis,
but failed the smoke assertion because no reviewable task was found. This is a
failed end-to-end check, not a passing task-review/persistence result.

Controlled, automatically launched public-fixture benchmarks (no private recordings
selected) then showed:

- Whisper large-v3: 3.63 seconds warm, sampled footprint 113,247,272 bytes;
  recognized the public sample's words "send", "estimate", and "tomorrow".
- Qwen3-1.7B: 6.18 seconds, sampled footprint 607,504,600 bytes, nominal thermal;
  produced one suggested task involving a cancelled/rejected action in the public
  Hinglish fixture. It failed this semantic check despite valid output structure.

Only content-free aggregate diagnostics were printed; no private audio, transcript,
or generated meeting content was copied from the phone. These measurements do not
satisfy held-out accuracy gates. The lower footprint after bounded verification also
means earlier 4B failures must not be treated as a clean inference-memory comparison.

Build 9 introduces prompt version `meeting-analysis-v2` to distinguish concrete future
assignments from unrelated negations, invalidates prior prompt checkpoints, and records
prompt/context metadata in benchmarks. It also adds content-free pipeline result counts
so ASR, model output, decoding, and review persistence failures can be distinguished.

The normal pipeline remains the 1.7B trial configuration. The diagnostics-only 4B
candidate is re-evaluated with a 2,048-token context, 1,280 input / 768 output token
limits, 256/64 token batches, and a 500 MB working reserve. Its weights-plus-reserve
estimate is 2,997,280,256 bytes; admission still rejects insufficient available memory
and retains the 3 GB cap. Runtime load/decode footprint checks abort excessive usage.
This compact candidate has not yet passed device or quality qualification and is not
enabled for normal meetings. Build 9 device results are pending.

## Running the device lab

Use Settings → On-device intelligence → Diagnostics → Offline model benchmarks. Download one candidate and
run its benchmark. A public synthetic English audio clip (generated by macOS CI)
and a synthetic Hinglish text fixture are available for engine smoke tests.
Choose a local audio file to test speech/diarization; successful transcription
becomes the input for subsequent task-analysis benchmarks. Benchmarks never
create or modify saved meetings, active tasks, or reminders.
Build 6 also lets you choose an existing MeetMind recording directly, so no audio
has to leave the app to test the new engines. Selecting different audio clears
the previous transcript to prevent analysis of stale or synthetic text.

For automated smoke testing from this Windows workspace, after signing/installing
build 4 through Sideloadly:

```powershell
build/device-tools/Scripts/python.exe Scripts/device_benchmark.py --status
build/device-tools/Scripts/python.exe Scripts/device_benchmark.py --run qwen-1.7b
```

The helper filters device output to content-free benchmark markers. The underlying
developer launch command is:

```powershell
build/device-tools/Scripts/python.exe -m pymobiledevice3 developer dvt launch 'com.meetmind.app.JK2M3K5ACG --offline-benchmark --benchmark-model=qwen-1.7b' --userspace --stream
```

The launch flag selects the isolated lab, downloads the selected public model if
missing, and runs it. Substitute `whisper-small`, `whisper-large`, `diarization`,
or `qwen-4b`. Audio engines use the public synthetic clip by default. Keep the
device unlocked and app in foreground. No private audio is selected automatically.

Full results remain under Application Support/OfflineIntelligence/Results with
backup exclusion. Documents/BenchmarkMetrics contains numeric timing/memory/model
metadata only, with `qualified: false`; it contains no transcript or task text.
Memory is a sampled process footprint at 200 ms intervals, not a guaranteed true
peak. Neither short synthetic clips nor these metrics satisfy held-out quality
or one-hour performance gates. The analysis lab emits per-chunk drafts. Build 7 adds task review and checkpointing
to normal processing; semantic cross-chunk reconciliation and speaker-name
identification remain unqualified.
Language-model benchmarks use a 4,096-token context, at most 3,072 prompt tokens,
and at most 1,024 generated tokens to limit KV-cache memory on the 6 GB phone.
The tokenizer checks the actual prompt budget; an oversized chunk fails visibly
rather than truncating evidence. Long-meeting reconciliation is not qualified yet.

The 1.7B Q4_K_M asset is bartowski's pinned quantization of Qwen3-1.7B, since
the official 1.7B GGUF repository exposes Q8_0 rather than the planned Q4_K_M.
Model/engine licenses and speaker-model attribution are bundled in the lab.

## Physical-device smoke results

Measured on the connected regular iPhone 15, iOS 26.5.2, build 4 from source
`438a830` (successful Actions run `44223723797`). These are short public synthetic
fixtures, **not real-meeting quality or one-hour performance measurements**.
Times include engine/model loading and inference, excluding downloads and file
integrity checks. Footprint is sampled every 200 ms and can miss short spikes.

| Candidate | Seconds | Sampled peak bytes | Thermal state |
| --- | ---: | ---: | --- |
| FluidAudio offline VBx | 4.54 | 303842224 | Nominal |
| Whisper multilingual small | 25.12 | 511018168 | Nominal |
| Whisper compressed large-v3 | 77.28 | 651035952 | Nominal |
| Qwen3-1.7B Q4_K_M | 18.30 | 1880722536 | Nominal |
| Qwen3-4B Q4_K_M | Did not complete | No completed sample | Terminated by iOS memory pressure |

Build 5 adds bounded, resumable HTTP range downloads with retries after the 4B
download failure. Previously installed model directories remain compatible.
It also enforces on-device Apple Speech, removes the dormant cloud inference
service, excludes legacy meeting storage from backups, and removes fabricated
consensus from the legacy summary fallback. Those build-5 changes preceded the integrated evaluation flow in build 7.

After its download completed, the 4B configuration was terminated under memory
pressure in two foreground attempts (`vm-pageshortage`, `proc-thrashing` in iOS
jetsam reports). One report records approximately 2.60 GB of resident pages when
terminated; this is not a completed inference peak and is not the footprint metric
used above. Do not treat the failed attempt as a valid timing measurement.
Build 6 adds a conservative pre-allocation budget check (weights + 750 MB reserve,
capped at 3 GB and the OS-reported available process memory), a safe rejection of
this configuration, and a user action to remove downloaded model files.
The 1.7B candidate still requires real-meeting accuracy and headroom evaluation.

Build 6 can verify that the actual production store opens without copying any
meeting content off the phone:

```powershell
build/device-tools/Scripts/python.exe Scripts/device_benchmark.py --storage-check
```

The diagnostic prints only a success boolean and checks that the app remains alive
after five seconds. It does not inspect or export saved meeting rows.

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

Use `build/private-evaluation/` for synthetic scorer fixtures only. Real recordings,
reference text, annotations, transcripts, and generated content must remain on the
iPhone, including during evaluation. Do not copy them to this Windows workspace,
commit them, or upload them to Actions. The Python scorer currently consumes text
and therefore is **not the real-corpus evaluation path** under this privacy rule.
On-device human review and content-free aggregate metric export are still needed
before real-corpus qualification. Keep development and held-out recordings separate
on the phone; never tune against held-out annotations.

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

## Remaining device work before production release

Build 7 is an integrated evaluation build. Whisper large-v3 and Qwen3-1.7B are
trial defaults selected for testing, not winners of the held-out quality gates.
The setup, local inference, additive persistence, checkpoint recovery, source-linked
task review, and explicit accepted-task reminder export are implemented in source.
Physical-device regression against the existing populated store and the complete
pipeline must pass before distributing it as a validated update.

Windows launches the iPhone's Core ML/Metal engines over pymobiledevice3's USB
userspace developer tunnel. Short synthetic engine smoke tests and existing-store
opening have been measured on the regular iPhone 15. Simulator success does not
establish iPhone memory, speed, thermal, diarization, or Hinglish accuracy results.

Before production qualification, collect the consented held-out corpus and reference
annotations on the iPhone, implement content-free aggregate evaluation export, and
measure every gate above. Semantic reconciliation of cross-chunk cancellations and
contradictions is not implemented by deterministic title/owner deduplication.
Generated drafts therefore still require human review. Do not describe this build
as fully qualified or infer task accuracy from valid substring quotes alone.

Synthetic scorer unit tests are only tests of scoring logic. They must never be
included in the quality corpus or cited as real-meeting accuracy benchmarks.
