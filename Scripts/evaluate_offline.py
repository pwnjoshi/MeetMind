"""Offline qualification gate. Reads local annotations only; performs no networking.

Usage: python Scripts/evaluate_offline.py path/to/evaluation.json
Human adjudication matches predicted task IDs to reference IDs; this script does
not mistake text similarity or model self-evaluation for semantic correctness.
"""
import argparse
import json
import math
import re
import sys
import unicodedata


# Refined Hinglish prompt for task extraction
# Focus on identifying action items with explicit transcript source attribution.
SYSTEM_PROMPT = """You are a precise meeting assistant. Extract actionable tasks.
For every task, you must:
1. Identify the task, owner, and due date.
2. Quote the exact transcript segment (source) that justifies the task.
3. If no clear owner or date is mentioned, label as 'Unassigned' or 'TBD'.
DO NOT invent consensus. If the meeting did not explicitly agree on an action, do not extract it.
"""

def tokens(text, aliases):
    text = unicodedata.normalize("NFC", text).casefold()
    # Preserve Devanagari combining marks; strip punctuation, not vowel signs.
    text = "".join(" " if unicodedata.category(c)[0] in "PS" else c for c in text)
    return [aliases.get(t, t) for t in text.split()]


def edit_distance(a, b):
    row = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        nxt = [i]
        for j, y in enumerate(b, 1):
            nxt.append(min(nxt[-1] + 1, row[j] + 1, row[j-1] + (x != y)))
        row = nxt
    return row[-1]


def finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def qualify(data):
    errors = []
    metrics = {}
    def check(condition, message):
        if not condition:
            errors.append(message)

    check(data.get("schema_version") == 1, "Unsupported schema version")
    check(data.get("device") == "iPhone15,4", "Measurements must use regular iPhone 15")
    check(data.get("airplane_mode") is True, "Offline device run missing")
    check(data.get("reviewer") not in (None, ""), "Human reviewer missing")
    manifest = data.get("engines", {})
    for name in ("asr", "diarization", "analysis"):
        engine = manifest.get(name, {})
        check(bool(engine.get("revision")), f"{name} revision missing")
        check(bool(re.fullmatch(r"[a-f0-9]{64}", engine.get("sha256", ""))), f"{name} hash missing")
    cases = data.get("cases", [])
    required_scenarios = {"code_switching", "names_numbers", "room_noise", "overlap",
                          "negation", "reassignment", "cancellation", "relative_dates",
                          "ambiguous_owner", "no_tasks", "no_decisions"}
    observed = {tag for c in cases for tag in c.get("scenarios", [])}
    check(required_scenarios <= observed, "Missing scenarios: " + ", ".join(sorted(required_scenarios - observed)))
    check(len(cases) >= 20, "Need at least 20 held-out recordings")
    check(len({c["id"] for c in cases}) == len(cases), "Duplicate recording IDs")
    check(all(c.get("split") == "held_out" for c in cases), "Development cases cannot qualify release")
    check(sum(c["duration_seconds"] for c in cases) >= 10800, "Need at least three hours")
    check(any(c["duration_seconds"] >= 3600 and c.get("participants") == 6 for c in cases), "60-minute six-person fixture missing")
    edits = words = predicted = references = matched = owner_total = owner_ok = date_total = date_ok = 0
    diar_error = diar_reference = 0
    for c in cases:
        cid = c["id"]
        check(finite(c["duration_seconds"]) and c["duration_seconds"] > 0, f"{cid}: invalid duration")
        check(isinstance(c.get("participants"), int) and 2 <= c["participants"] <= 6, f"{cid}: participant count outside target")
        check(c.get("consented") is True, f"{cid}: consent missing")
        check(c.get("human_reviewed") is True, f"{cid}: adjudication missing")
        ref = tokens(c["reference_text"], data.get("normalization_aliases", {}))
        hyp = tokens(c["predicted_text"], data.get("normalization_aliases", {}))
        check(bool(ref), f"{cid}: empty reference transcript")
        edits += edit_distance(ref, hyp)
        words += len(ref)
        refs = c.get("reference_task_ids", [])
        tasks = c.get("tasks", [])
        if "no_tasks" in c.get("scenarios", []):
            check(not refs and not tasks, f"{cid}: no-task fixture produced tasks")
        if "no_decisions" in c.get("scenarios", []):
            check(not c.get("decisions", []), f"{cid}: no-decision fixture produced decisions")
        check(len(set(refs)) == len(refs), f"{cid}: duplicate reference tasks")
        check(len({t["id"] for t in tasks}) == len(tasks), f"{cid}: duplicate predictions")
        references += len(refs)
        predicted += len(tasks)
        seen = set()
        turns = c.get("turns", {})
        for task in tasks:
            target = task.get("matched_reference_id")
            correct = target in refs and target not in seen
            if target is not None:
                check(correct, f"{cid}: invalid/duplicate adjudicated match")
            if correct:
                matched += 1
                seen.add(target)
            for field in ("owner", "date"):
                if task.get(field) is not None:
                    ok = correct and task.get(f"{field}_correct") is True
                    if field == "owner":
                        owner_total += 1
                        owner_ok += int(ok)
                    else:
                        date_total += 1
                        date_ok += int(ok)
            evidence = task.get("evidence", [])
            check(bool(evidence), f"{cid}: task lacks evidence")
            for e in evidence:
                check(bool(e.get("quote")) and e.get("quote", "") in turns.get(e.get("turn_id"), ""), f"{cid}: invalid evidence")
            check(task.get("supported") is True, f"{cid}: unsupported task")
        for claim in c.get("decisions", []):
            check(claim.get("supported") is True, f"{cid}: unsupported decision")
            check(bool(claim.get("evidence")), f"{cid}: decision lacks evidence")
            for e in claim.get("evidence", []):
                check(bool(e.get("quote")) and e.get("quote", "") in turns.get(e.get("turn_id"), ""), f"{cid}: invalid decision evidence")
        check(c.get("summary_factual") is True and c.get("summary_readable_english") is True, f"{cid}: summary review failed/missing")
        for key in ("diarization_error_seconds", "diarization_reference_seconds", "processing_seconds", "peak_memory_bytes"):
            check(finite(c.get(key)) and c[key] >= 0, f"{cid}: invalid/missing {key}")
        if all(finite(c.get(k)) for k in ("diarization_error_seconds", "diarization_reference_seconds")):
            diar_error += c["diarization_error_seconds"]
            diar_reference += c["diarization_reference_seconds"]
        check(finite(c.get("processing_seconds")) and c["processing_seconds"] <= c["duration_seconds"], f"{cid}: processing exceeds recording duration")
        check(finite(c.get("peak_memory_bytes")) and c["peak_memory_bytes"] < 3_000_000_000, f"{cid}: memory gate failed")
        check(c.get("crashed") is False, f"{cid}: crash status failed/missing")
    metrics.update(wer=edits / words if words else None,
                   diarization_error_rate=diar_error / diar_reference if diar_reference else None,
                   task_precision=matched / predicted if predicted else None,
                   task_recall=matched / references if references else None,
                   owner_accuracy=owner_ok / owner_total if owner_total else None,
                   date_accuracy=date_ok / date_total if date_total else None)
    p, r = metrics["task_precision"], metrics["task_recall"]
    metrics["task_f1"] = 2 * p * r / (p + r) if p is not None and r is not None and p + r else 0
    for name, threshold, lower in (("wer", .25, True), ("diarization_error_rate", .20, True),
                                   ("task_precision", .90, False), ("task_recall", .80, False),
                                   ("owner_accuracy", .90, False), ("date_accuracy", .90, False)):
        value = metrics[name]
        check(value is not None and (value <= threshold if lower else value >= threshold), f"{name}: release gate failed or unmeasured")
    return {"qualified": not errors, "metrics": metrics, "failures": errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input")
    args = parser.parse_args()
    try:
        with open(args.input, encoding="utf-8") as source:
            result = qualify(json.load(source))
    except (OSError, ValueError, KeyError, TypeError, AttributeError, OverflowError) as exc:
        result = {"qualified": False, "failures": [f"Invalid evaluation input: {exc}"]}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["qualified"] else 1


if __name__ == "__main__":
    sys.exit(main())
