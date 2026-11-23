"""Generate synthetic golden meetings for the automatic build evaluation.

Each meeting is spoken by macOS text-to-speech (`say`), one voice per speaker, stitched into one
16 kHz mono WAV with short pauses, and written next to a labels.json in the format documented in
docs/EVALUATION.md. Output is deterministic for a given set of installed voices: the scripts are
fixed, pauses come from a seeded generator, and turn times are measured from the audio itself.

  python3 -X utf8 Scripts/synth_meetings.py --out build/eval-golden
  python3 -X utf8 Scripts/synth_meetings.py --list-voices
  python3 -X utf8 Scripts/synth_meetings.py --out /tmp/g --only en-standup,hi-review

Needs macOS (`say`, `afconvert`). No third-party Python packages, no ffmpeg. When a preferred voice
is missing the next candidate is used; a meeting whose required voices cannot be found at all
(for example every Hindi meeting without Lekha) is skipped with a warning, never faked.

The audio is synthetic and public, so it is safe to keep in CI artifacts.
"""
import argparse
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import wave
import zlib

SAMPLE_RATE = 16000
LEAD_SECONDS = 0.30
TAIL_SECONDS = 0.50
PAUSES = (0.35, 0.50, 0.70)
MAX_MEETING_SECONDS = 70.0

# Role -> voices to try in order. Roles are distinct speakers: within a meeting no voice is used twice.
ROLE_VOICES = {
    "hi_f": ["Lekha"],
    "en_f1": ["Veena", "Samantha", "Karen", "Moira", "Tessa"],
    "en_m1": ["Rishi", "Daniel", "Alex", "Fred"],
    "en_m2": ["Daniel", "Alex", "Aaron", "Fred", "Rishi"],
    "en_f2": ["Samantha", "Karen", "Moira", "Tessa", "Veena"],
}
ROLE_LOCALE = {"hi_f": "hi_", "en_f1": "en_", "en_m1": "en_", "en_m2": "en_", "en_f2": "en_"}

SPEAKERS_NEHA = ("S1", "Neha", "en_f1")
SPEAKERS_PAWAN = ("S2", "Pawan", "en_m1")

MEETINGS = [
    {
        "id": "synth-en-standup",
        "speakers": [SPEAKERS_NEHA, SPEAKERS_PAWAN],
        "turns": [
            ("S1", "en", "Good morning Pawan. Let's start with the launch date for the mobile app."),
            ("S2", "en", "The vendor confirmed that testing finishes on Thursday, so we can launch on 20 November."),
            ("S1", "en", "Agreed, let's go with 20 November for the launch. Pawan, please send the updated agenda to the team by Friday."),
            ("S2", "en", "Sure, I will send the agenda by Friday. The marketing budget is still open, we will discuss it in the next meeting."),
            ("S1", "en", "Okay. The next meeting is on Monday at 10:30. Thanks everyone."),
        ],
        "tasks": [{"title": "Send the updated agenda to the team", "owner": "Pawan", "deadline": "Friday"}],
        "decisions": ["Launch on 20 November"],
        "openIssues": ["Marketing budget is not decided, discuss it in the next meeting"],
        "participants": ["Neha", "Pawan"],
        "agenda": ["Launch date", "Vendor testing", "Marketing budget"],
        "nextMeeting": "Monday at 10:30",
    },
    {
        "id": "synth-en-planning",
        "speakers": [SPEAKERS_NEHA, SPEAKERS_PAWAN, ("S3", "Arjun", "en_m2")],
        "turns": [
            ("S1", "en", "Let's review the release checklist. Arjun, can you take the security review?"),
            ("S3", "en", "I can't take the security review this sprint, I am fully booked with the payment migration."),
            ("S1", "en", "Fine. Then Pawan, will you handle the security review?"),
            ("S2", "en", "Yes, I will complete the security review by next Wednesday."),
            ("S1", "en", "Great. We decided to postpone the redesign until next quarter, because the team is too small right now."),
            ("S3", "en", "Agreed. I will share the migration plan tomorrow."),
            ("S1", "en", "We will defer the pricing question to the next meeting. The next meeting is on Tuesday the 18th of March."),
        ],
        "tasks": [
            {"title": "Complete the security review", "owner": "Pawan", "deadline": "next Wednesday"},
            {"title": "Share the migration plan", "owner": "Arjun", "deadline": "tomorrow"},
        ],
        "decisions": ["Postpone the redesign until next quarter because the team is too small"],
        "openIssues": ["Pricing question is deferred to the next meeting"],
        "participants": ["Neha", "Pawan", "Arjun"],
        "agenda": ["Release checklist", "Redesign", "Pricing"],
        "nextMeeting": "Tuesday 18 March",
    },
    {
        "id": "synth-en-vendor-call",
        "speakers": [SPEAKERS_NEHA, SPEAKERS_PAWAN, ("S3", "Arjun", "en_m2"), ("S4", "Priya", "en_f2")],
        "turns": [
            ("S1", "en", "Welcome everyone. Today we compare the two vendors for the cloud contract."),
            ("S4", "en", "The Pune vendor is cheaper than the Delhi vendor, and both can start next month."),
            ("S3", "en", "The Pune vendor also offers better support, so I recommend them."),
            ("S1", "en", "Okay, let's go with the Pune vendor, because it is cheaper and offers better support."),
            ("S2", "en", "I will email the Pune vendor the signed proposal by Thursday."),
            ("S4", "en", "And I will prepare the contract draft by next Monday. Who will check the legal terms?"),
            ("S1", "en", "Nobody is available for the legal terms yet, so that stays open until we find someone."),
        ],
        "tasks": [
            {"title": "Email the Pune vendor the signed proposal", "owner": "Pawan", "deadline": "Thursday"},
            {"title": "Prepare the contract draft", "owner": "Priya", "deadline": "next Monday"},
        ],
        "decisions": ["Go with the Pune vendor because it is cheaper and offers better support"],
        "openIssues": ["Nobody is assigned to check the legal terms"],
        "participants": ["Neha", "Pawan", "Arjun", "Priya"],
        "agenda": ["Vendor comparison", "Contract"],
        "nextMeeting": None,
    },
    {
        "id": "synth-en-no-tasks",
        "speakers": [SPEAKERS_NEHA, SPEAKERS_PAWAN],
        "turns": [
            ("S1", "en", "I have been thinking about the onboarding flow. We could maybe look at a shorter version some day."),
            ("S2", "en", "Maybe. The current flow takes six steps, which feels long, but nobody has time for it now."),
            ("S1", "en", "Right. I also wonder whether we should support tablets, but that is just an idea."),
            ("S2", "en", "The question of tablet support is still open. We should revisit it after the summer."),
            ("S1", "en", "Okay. No decisions today. Thanks."),
        ],
        "tasks": [],
        "decisions": [],
        "openIssues": ["Tablet support is undecided, revisit after the summer"],
        "participants": ["Neha", "Pawan"],
        "agenda": [],
        "nextMeeting": None,
    },
    {
        "id": "synth-hi-review",
        "speakers": [("S1", "Meera", "hi_f")],
        "turns": [
            ("S1", "hi", "सभी को नमस्कार। आज हम नई वेबसाइट की लॉन्च तारीख पर बात करेंगे।"),
            ("S1", "hi", "डिज़ाइन टीम ने बताया कि काम शुक्रवार तक पूरा हो जाएगा।"),
            ("S1", "hi", "इसलिए हमने तय किया कि वेबसाइट सोमवार को लॉन्च होगी।"),
            ("S1", "hi", "राहुल, कृपया शनिवार तक सभी पेज की जाँच कर लीजिए।"),
            ("S1", "hi", "बजट का सवाल अभी तय नहीं हुआ है, उसे अगली बैठक में देखेंगे।"),
            ("S1", "hi", "अगली बैठक अगले मंगलवार को सुबह दस बजे होगी। धन्यवाद।"),
        ],
        "tasks": [{"title": "Check all the pages", "owner": "Rahul", "deadline": "Saturday"}],
        "decisions": ["The website will launch on Monday"],
        "openIssues": ["Budget question is not decided, look at it in the next meeting"],
        "participants": ["Meera", "Rahul"],
        "agenda": ["Website launch date", "Budget"],
        "nextMeeting": "next Tuesday at 10 AM",
    },
    {
        "id": "synth-hi-two-speakers",
        # Only one Hindi voice ships with macOS. The second speaker is an Indian-English voice
        # reading Roman-script Hindi, which is also how many people write Hinglish.
        "speakers": [("S1", "Meera", "hi_f"), SPEAKERS_PAWAN],
        "turns": [
            ("S1", "hi", "पवन, ग्राहकों की शिकायतों की सूची तैयार हो गई है?"),
            ("S2", "hinglish", "haan Meera ji, suchi taiyaar hai, main kal subah tak aapko bhej dunga."),
            ("S1", "hi", "ठीक है। और पुराने सर्वर की मरम्मत का काम कौन करेगा?"),
            ("S2", "hinglish", "mujhe is hafte time nahi hai, main ye kaam nahi le sakta."),
            ("S1", "hi", "कोई बात नहीं। तो यह काम हम अगले महीने के लिए टाल देते हैं।"),
            ("S2", "hinglish", "theek hai. Aur naya vendor chunne ka faisla ho gaya, hum Sharma Traders ke saath jaayenge kyunki unka daam kam hai."),
            ("S1", "hi", "बिल्कुल। अगली बैठक सोमवार को होगी।"),
        ],
        "tasks": [{"title": "Send the list of customer complaints", "owner": "Pawan", "deadline": "kal subah tak"}],
        "decisions": ["Go with Sharma Traders as the new vendor because their price is lower"],
        "openIssues": ["Old server repair is postponed to next month"],
        "participants": ["Meera", "Pawan"],
        "agenda": ["Customer complaints", "Server repair", "New vendor"],
        "nextMeeting": "Monday",
    },
    {
        "id": "synth-hinglish-sprint",
        "speakers": [("S1", "Meera", "hi_f"), SPEAKERS_PAWAN, ("S3", "Neha", "en_f1")],
        "turns": [
            ("S1", "hinglish", "सबको नमस्ते। आज का agenda है, launch की तारीख और vendor की बात।"),
            ("S2", "hinglish", "haan, vendor ne bola hai ki testing Thursday tak ho jayegi, toh hum 20 November ko launch kar sakte hain."),
            ("S3", "en", "Sounds good. Let's go with 20 November for the launch."),
            ("S1", "hinglish", "ठीक है। Pawan, तुम कल तक सभी को agenda भेज दो।"),
            ("S2", "hinglish", "haan, main kal tak agenda bhej dunga."),
            ("S3", "hinglish", "Marketing budget abhi decide nahi hua, we will take it up in the next meeting."),
            ("S3", "en", "The next meeting is on Monday at eleven."),
        ],
        "tasks": [{"title": "Send the agenda to everyone", "owner": "Pawan", "deadline": "kal tak"}],
        "decisions": ["Launch on 20 November"],
        "openIssues": ["Marketing budget is not decided, discuss it in the next meeting"],
        "participants": ["Meera", "Pawan", "Neha"],
        "agenda": ["Launch date", "Vendor"],
        "nextMeeting": "Monday at 11",
    },
    {
        "id": "synth-hinglish-switch",
        "speakers": [SPEAKERS_NEHA, SPEAKERS_PAWAN],
        "turns": [
            ("S1", "hinglish", "Okay team, quick review of the vendor onboarding. Pawan, kya tumne contract dekh liya?"),
            ("S2", "hinglish", "Yes, I checked it. Contract mein payment terms thode unclear hain."),
            ("S1", "hinglish", "Theek hai. Please ask the vendor to clarify the payment terms by Wednesday."),
            ("S2", "hinglish", "Sure, main vendor ko Wednesday tak email kar dunga."),
            ("S1", "en", "Also, Pawan, can you redo the pricing sheet?"),
            ("S2", "hinglish", "Sorry, mujhse yeh nahi ho payega, I am travelling next week."),
            ("S1", "en", "No problem, we will skip the pricing sheet for now. Let's go with the old pricing because there is no time to change it."),
            ("S2", "hinglish", "Sahi hai. Next meeting Thursday ko rakhte hain."),
        ],
        "tasks": [{"title": "Email the vendor to clarify the payment terms", "owner": "Pawan", "deadline": "Wednesday"}],
        "decisions": ["Keep the old pricing because there is no time to change it"],
        "openIssues": [],
        "participants": ["Neha", "Pawan"],
        "agenda": ["Vendor onboarding", "Pricing sheet"],
        "nextMeeting": "Thursday",
    },
]

VOICE_LINE = re.compile(r"^(?P<name>.+?)\s+(?P<locale>[A-Za-z]{2,3}[_-][A-Za-z0-9]{2,4})\s+#")


def parse_voices(listing):
    """Parse `say -v '?'` into {voice name: locale with underscore}. First listing wins."""
    voices = {}
    for line in listing.splitlines():
        match = VOICE_LINE.match(line.strip())
        if match:
            voices.setdefault(match.group("name").strip(), match.group("locale").replace("-", "_"))
    return voices


def installed_voices():
    result = subprocess.run(["say", "-v", "?"], capture_output=True, text=True, encoding="utf-8", check=True)
    return parse_voices(result.stdout)


def resolve_voices(meeting, available):
    """Map each speaker label to a distinct voice, or raise LookupError naming what is missing."""
    chosen = {}
    used = set()
    for label, _name, role in meeting["speakers"]:
        candidates = [v for v in ROLE_VOICES[role] if v in available]
        prefix = ROLE_LOCALE[role]
        if prefix == "hi_":
            candidates += sorted(v for v, loc in available.items() if loc.startswith("hi_"))
        else:
            candidates += sorted(v for v, loc in available.items() if loc.startswith("en_") and "(" not in v)
        voice = next((v for v in candidates if v not in used), None)
        if voice is None:
            raise LookupError(f"no free {'Hindi' if prefix == 'hi_' else 'English'} voice for speaker {label} ({role})")
        used.add(voice)
        chosen[label] = voice
    return chosen


def pause_plan(meeting_id, count):
    """Deterministic gaps (seconds) between `count` turns."""
    rng = random.Random(zlib.crc32(meeting_id.encode("utf-8")))
    return [rng.choice(PAUSES) for _ in range(max(0, count - 1))]


def plan_timeline(durations, pauses, lead=LEAD_SECONDS, tail=TAIL_SECONDS):
    """Turn start/end times (seconds, rounded to 10 ms) and the total length for the given
    speech durations and the silences between them."""
    if len(pauses) != max(0, len(durations) - 1):
        raise ValueError("need exactly one pause between consecutive turns")
    cursor = lead
    spans = []
    for index, duration in enumerate(durations):
        spans.append((round(cursor, 2), round(cursor + duration, 2)))
        cursor += duration
        if index < len(pauses):
            cursor += pauses[index]
    return spans, round(cursor + tail, 2)


def read_wav(path):
    with wave.open(path, "rb") as handle:
        if handle.getnchannels() != 1 or handle.getsampwidth() != 2:
            raise ValueError(f"{path}: expected mono 16-bit PCM")
        return handle.getframerate(), handle.readframes(handle.getnframes())


def silence(seconds, rate=SAMPLE_RATE):
    return b"\x00\x00" * int(round(seconds * rate))


def trim_silence(pcm, rate, threshold=200, keep=0.05):
    """Drop near-silent samples at both ends (keeping `keep` seconds) so turn times are tight."""
    count = len(pcm) // 2
    samples = memoryview(pcm[: count * 2]).cast("h")
    first = next((i for i in range(count) if abs(samples[i]) > threshold), None)
    if first is None:
        return pcm[: count * 2]
    last = next(i for i in range(count - 1, -1, -1) if abs(samples[i]) > threshold)
    pad = int(keep * rate)
    return pcm[max(0, first - pad) * 2:(min(count, last + 1 + pad)) * 2]


def write_wav(path, pcm, rate=SAMPLE_RATE):
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(pcm)


def say_to_wav(voice, text, destination):
    """Speak `text` with `voice` into a 16 kHz mono 16-bit WAV (macOS only)."""
    with tempfile.TemporaryDirectory() as scratch:
        text_file = os.path.join(scratch, "turn.txt")
        raw = os.path.join(scratch, "turn.aiff")
        with open(text_file, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text + "\n")
        subprocess.run(["say", "-v", voice, "-o", raw, "-f", text_file], check=True)
        subprocess.run(["afconvert", "-f", "WAVE", "-d", f"LEI16@{SAMPLE_RATE}", "-c", "1", raw, destination],
                       check=True)


def build_labels(meeting, spans, speaker_names=None):
    languages = []
    for _speaker, lang, _text in meeting["turns"]:
        if lang not in languages:
            languages.append(lang)
    labels = {
        "id": meeting["id"],
        "languages": languages,
        "speakers": [{"label": label, "name": name} for label, name, _role in meeting["speakers"]],
        "turns": [
            {"start": start, "end": end, "speaker": speaker, "lang": lang, "text": text}
            for (speaker, lang, text), (start, end) in zip(meeting["turns"], spans)
        ],
        "tasks": meeting["tasks"],
        "decisions": meeting["decisions"],
        "openIssues": meeting["openIssues"],
        "participants": meeting["participants"],
        "agenda": meeting["agenda"],
    }
    if meeting.get("nextMeeting"):
        labels["nextMeeting"] = meeting["nextMeeting"]  # informational; the scorer ignores it
    return labels


def render_meeting(meeting, voices, out_dir, synth=say_to_wav):
    """Synthesize every turn, stitch, and write audio.wav + labels.json under out_dir/<id>/.
    `synth(voice, text, wav_path)` is injectable for tests. Returns the labels dict."""
    folder = os.path.join(out_dir, meeting["id"])
    os.makedirs(folder, exist_ok=True)
    pieces = []
    with tempfile.TemporaryDirectory() as scratch:
        for index, (speaker, _lang, text) in enumerate(meeting["turns"]):
            path = os.path.join(scratch, f"turn-{index:02d}.wav")
            synth(voices[speaker], text, path)
            rate, pcm = read_wav(path)
            if rate != SAMPLE_RATE:
                raise ValueError(f"{meeting['id']} turn {index}: sample rate {rate}, expected {SAMPLE_RATE}")
            pieces.append(trim_silence(pcm, rate))
    durations = [len(piece) / 2 / SAMPLE_RATE for piece in pieces]
    pauses = pause_plan(meeting["id"], len(pieces))
    spans, total = plan_timeline(durations, pauses)
    audio = bytearray(silence(LEAD_SECONDS))
    for index, piece in enumerate(pieces):
        audio += piece
        if index < len(pauses):
            audio += silence(pauses[index])
    audio += silence(TAIL_SECONDS)
    write_wav(os.path.join(folder, "audio.wav"), bytes(audio))
    labels = build_labels(meeting, spans)
    with open(os.path.join(folder, "labels.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(labels, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    if total > MAX_MEETING_SECONDS:
        print(f"warning: {meeting['id']} is {total:.0f} s (target is under {MAX_MEETING_SECONDS:.0f} s)", file=sys.stderr)
    return labels


def generate(out_dir, only=None, available=None, synth=say_to_wav):
    """Render every meeting whose voices exist. Returns (rendered ids, skipped {id: reason})."""
    available = installed_voices() if available is None else available
    rendered, skipped, voice_map = [], {}, {}
    for meeting in MEETINGS:
        if only and meeting["id"] not in only and meeting["id"].replace("synth-", "", 1) not in only:
            continue
        try:
            voices = resolve_voices(meeting, available)
        except LookupError as error:
            skipped[meeting["id"]] = str(error)
            continue
        render_meeting(meeting, voices, out_dir, synth)
        rendered.append(meeting["id"])
        voice_map[meeting["id"]] = voices
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "voices.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump({"voices": voice_map, "skipped": skipped}, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
    return rendered, skipped


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default=os.path.join("build", "eval-golden"))
    parser.add_argument("--only", help="comma-separated meeting ids (with or without the synth- prefix)")
    parser.add_argument("--list-voices", action="store_true")
    parser.add_argument("--clean", action="store_true", help="delete --out first")
    args = parser.parse_args(argv)
    if shutil.which("say") is None or shutil.which("afconvert") is None:
        print("This script needs macOS `say` and `afconvert`.", file=sys.stderr)
        return 1
    if args.list_voices:
        for name, locale in sorted(installed_voices().items()):
            print(f"{name}\t{locale}")
        return 0
    if args.clean and os.path.isdir(args.out):
        shutil.rmtree(args.out)
    only = {x.strip() for x in args.only.split(",") if x.strip()} if args.only else None
    rendered, skipped = generate(args.out, only)
    for name in rendered:
        print(f"rendered {name}")
    for name, reason in skipped.items():
        print(f"warning: skipped {name}: {reason}", file=sys.stderr)
    if not rendered:
        print("No meetings could be rendered.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
