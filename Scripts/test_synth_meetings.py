"""Tests for Scripts/synth_meetings.py that need no macOS speech tools."""
import json
import math
import os
import struct
import sys
import tempfile
import unittest
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import synth_meetings as synth  # noqa: E402

VOICE_LISTING = """\
Alex                en_US    # Most people recognize me by my voice.
Lekha               hi_IN    # \u0928\u092e\u0938\u094d\u0915\u093e\u0930, \u092e\u0947\u0930\u093e \u0928\u093e\u092e \u0932\u0947\u0916\u093e \u0939\u0948.
Rishi               en_IN    # Hello! My name is Rishi.
Veena               en_IN    # Hello! My name is Veena.
Daniel              en_GB    # Hello, my name is Daniel.
Samantha            en_US    # Hello, my name is Samantha.
Eddy (English (US)) en_US    # Hello, my name is Eddy.
"""


def fake_synth(voice, text, path):
    """A tone whose length depends on the text, so timing is predictable: 0.05 s per character."""
    seconds = 0.05 * len(text)
    count = int(seconds * synth.SAMPLE_RATE)
    frames = b"".join(struct.pack("<h", int(8000 * math.sin(2 * math.pi * 220 * i / synth.SAMPLE_RATE))) for i in range(count))
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(synth.SAMPLE_RATE)
        handle.writeframes(frames)


class VoiceTests(unittest.TestCase):
    def test_parse_voices(self):
        voices = synth.parse_voices(VOICE_LISTING)
        self.assertEqual(voices["Lekha"], "hi_IN")
        self.assertEqual(voices["Eddy (English (US))"], "en_US")
        self.assertEqual(len(voices), 7)

    def test_resolution_uses_distinct_voices(self):
        available = synth.parse_voices(VOICE_LISTING)
        meeting = next(m for m in synth.MEETINGS if m["id"] == "synth-en-vendor-call")
        chosen = synth.resolve_voices(meeting, available)
        self.assertEqual(len(set(chosen.values())), 4)
        self.assertEqual(chosen["S1"], "Veena")
        self.assertEqual(chosen["S2"], "Rishi")

    def test_fallback_when_preferred_voice_is_missing(self):
        available = {"Alex": "en_US", "Samantha": "en_US"}
        meeting = next(m for m in synth.MEETINGS if m["id"] == "synth-en-standup")
        chosen = synth.resolve_voices(meeting, available)
        self.assertEqual(set(chosen.values()), {"Alex", "Samantha"})

    def test_missing_hindi_voice_skips_meeting(self):
        available = {"Rishi": "en_IN", "Veena": "en_IN", "Alex": "en_US"}
        meeting = next(m for m in synth.MEETINGS if m["id"] == "synth-hi-review")
        with self.assertRaises(LookupError):
            synth.resolve_voices(meeting, available)

    def test_too_few_english_voices_is_an_error(self):
        meeting = next(m for m in synth.MEETINGS if m["id"] == "synth-en-vendor-call")
        with self.assertRaises(LookupError):
            synth.resolve_voices(meeting, {"Alex": "en_US", "Daniel": "en_GB"})


class TimelineTests(unittest.TestCase):
    def test_spans_and_total(self):
        spans, total = synth.plan_timeline([2.0, 3.0, 1.5], [0.5, 0.7], lead=0.3, tail=0.5)
        self.assertEqual(spans, [(0.3, 2.3), (2.8, 5.8), (6.5, 8.0)])
        self.assertEqual(total, 8.5)

    def test_single_turn(self):
        spans, total = synth.plan_timeline([4.0], [], lead=0.3, tail=0.5)
        self.assertEqual(spans, [(0.3, 4.3)])
        self.assertEqual(total, 4.8)

    def test_wrong_pause_count(self):
        with self.assertRaises(ValueError):
            synth.plan_timeline([1.0, 1.0], [])

    def test_pauses_are_deterministic(self):
        self.assertEqual(synth.pause_plan("synth-en-standup", 6), synth.pause_plan("synth-en-standup", 6))
        self.assertTrue(all(p in synth.PAUSES for p in synth.pause_plan("x", 10)))
        self.assertEqual(synth.pause_plan("x", 1), [])

    def test_trim_silence(self):
        pcm = b"\x00\x00" * 1000 + struct.pack("<h", 5000) * 100 + b"\x00\x00" * 1000
        trimmed = synth.trim_silence(pcm, synth.SAMPLE_RATE, keep=0.01)
        self.assertEqual(len(trimmed) // 2, 100 + 2 * int(0.01 * synth.SAMPLE_RATE))


class MeetingDataTests(unittest.TestCase):
    def test_every_turn_uses_a_declared_speaker_and_known_language(self):
        for meeting in synth.MEETINGS:
            labels = {s[0] for s in meeting["speakers"]}
            self.assertTrue(2 <= len(meeting["turns"]) or len(labels) == 1, meeting["id"])
            for speaker, lang, text in meeting["turns"]:
                self.assertIn(speaker, labels, meeting["id"])
                self.assertIn(lang, ("en", "hi", "hinglish"))
                self.assertTrue(text.strip())

    def test_coverage(self):
        ids = [m["id"] for m in synth.MEETINGS]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertGreaterEqual(len(ids), 8)
        langs = {t[1] for m in synth.MEETINGS for t in m["turns"]}
        self.assertEqual(langs, {"en", "hi", "hinglish"})
        counts = {len(m["speakers"]) for m in synth.MEETINGS}
        self.assertTrue({1, 2, 3, 4} >= counts and {2, 3, 4} <= counts)
        self.assertTrue(any(not m["tasks"] for m in synth.MEETINGS))
        self.assertTrue(any(any("\u0900" <= c <= "\u097f" for c in t[2]) for m in synth.MEETINGS for t in m["turns"]))

    def test_speech_length_budget(self):
        # Roughly 15 characters per second of speech keeps every meeting under about a minute.
        for meeting in synth.MEETINGS:
            characters = sum(len(t[2]) for t in meeting["turns"])
            self.assertLess(characters / 13.0, 65, meeting["id"])


class RenderTests(unittest.TestCase):
    def test_render_writes_labels_matching_the_audio(self):
        meeting = next(m for m in synth.MEETINGS if m["id"] == "synth-en-planning")
        voices = {label: f"V{label}" for label, _n, _r in meeting["speakers"]}
        with tempfile.TemporaryDirectory() as out:
            labels = synth.render_meeting(meeting, voices, out, synth=fake_synth)
            folder = os.path.join(out, meeting["id"])
            with wave.open(os.path.join(folder, "audio.wav"), "rb") as handle:
                self.assertEqual((handle.getnchannels(), handle.getsampwidth(), handle.getframerate()),
                                 (1, 2, synth.SAMPLE_RATE))
                total = handle.getnframes() / handle.getframerate()
            with open(os.path.join(folder, "labels.json"), encoding="utf-8") as handle:
                saved = json.load(handle)
        self.assertEqual(saved, json.loads(json.dumps(labels)))
        turns = saved["turns"]
        self.assertEqual(len(turns), len(meeting["turns"]))
        previous_end = 0.0
        for turn in turns:
            self.assertGreater(turn["start"], previous_end)  # a pause always separates turns
            self.assertGreater(turn["end"], turn["start"])
            previous_end = turn["end"]
        self.assertAlmostEqual(total, previous_end + synth.TAIL_SECONDS, delta=0.03)
        expected_pauses = synth.pause_plan(meeting["id"], len(turns))
        for index, pause in enumerate(expected_pauses):
            self.assertAlmostEqual(turns[index + 1]["start"] - turns[index]["end"], pause, delta=0.02)
        for key in ("id", "languages", "speakers", "turns", "tasks", "decisions", "openIssues", "participants", "agenda"):
            self.assertIn(key, saved)
        self.assertEqual(saved["speakers"][0], {"label": "S1", "name": "Neha"})

    def test_rendering_twice_is_byte_identical(self):
        meeting = synth.MEETINGS[0]
        voices = {label: f"V{label}" for label, _n, _r in meeting["speakers"]}
        blobs = []
        for _ in range(2):
            with tempfile.TemporaryDirectory() as out:
                synth.render_meeting(meeting, voices, out, synth=fake_synth)
                folder = os.path.join(out, meeting["id"])
                blobs.append([open(os.path.join(folder, n), "rb").read() for n in ("audio.wav", "labels.json")])
        self.assertEqual(blobs[0], blobs[1])

    def test_generate_skips_unrenderable_meetings(self):
        available = {"Rishi": "en_IN", "Veena": "en_IN", "Daniel": "en_GB", "Samantha": "en_US"}
        with tempfile.TemporaryDirectory() as out:
            rendered, skipped = synth.generate(out, available=available, synth=fake_synth)
            self.assertIn("synth-en-standup", rendered)
            self.assertIn("synth-hi-review", skipped)
            self.assertIn("synth-hinglish-sprint", skipped)
            with open(os.path.join(out, "voices.json"), encoding="utf-8") as handle:
                self.assertIn("synth-hi-review", json.load(handle)["skipped"])

    def test_only_filter_accepts_short_names(self):
        available = {"Rishi": "en_IN", "Veena": "en_IN"}
        with tempfile.TemporaryDirectory() as out:
            rendered, _ = synth.generate(out, only={"en-standup"}, available=available, synth=fake_synth)
        self.assertEqual(rendered, ["synth-en-standup"])


if __name__ == "__main__":
    unittest.main()
