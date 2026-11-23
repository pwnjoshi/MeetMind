"""Turn a plain-text transcript into a labels.json skeleton for the golden set.

Input lines look like
    [00:12] Neha: Hi Pawan, let's start.
    [01:05:30] Pawan: haan, theek hai
A line without a timestamp continues the previous turn. Blank lines and lines starting with # are ignored.

  python Scripts/eval_labels_from_transcript.py transcript.txt --id 2025-01-standup --out golden/2025-01-standup/labels.json

Each turn ends where the next one starts; the last turn ends at --duration seconds (default start + 5 s).
`lang` is guessed from the script and a few common Roman Hindi words; fix it by hand.
tasks, decisions, openIssues and agenda are left empty on purpose: a human fills them in after
listening, following docs/EVALUATION.md.
"""
import argparse
import json
import os
import re
import sys

LINE = re.compile(r"^\s*\[(?P<time>\d{1,2}:\d{2}(?::\d{2})?(?:\.\d+)?)\]\s*(?:(?P<speaker>[^:\[\]]{1,40}?)\s*:\s*)?(?P<text>.*)$")

ROMAN_HINDI = {
    "hai", "hain", "nahi", "nahin", "kya", "haan", "theek", "thik", "kal", "aaj", "acha", "accha",
    "karna", "karo", "kar", "bhej", "dena", "dunga", "dungi", "karenge", "karunga", "karungi", "abhi",
    "toh", "mein", "main", "aap", "tum", "mujhe", "hum", "lekin", "aur", "bahut", "kaise", "chalo",
    "wala", "wali", "isko", "usko", "kyunki", "matlab", "samajh", "baat", "kaam", "ho", "hoga", "hogi",
}


def parse_time(text):
    parts = [float(p) for p in text.split(":")]
    seconds = 0.0
    for part in parts:
        seconds = seconds * 60 + part
    return seconds


def guess_lang(text):
    deva = sum(1 for c in text if "\u0900" <= c <= "\u097f")
    latin = sum(1 for c in text if c.isascii() and c.isalpha())
    if deva + latin == 0:
        return "en"
    fraction = deva / (deva + latin)
    if fraction >= 0.9:
        return "hi"
    if fraction > 0.1:
        return "hinglish"
    tokens = re.findall(r"[a-z]+", text.lower())
    hits = sum(1 for t in tokens if t in ROMAN_HINDI)
    return "hinglish" if tokens and hits / len(tokens) >= 0.15 else "en"


def parse_transcript(lines):
    turns = []
    for raw in lines:
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = LINE.match(raw)
        if match:
            turns.append({"start": parse_time(match.group("time")),
                          "speaker_name": (match.group("speaker") or "").strip() or "Unknown",
                          "text": match.group("text").strip()})
        elif turns:
            turns[-1]["text"] = (turns[-1]["text"] + " " + stripped).strip()
    return turns


def build_labels(turns, meeting_id, duration=None):
    names = []
    for turn in turns:
        if turn["speaker_name"] not in names:
            names.append(turn["speaker_name"])
    label_of = {name: f"S{i + 1}" for i, name in enumerate(names)}
    out_turns = []
    for index, turn in enumerate(turns):
        if index + 1 < len(turns):
            end = turns[index + 1]["start"]
        else:
            end = duration if duration and duration > turn["start"] else turn["start"] + 5.0
        out_turns.append({"start": round(turn["start"], 2), "end": round(max(end, turn["start"]), 2),
                          "speaker": label_of[turn["speaker_name"]], "text": turn["text"],
                          "lang": guess_lang(turn["text"])})
    return {
        "id": meeting_id,
        "languages": sorted({t["lang"] for t in out_turns}),
        "speakers": [{"label": label_of[n], "name": n} for n in names],
        "turns": out_turns,
        "tasks": [],
        "decisions": [],
        "openIssues": [],
        "participants": [n for n in names if n != "Unknown"],
        "agenda": [],
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("transcript")
    parser.add_argument("--id", required=True, help="meeting id; use the golden folder name")
    parser.add_argument("--out", help="output path (default: print to stdout)")
    parser.add_argument("--duration", type=float, help="audio length in seconds, to end the last turn")
    args = parser.parse_args(argv)
    with open(args.transcript, encoding="utf-8-sig") as handle:
        turns = parse_transcript(handle.read().splitlines())
    if not turns:
        print("No timestamped lines found. Expected: [00:12] Name: text", file=sys.stderr)
        return 1
    text = json.dumps(build_labels(turns, args.id, args.duration), ensure_ascii=False, indent=2) + "\n"
    if args.out:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        print(f"Wrote {args.out}. Now add tasks, decisions, openIssues and agenda by hand.")
    else:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
