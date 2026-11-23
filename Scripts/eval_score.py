"""Score a Manent build against a labelled golden set. Pure Python 3, no third-party packages.

Inputs
  --golden DIR   one folder per meeting containing labels.json (see docs/EVALUATION.md)
  --results DIR  one folder per meeting containing result.json written by the app
                 (Documents/Evaluation/<id>/result.json, pulled by Scripts/device_eval.py)

Outputs (default build/eval)
  report-<commit>.md   human readable report
  summary-<commit>.json  machine readable metrics, comparable with --compare

  python Scripts/eval_score.py --golden golden --results build/eval/runs/abc1234
  python Scripts/eval_score.py --compare build/eval/summary-old.json build/eval/summary-new.json

Metrics are computed per meeting and aggregated by pooling errors and reference sizes
(micro average), never by averaging per-meeting percentages.
"""
import argparse
import difflib
import itertools
import json
import os
import re
import sys
import unicodedata

SUMMARY_SCHEMA = 1
TOKEN_MATCH_THRESHOLD = 0.6
LANG_SCRIPT_TOLERANCE = 0.35
MAX_MAPPING_SPEAKERS = 8

# ---------------------------------------------------------------------------
# Text normalisation and scripts
# ---------------------------------------------------------------------------

DEVANAGARI_NUKTA = "\u093c"


def is_devanagari(ch):
    return "\u0900" <= ch <= "\u097f"


def normalize_text(text):
    """NFC, case-folded, punctuation and symbols replaced by spaces. Combining marks are kept
    so Devanagari vowel signs survive. The nukta is dropped because ASR output and human labels
    disagree on it far more often than on the letter itself."""
    text = unicodedata.normalize("NFC", text or "").casefold().replace(DEVANAGARI_NUKTA, "")
    text = text.replace("\u200c", "").replace("\u200d", "")
    return "".join(" " if unicodedata.category(c)[0] in "PSZC" else c for c in text)


def words(text):
    return normalize_text(text).split()


def word_has_devanagari(word):
    return any(is_devanagari(c) for c in word)


def devanagari_fraction(text):
    """Share of words written in Devanagari among words that contain letters, or None when the
    text has no lettered word. Word based so long English words do not outweigh short Hindi ones."""
    deva = latin = 0
    for word in words(text):
        if word_has_devanagari(word):
            deva += 1
        elif any(c.isalpha() for c in word):
            latin += 1
    total = deva + latin
    return None if total == 0 else deva / total


# ---------------------------------------------------------------------------
# Devanagari -> Roman transliteration (ISO-ish, simplified for matching)
# ---------------------------------------------------------------------------

_CONSONANTS = {
    "\u0915": "k", "\u0916": "kh", "\u0917": "g", "\u0918": "gh", "\u0919": "n",
    "\u091a": "ch", "\u091b": "chh", "\u091c": "j", "\u091d": "jh", "\u091e": "n",
    "\u091f": "t", "\u0920": "th", "\u0921": "d", "\u0922": "dh", "\u0923": "n",
    "\u0924": "t", "\u0925": "th", "\u0926": "d", "\u0927": "dh", "\u0928": "n",
    "\u092a": "p", "\u092b": "ph", "\u092c": "b", "\u092d": "bh", "\u092e": "m",
    "\u092f": "y", "\u0930": "r", "\u0932": "l", "\u0935": "v", "\u0936": "sh",
    "\u0937": "sh", "\u0938": "s", "\u0939": "h", "\u0933": "l",
    # precomposed nukta letters
    "\u0958": "q", "\u0959": "kh", "\u095a": "g", "\u095b": "z", "\u095c": "r",
    "\u095d": "rh", "\u095e": "f", "\u095f": "y",
}
_INDEPENDENT_VOWELS = {
    "\u0905": "a", "\u0906": "aa", "\u0907": "i", "\u0908": "ee", "\u0909": "u", "\u090a": "oo",
    "\u090b": "ri", "\u090f": "e", "\u0910": "ai", "\u0913": "o", "\u0914": "au",
    "\u0911": "o", "\u090d": "e", "\u0904": "a",
}
_MATRAS = {
    "\u093e": "aa", "\u093f": "i", "\u0940": "ee", "\u0941": "u", "\u0942": "oo",
    "\u0943": "ri", "\u0947": "e", "\u0948": "ai", "\u094b": "o", "\u094c": "au",
    "\u0949": "o", "\u0945": "e", "\u0946": "e", "\u094a": "o",
}
_DIGITS = {chr(0x0966 + i): str(i) for i in range(10)}
_VIRAMA = "\u094d"
_SIGNS = {"\u0901": "n", "\u0902": "n", "\u0903": "h"}


def devanagari_to_roman(word):
    """Transliterate one Devanagari word. The inherent 'a' is written after a bare consonant
    except at the end of a word (schwa deletion), so 'kam' not 'kama'."""
    chars = unicodedata.normalize("NFC", word).replace(DEVANAGARI_NUKTA, "")
    out = []
    pending_a = False
    for ch in chars:
        if ch in _CONSONANTS:
            if pending_a:
                out.append("a")
            out.append(_CONSONANTS[ch])
            pending_a = True
        elif ch == _VIRAMA:
            pending_a = False
        elif ch in _MATRAS:
            pending_a = False
            out.append(_MATRAS[ch])
        elif ch in _INDEPENDENT_VOWELS:
            if pending_a:
                out.append("a")
            pending_a = False
            out.append(_INDEPENDENT_VOWELS[ch])
        elif ch in _SIGNS:
            if pending_a:
                out.append("a")
            pending_a = False
            out.append(_SIGNS[ch])
        elif ch in _DIGITS:
            if pending_a:
                out.append("a")
            pending_a = False
            out.append(_DIGITS[ch])
        else:
            if pending_a:
                out.append("a")
            pending_a = False
            out.append(ch if ch.isascii() else "")
    return "".join(out)


def roman_skeleton(word):
    """Spelling-tolerant Roman form shared by Latin and transliterated Devanagari words.
    Folds common Hinglish spelling variation (ph/f, w/v, z/j, ee/i, oo/u, e/i, o/u, doubled
    letters). It is deliberately lenient: it measures script-agnostic word identity, not spelling."""
    if word_has_devanagari(word):
        word = devanagari_to_roman(word)
    word = unicodedata.normalize("NFD", word.casefold())
    word = "".join(c for c in word if not unicodedata.combining(c))
    word = re.sub(r"[^a-z0-9]", "", word)
    for source, target in (("ph", "f"), ("w", "v"), ("z", "j"), ("q", "k"), ("x", "ks"),
                           ("ee", "i"), ("oo", "u"), ("ii", "i"), ("uu", "u")):
        word = word.replace(source, target)
    word = word.translate(str.maketrans("eo", "iu"))
    return re.sub(r"(.)\1+", r"\1", word)


def roman_words(text):
    return [w for w in (roman_skeleton(x) for x in words(text)) if w]


# ---------------------------------------------------------------------------
# Edit distance
# ---------------------------------------------------------------------------

def edit_distance(a, b):
    if not a:
        return len(b)
    if not b:
        return len(a)
    row = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        nxt = [i]
        for j, y in enumerate(b, 1):
            nxt.append(min(nxt[-1] + 1, row[j] + 1, row[j - 1] + (x != y)))
        row = nxt
    return row[-1]


def latin_words(text):
    return [w for w in words(text) if not word_has_devanagari(w)]


def devanagari_chars(text):
    """Devanagari letters and signs of text with spaces removed, for character error rate."""
    normalised = normalize_text(text)
    return [c for c in normalised if is_devanagari(c)]


# ---------------------------------------------------------------------------
# Transcript alignment and error rates
# ---------------------------------------------------------------------------

def overlap(a_start, a_end, b_start, b_end):
    return max(0.0, min(a_end, b_end) - max(a_start, b_start))


def align_hypothesis(ref_turns, hyp_turns):
    """Return one hypothesis text per reference turn. Each hypothesis turn goes to the reference
    turn it overlaps most in time, or to the nearest one by midpoint when nothing overlaps."""
    buckets = [[] for _ in ref_turns]
    if not ref_turns:
        return []
    for hyp in sorted(hyp_turns, key=lambda t: (t.get("start", 0.0), t.get("end", 0.0))):
        h_start, h_end = float(hyp.get("start", 0.0)), float(hyp.get("end", 0.0))
        best, best_overlap = None, 0.0
        for index, ref in enumerate(ref_turns):
            shared = overlap(h_start, h_end, float(ref["start"]), float(ref["end"]))
            if shared > best_overlap:
                best, best_overlap = index, shared
        if best is None:
            mid = (h_start + h_end) / 2
            best = min(range(len(ref_turns)),
                       key=lambda i: abs(mid - (float(ref_turns[i]["start"]) + float(ref_turns[i]["end"])) / 2))
        buckets[best].append(hyp.get("text", ""))
    return [" ".join(parts) for parts in buckets]


class Counter:
    """Errors over reference size, pooled across turns."""

    def __init__(self):
        self.errors = 0
        self.total = 0

    def add(self, errors, total):
        self.errors += errors
        self.total += total

    def rate(self):
        return None if self.total == 0 else self.errors / self.total


def transcript_errors(ref_turns, hyp_turns):
    """Pooled transcript errors, per labelled language and overall.

    Returns {lang: {"wer_latin": Counter, "cer_deva": Counter, "wer_roman": Counter,
                    "lang_correct": Counter}} with an "all" entry covering every turn."""
    aligned = align_hypothesis(ref_turns, hyp_turns)
    result = {}

    def bucket(name):
        if name not in result:
            result[name] = {"wer_latin": Counter(), "cer_deva": Counter(),
                            "wer_roman": Counter(), "lang_correct": Counter()}
        return result[name]

    for ref, hyp_text in zip(ref_turns, aligned):
        ref_text = ref.get("text", "")
        for name in (ref.get("lang") or "unknown", "all"):
            entry = bucket(name)
            r_latin, h_latin = latin_words(ref_text), latin_words(hyp_text)
            if r_latin:
                entry["wer_latin"].add(edit_distance(r_latin, h_latin), len(r_latin))
            r_deva, h_deva = devanagari_chars(ref_text), devanagari_chars(hyp_text)
            if r_deva:
                entry["cer_deva"].add(edit_distance(r_deva, h_deva), len(r_deva))
            r_roman, h_roman = roman_words(ref_text), roman_words(hyp_text)
            if r_roman:
                entry["wer_roman"].add(edit_distance(r_roman, h_roman), len(r_roman))
            ref_fraction = devanagari_fraction(ref_text)
            if ref_fraction is not None:
                hyp_fraction = devanagari_fraction(hyp_text)
                ok = hyp_fraction is not None and abs(hyp_fraction - ref_fraction) <= LANG_SCRIPT_TOLERANCE
                entry["lang_correct"].add(0 if ok else 1, 1)
    return result


# ---------------------------------------------------------------------------
# Speaker attribution
# ---------------------------------------------------------------------------

def _speaker_at(turns, start, end):
    mid = (start + end) / 2
    for turn in turns:
        if float(turn["start"]) <= mid < float(turn["end"]):
            return turn.get("speaker")
    return None


def speaker_confusion(ref_turns, hyp_turns):
    """Seconds of reference speech for each (reference speaker, hypothesis speaker or None)."""
    points = set()
    for turn in list(ref_turns) + list(hyp_turns):
        points.add(float(turn["start"]))
        points.add(float(turn["end"]))
    ordered = sorted(points)
    table = {}
    for left, right in zip(ordered, ordered[1:]):
        if right - left <= 0:
            continue
        ref_speaker = _speaker_at(ref_turns, left, right)
        if ref_speaker is None:
            continue
        hyp_speaker = _speaker_at(hyp_turns, left, right)
        key = (ref_speaker, hyp_speaker)
        table[key] = table.get(key, 0.0) + (right - left)
    return table


def best_speaker_mapping(table):
    """One-to-one mapping from hypothesis speaker to reference speaker that maximises matched
    seconds. Brute force over permutations, which is fast for up to 8 speakers per side; extra
    hypothesis speakers beyond the 8 with the most speech stay unmapped (counted as errors)."""
    refs = sorted({r for r, _ in table})
    hyp_time = {}
    for (_, h), seconds in table.items():
        if h is not None:
            hyp_time[h] = hyp_time.get(h, 0.0) + seconds
    hyps = sorted(hyp_time, key=lambda h: (-hyp_time[h], str(h)))[:MAX_MAPPING_SPEAKERS]
    refs = refs[:MAX_MAPPING_SPEAKERS] if len(refs) > MAX_MAPPING_SPEAKERS else refs
    best_score, best_map = -1.0, {}
    if not refs or not hyps:
        return {}
    if len(refs) <= len(hyps):
        candidates = (dict(zip(refs, perm)) for perm in itertools.permutations(hyps, len(refs)))
        for assignment in candidates:
            score = sum(table.get((r, h), 0.0) for r, h in assignment.items())
            if score > best_score:
                best_score, best_map = score, assignment
        return {h: r for r, h in best_map.items()}
    candidates = (dict(zip(perm, hyps)) for perm in itertools.permutations(refs, len(hyps)))
    for assignment in candidates:
        score = sum(table.get((r, h), 0.0) for r, h in assignment.items())
        if score > best_score:
            best_score, best_map = score, assignment
    return {h: r for r, h in best_map.items()}


def speaker_error(ref_turns, hyp_turns):
    """Time-weighted speaker attribution error after the best label mapping.

    Returns dict with total speech seconds, missed (no hypothesis speaker), confused (wrong
    speaker) seconds, and the error rate (missed + confused) / total. None when there is no
    labelled speech."""
    table = speaker_confusion(ref_turns, hyp_turns)
    total = sum(table.values())
    if total <= 0:
        return {"total_s": 0.0, "missed_s": 0.0, "confused_s": 0.0, "rate": None,
                "ref_speakers": 0, "hyp_speakers": 0}
    mapping = best_speaker_mapping(table)
    missed = confused = 0.0
    for (ref_speaker, hyp_speaker), seconds in table.items():
        if hyp_speaker is None:
            missed += seconds
        elif mapping.get(hyp_speaker) != ref_speaker:
            confused += seconds
    hyp_labels = {t.get("speaker") for t in hyp_turns if t.get("speaker")}
    return {"total_s": total, "missed_s": missed, "confused_s": confused,
            "rate": (missed + confused) / total,
            "ref_speakers": len({r for r, _ in table}), "hyp_speakers": len(hyp_labels)}


# ---------------------------------------------------------------------------
# Fuzzy text matching for tasks, decisions and open issues
# ---------------------------------------------------------------------------

STOPWORDS = {
    "the", "a", "an", "to", "of", "and", "or", "for", "on", "in", "at", "by", "is", "are", "be",
    "will", "that", "this", "we", "i", "you", "it", "with", "from", "as",
    "ko", "ka", "ki", "ke", "se", "me", "mein", "hai", "hain", "tha", "thi", "ne", "par", "aur",
}
_STOP_SKELETONS = {roman_skeleton(w) for w in STOPWORDS}


def content_tokens(text):
    tokens = [roman_skeleton(w) for w in words(text)]
    kept = [t for t in tokens if t and t not in _STOP_SKELETONS]
    return kept or [t for t in tokens if t]


def _tokens_equal(a, b):
    if a == b:
        return True
    if min(len(a), len(b)) >= 4:
        return difflib.SequenceMatcher(None, a, b).ratio() >= 0.8
    return False


def token_set_ratio(a, b):
    """Dice coefficient over content-word sets, 0..1. Words match when equal after the Roman
    skeleton fold or when they are near spellings (SequenceMatcher >= 0.8, length >= 4)."""
    left, right = sorted(set(content_tokens(a))), sorted(set(content_tokens(b)))
    if not left or not right:
        return 0.0
    used = set()
    shared = 0
    for token in left:
        for index, other in enumerate(right):
            if index not in used and _tokens_equal(token, other):
                used.add(index)
                shared += 1
                break
    return 2 * shared / (len(left) + len(right))


def match_items(refs, preds, threshold=TOKEN_MATCH_THRESHOLD):
    """Greedy one-to-one matching, best scores first. Returns [(ref_index, pred_index, score)]."""
    scored = []
    for i, ref in enumerate(refs):
        for j, pred in enumerate(preds):
            score = token_set_ratio(ref, pred)
            if score >= threshold:
                scored.append((score, i, j))
    scored.sort(key=lambda item: (-item[0], item[1], item[2]))
    used_ref, used_pred, matches = set(), set(), []
    for score, i, j in scored:
        if i not in used_ref and j not in used_pred:
            used_ref.add(i)
            used_pred.add(j)
            matches.append((i, j, score))
    return matches


def prf(true_positive, predicted, expected):
    """Precision, recall, F1 where an empty side counts as vacuously perfect."""
    precision = true_positive / predicted if predicted else 1.0
    recall = true_positive / expected if expected else 1.0
    f1 = 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)
    return precision, recall, f1


def _name_tokens(name):
    return {roman_skeleton(w) for w in words(name or "") if roman_skeleton(w)}


def owner_matches(ref_owner, pred_owner):
    ref_tokens, pred_tokens = _name_tokens(ref_owner), _name_tokens(pred_owner)
    if not ref_tokens and not pred_tokens:
        return True
    if not ref_tokens or not pred_tokens:
        return False
    return ref_tokens <= pred_tokens or pred_tokens <= ref_tokens or bool(ref_tokens & pred_tokens)


_DEADLINE_FILLER = {"by", "on", "before", "till", "until", "tak", "the", "ko", "se", "of"}
_DEADLINE_FILLER_SKELETONS = {roman_skeleton(w) for w in _DEADLINE_FILLER}


def _deadline_tokens(text):
    tokens = [roman_skeleton(w) for w in words(text or "")]
    return {t for t in tokens if t and t not in _DEADLINE_FILLER_SKELETONS}


def deadline_matches(ref_deadline, pred_text, pred_due_date=None):
    ref_tokens = _deadline_tokens(ref_deadline)
    if not ref_tokens:
        return not _deadline_tokens(pred_text) and not pred_due_date
    if pred_due_date and (ref_deadline or "").strip() == pred_due_date.strip():
        return True
    pred_tokens = _deadline_tokens(pred_text)
    if not pred_tokens:
        return False
    return 2 * len(ref_tokens & pred_tokens) / (len(ref_tokens) + len(pred_tokens)) >= 0.5


def score_items(ref_texts, pred_texts):
    matches = match_items(ref_texts, pred_texts)
    return {"tp": len(matches), "predicted": len(pred_texts), "expected": len(ref_texts)}, matches


def score_tasks(ref_tasks, pred_tasks):
    counts, matches = score_items([t.get("title", "") for t in ref_tasks],
                                  [t.get("title", "") for t in pred_tasks])
    owner_ok = deadline_ok = 0
    for i, j, _ in matches:
        ref, pred = ref_tasks[i], pred_tasks[j]
        owner_ok += owner_matches(ref.get("owner"), pred.get("owner"))
        deadline_ok += deadline_matches(ref.get("deadline"), pred.get("deadlineText"), pred.get("dueDate"))
    counts.update({"owner_ok": owner_ok, "deadline_ok": deadline_ok, "matched": len(matches)})
    return counts


# ---------------------------------------------------------------------------
# Per-meeting scoring and aggregation
# ---------------------------------------------------------------------------

def load_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def score_meeting(labels, result, task_source="tasks"):
    ref_turns = labels.get("turns", [])
    speaker_names = {s.get("label"): s.get("name") for s in labels.get("speakers", [])}
    hyp_turns = result.get("turns", [])
    transcript = transcript_errors(ref_turns, hyp_turns)
    speakers = speaker_error(ref_turns, hyp_turns)
    tasks = score_tasks(labels.get("tasks", []), result.get(task_source, []))
    decisions, _ = score_items(labels.get("decisions", []), result.get("decisions", []))
    issues, _ = score_items(labels.get("openIssues", []), result.get("openIssues", []))
    timings = result.get("timings", {})
    audio_s = float(result.get("audioSeconds") or 0)
    total_ms = timings.get("totalMs")
    return {
        "id": labels.get("id") or result.get("id"),
        "languages": labels.get("languages", []),
        "speaker_names": speaker_names,
        "audio_s": audio_s,
        "transcript": {lang: {name: {"errors": c.errors, "total": c.total} for name, c in entry.items()}
                       for lang, entry in transcript.items()},
        "speakers": speakers,
        "tasks": tasks,
        "decisions": decisions,
        "open_issues": issues,
        "timings": timings,
        "rtf": (total_ms / 1000 / audio_s) if total_ms is not None and audio_s > 0 else None,
        "peak_mb": result.get("peakFootprintMB"),
        "speaker_warning": result.get("speakerWarning"),
    }


def _pool(per_meeting, getter):
    errors = total = 0
    for meeting in per_meeting:
        e, t = getter(meeting)
        errors += e
        total += t
    return errors, total


def _rate(errors, total):
    return None if total == 0 else errors / total


def _stat(values, fn):
    values = [v for v in values if v is not None]
    return fn(values) if values else None


def aggregate(per_meeting):
    """Flat metrics dict {name: {"value", "better", "n"}} for the summary and for --compare."""
    metrics = {}

    def put(name, value, better, n):
        metrics[name] = {"value": value, "better": better, "n": n}

    languages = sorted({lang for m in per_meeting for lang in m["transcript"]})
    for lang in languages:
        for key, label in (("wer_latin", "wer_latin"), ("cer_deva", "cer_deva"), ("wer_roman", "wer_roman")):
            e, t = _pool(per_meeting, lambda m, l=lang, k=key: (m["transcript"].get(l, {}).get(k, {}).get("errors", 0),
                                                              m["transcript"].get(l, {}).get(k, {}).get("total", 0)))
            put(f"{label}.{lang}", _rate(e, t), "lower", t)
        e, t = _pool(per_meeting, lambda m, l=lang: (m["transcript"].get(l, {}).get("lang_correct", {}).get("errors", 0),
                                                    m["transcript"].get(l, {}).get("lang_correct", {}).get("total", 0)))
        put(f"language_correct.{lang}", None if t == 0 else 1 - e / t, "higher", t)

    seconds = sum(m["speakers"]["total_s"] for m in per_meeting)
    wrong = sum(m["speakers"]["missed_s"] + m["speakers"]["confused_s"] for m in per_meeting)
    put("speaker_error", wrong / seconds if seconds > 0 else None, "lower", round(seconds))
    exact = [m for m in per_meeting if m["speakers"]["ref_speakers"]]
    put("speaker_count_exact",
        sum(m["speakers"]["ref_speakers"] == m["speakers"]["hyp_speakers"] for m in exact) / len(exact) if exact else None,
        "higher", len(exact))

    for name, key in (("tasks", "tasks"), ("decisions", "decisions"), ("open_issues", "open_issues")):
        tp = sum(m[key]["tp"] for m in per_meeting)
        predicted = sum(m[key]["predicted"] for m in per_meeting)
        expected = sum(m[key]["expected"] for m in per_meeting)
        precision, recall, f1 = prf(tp, predicted, expected)
        has_data = predicted + expected > 0
        put(f"{name}_precision", precision if has_data else None, "higher", predicted)
        put(f"{name}_recall", recall if has_data else None, "higher", expected)
        put(f"{name}_f1", f1 if has_data else None, "higher", expected)
    matched = sum(m["tasks"]["matched"] for m in per_meeting)
    put("owner_accuracy", sum(m["tasks"]["owner_ok"] for m in per_meeting) / matched if matched else None, "higher", matched)
    put("deadline_accuracy", sum(m["tasks"]["deadline_ok"] for m in per_meeting) / matched if matched else None, "higher", matched)

    put("rtf_mean", _stat([m["rtf"] for m in per_meeting], lambda v: sum(v) / len(v)), "lower", len(per_meeting))
    put("rtf_max", _stat([m["rtf"] for m in per_meeting], max), "lower", len(per_meeting))
    for stage in ("transcribeMs", "speakersMs", "minutesMs", "modelLoadMs", "totalMs"):
        label = re.sub(r"(?<!^)([A-Z])", r"_\1", stage).lower()
        put(f"{label}_mean", _stat([m["timings"].get(stage) for m in per_meeting], lambda v: sum(v) / len(v)),
            "lower", len(per_meeting))
    put("peak_mb_max", _stat([m["peak_mb"] for m in per_meeting], max), "lower", len(per_meeting))
    put("fallback_chunks_total", sum(m["timings"].get("fallbackChunks", 0) or 0 for m in per_meeting), "lower", len(per_meeting))
    return metrics


def build_summary(per_meeting, results, missing, commit, task_source):
    first = next(iter(results.values()), {})
    return {
        "schema": SUMMARY_SCHEMA,
        "commit": commit,
        "device": first.get("device"),
        "osVersion": first.get("osVersion"),
        "model": first.get("model"),
        "promptVersion": first.get("promptVersion"),
        "taskSource": task_source,
        "meetings": len(per_meeting),
        "missing": missing,
        "metrics": aggregate(per_meeting),
        "perMeeting": per_meeting,
    }


# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------

def fmt(value, kind="pct"):
    if value is None:
        return "n/a"
    if kind == "pct":
        return f"{value * 100:.1f}%"
    if kind == "ms":
        return f"{value / 1000:.1f}s"
    if kind == "x":
        return f"{value:.2f}x"
    return f"{value:.1f}"


def metric_kind(name):
    if name.endswith("_ms_mean"):
        return "ms"
    if name.startswith("rtf"):
        return "x"
    if name.startswith("peak_mb") or name.startswith("fallback"):
        return "num"
    return "pct"


def render_report(summary):
    metrics = summary["metrics"]
    lines = [f"# Evaluation report {summary.get('commit') or 'unknown'}", ""]
    lines.append(f"- Device: {summary.get('device') or 'unknown'} ({summary.get('osVersion') or 'unknown'})")
    lines.append(f"- Analysis model: {summary.get('model') or 'unknown'}, prompt {summary.get('promptVersion') or 'unknown'}")
    lines.append(f"- Meetings scored: {summary['meetings']}; task source: `{summary['taskSource']}`")
    if summary["missing"]:
        lines.append(f"- No result for: {', '.join(summary['missing'])}")
    lines += ["", "With few meetings these numbers are indicative, not statistically tight. Compare builds on the same set.", ""]

    languages = sorted({n.split(".", 1)[1] for n in metrics if n.startswith("wer_roman.")})
    lines += ["## Transcript", "", "| Language | WER Latin | CER Devanagari | WER Roman (script-agnostic) | Right script | Ref words |",
              "|---|---|---|---|---|---|"]
    for lang in languages:
        lines.append("| {} | {} | {} | {} | {} | {} |".format(
            lang, fmt(metrics[f"wer_latin.{lang}"]["value"]), fmt(metrics[f"cer_deva.{lang}"]["value"]),
            fmt(metrics[f"wer_roman.{lang}"]["value"]), fmt(metrics[f"language_correct.{lang}"]["value"]),
            metrics[f"wer_roman.{lang}"]["n"]))
    lines += ["", "## Speakers", "",
              f"- Attribution error (time-weighted, best label mapping): {fmt(metrics['speaker_error']['value'])} over {metrics['speaker_error']['n']} s of labelled speech",
              f"- Meetings with the right speaker count: {fmt(metrics['speaker_count_exact']['value'])}", ""]
    lines += ["## Tasks, decisions, open issues", "", "| Item | Precision | Recall | F1 | Expected |", "|---|---|---|---|---|"]
    for name in ("tasks", "decisions", "open_issues"):
        lines.append("| {} | {} | {} | {} | {} |".format(
            name, fmt(metrics[f"{name}_precision"]["value"]), fmt(metrics[f"{name}_recall"]["value"]),
            fmt(metrics[f"{name}_f1"]["value"]), metrics[f"{name}_recall"]["n"]))
    lines += ["", f"- Owner accuracy on matched tasks: {fmt(metrics['owner_accuracy']['value'])} ({metrics['owner_accuracy']['n']} matched)",
              f"- Deadline accuracy on matched tasks: {fmt(metrics['deadline_accuracy']['value'])}", ""]
    lines += ["## Time and memory", "",
              f"- Real-time factor (processing time / audio length): mean {fmt(metrics['rtf_mean']['value'], 'x')}, max {fmt(metrics['rtf_max']['value'], 'x')}",
              f"- Peak memory (phys footprint, sampled): {fmt(metrics['peak_mb_max']['value'], 'num')} MB",
              f"- Analysis chunks that fell back to rules: {metrics['fallback_chunks_total']['value']}", "",
              "| Meeting | Audio | Total | Transcribe | Speakers | Minutes | RTF | Peak MB |", "|---|---|---|---|---|---|---|---|"]
    for m in summary["perMeeting"]:
        t = m["timings"]
        lines.append("| {} | {:.0f}s | {} | {} | {} | {} | {} | {} |".format(
            m["id"], m["audio_s"], fmt(t.get("totalMs"), "ms"), fmt(t.get("transcribeMs"), "ms"),
            fmt(t.get("speakersMs"), "ms"), fmt(t.get("minutesMs"), "ms"), fmt(m["rtf"], "x"),
            m["peak_mb"] if m["peak_mb"] is not None else "n/a"))
    lines += ["", "## Per meeting", "", "| Meeting | Languages | Speaker error | Tasks F1 | Decisions F1 |", "|---|---|---|---|---|"]
    for m in summary["perMeeting"]:
        _, _, task_f1 = prf(m["tasks"]["tp"], m["tasks"]["predicted"], m["tasks"]["expected"])
        _, _, decision_f1 = prf(m["decisions"]["tp"], m["decisions"]["predicted"], m["decisions"]["expected"])
        lines.append("| {} | {} | {} | {} | {} |".format(
            m["id"], ", ".join(m["languages"]) or "n/a", fmt(m["speakers"]["rate"]), fmt(task_f1), fmt(decision_f1)))
    return "\n".join(lines) + "\n"


def compare(old, new, out=print):
    """Print a metric-by-metric diff. Returns the number of regressions."""
    regressions = 0
    out(f"Compare {old.get('commit') or 'old'} -> {new.get('commit') or 'new'}")
    out(f"{'metric':<28}{'old':>10}{'new':>10}{'delta':>10}  verdict")
    names = sorted(set(old["metrics"]) | set(new["metrics"]))
    for name in names:
        a = old["metrics"].get(name, {})
        b = new["metrics"].get(name, {})
        old_value, new_value = a.get("value"), b.get("value")
        better = b.get("better") or a.get("better") or "lower"
        kind = metric_kind(name)
        if old_value is None or new_value is None:
            out(f"{name:<28}{fmt(old_value, kind):>10}{fmt(new_value, kind):>10}{'':>10}  n/a")
            continue
        delta = new_value - old_value
        scale = abs(old_value) if kind in ("ms", "x", "num") else 1.0
        relative = delta / scale if scale else 0.0
        threshold = 0.05 if kind in ("ms", "x", "num") else 0.005
        if abs(relative) < threshold:
            verdict = "same"
        elif (delta < 0) == (better == "lower"):
            verdict = "better"
        else:
            verdict = "WORSE"
            regressions += 1
        shown = f"{delta * 100:+.1f}pp" if kind == "pct" else f"{delta:+.2f}" if kind != "ms" else f"{delta / 1000:+.1f}s"
        out(f"{name:<28}{fmt(old_value, kind):>10}{fmt(new_value, kind):>10}{shown:>10}  {verdict}")
    out(f"{regressions} regression(s)")
    return regressions


# ---------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------

def collect(golden_dir, results_dir):
    labels, results, missing = {}, {}, []
    for name in sorted(os.listdir(golden_dir)):
        label_path = os.path.join(golden_dir, name, "labels.json")
        if not os.path.isfile(label_path):
            continue
        labels[name] = load_json(label_path)
        result_path = os.path.join(results_dir, name, "result.json")
        if os.path.isfile(result_path):
            results[name] = load_json(result_path)
        else:
            missing.append(name)
    return labels, results, missing


def safe_name(text):
    return re.sub(r"[^A-Za-z0-9._-]", "_", text or "unknown")[:40]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--golden", help="folder of golden meetings (labels.json per subfolder)")
    parser.add_argument("--results", help="folder of result.json per meeting id")
    parser.add_argument("--out", default=os.path.join("build", "eval"))
    parser.add_argument("--commit", help="override the commit recorded in the results")
    parser.add_argument("--task-source", choices=("tasks", "rawTasks"), default="tasks",
                        help="tasks = minutes actions (default); rawTasks = reducer tasks")
    parser.add_argument("--compare", nargs=2, metavar=("OLD", "NEW"), help="diff two summary JSON files")
    args = parser.parse_args(argv)
    if args.compare:
        old, new = (load_json(path) for path in args.compare)
        compare(old, new)
        return 0
    if not args.golden or not args.results:
        parser.error("--golden and --results are required unless --compare is used")
    labels, results, missing = collect(args.golden, args.results)
    if not results:
        print("No result.json files found; nothing to score.", file=sys.stderr)
        return 1
    per_meeting = [score_meeting(labels[name], results[name], args.task_source) for name in labels if name in results]
    commit = args.commit or next((r.get("commit") for r in results.values() if r.get("commit")), "unknown")
    summary = build_summary(per_meeting, results, missing, commit, args.task_source)
    os.makedirs(args.out, exist_ok=True)
    stem = safe_name(commit)
    report_path = os.path.join(args.out, f"report-{stem}.md")
    summary_path = os.path.join(args.out, f"summary-{stem}.json")
    with open(report_path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(render_report(summary))
    with open(summary_path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(summary, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(f"Wrote {report_path}")
    print(f"Wrote {summary_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
