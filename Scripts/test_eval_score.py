"""Unit tests for the golden-set scorer. Synthetic data only; no audio, no device."""
import json
import os
import tempfile
import unittest

import eval_labels_from_transcript as labels_tool
import eval_score as ev

# Devanagari written as escapes so the file is encoding-proof.
NAHIN = "\u0928\u0939\u0940\u0902"            # nahin
HAI = "\u0939\u0948"                           # hai
MEETING = "\u092e\u0940\u091f\u093f\u0902\u0917"  # meeting
KAAM = "\u0915\u093e\u092e"                    # kaam


def turn(start, end, speaker, text, lang="en"):
    return {"start": start, "end": end, "speaker": speaker, "text": text, "lang": lang}


class TextMetricsTests(unittest.TestCase):
    def test_edit_distance(self):
        self.assertEqual(ev.edit_distance(list("kitten"), list("sitting")), 3)
        self.assertEqual(ev.edit_distance([], ["a"]), 1)

    def test_latin_wer_pools_errors(self):
        ref = [turn(0, 4, "S1", "send the budget by Friday"), turn(4, 8, "S2", "okay thanks")]
        hyp = [{"start": 0, "end": 4, "speaker": "x", "text": "send the budget on Friday"},
               {"start": 4, "end": 8, "speaker": "x", "text": "okay thanks"}]
        entry = ev.transcript_errors(ref, hyp)["all"]["wer_latin"]
        self.assertEqual((entry.errors, entry.total), (1, 7))

    def test_devanagari_cer_ignores_latin_and_nukta(self):
        ref = [turn(0, 4, "S1", NAHIN + " launch", "hi")]
        hyp = [{"start": 0, "end": 4, "text": NAHIN + " lunch"}]
        result = ev.transcript_errors(ref, hyp)["hi"]
        self.assertEqual(result["cer_deva"].errors, 0)
        self.assertEqual(result["wer_latin"].errors, 1)

    def test_transliteration_matches_hinglish_spellings(self):
        self.assertEqual(ev.roman_skeleton(NAHIN), ev.roman_skeleton("nahin"))
        self.assertEqual(ev.roman_skeleton(MEETING), ev.roman_skeleton("meeting"))
        self.assertEqual(ev.roman_skeleton(KAAM), ev.roman_skeleton("kaam"))
        self.assertEqual(ev.roman_skeleton(HAI), "hai")

    def test_script_agnostic_wer_credits_roman_hindi_output(self):
        ref = [turn(0, 4, "S1", MEETING + " " + NAHIN, "hi")]
        hyp = [{"start": 0, "end": 4, "text": "meeting nahin"}]
        entry = ev.transcript_errors(ref, hyp)["hi"]
        self.assertEqual(entry["wer_roman"].errors, 0)
        self.assertEqual(entry["lang_correct"].errors, 1)  # but it is the wrong script

    def test_language_correctness_for_mixed_turn(self):
        ref = [turn(0, 4, "S1", HAI + " launch date " + NAHIN, "hinglish")]
        good = [{"start": 0, "end": 4, "text": HAI + " launch date " + NAHIN}]
        bad = [{"start": 0, "end": 4, "text": "hai launch date nahin"}]
        self.assertEqual(ev.transcript_errors(ref, good)["all"]["lang_correct"].errors, 0)
        self.assertEqual(ev.transcript_errors(ref, bad)["all"]["lang_correct"].errors, 1)

    def test_missing_hypothesis_counts_every_word(self):
        ref = [turn(0, 4, "S1", "one two three")]
        entry = ev.transcript_errors(ref, [])["all"]["wer_latin"]
        self.assertEqual((entry.errors, entry.total), (3, 3))

    def test_unoverlapping_hypothesis_goes_to_nearest_turn(self):
        ref = [turn(0, 4, "S1", "alpha"), turn(10, 14, "S2", "beta")]
        aligned = ev.align_hypothesis(ref, [{"start": 11, "end": 12, "text": "beta"}])
        self.assertEqual(aligned, ["", "beta"])


class SpeakerTests(unittest.TestCase):
    def ref(self):
        return [turn(0, 10, "A", "x"), turn(10, 20, "B", "y"), turn(20, 30, "C", "z")]

    def test_relabelled_speakers_are_not_errors(self):
        hyp = [turn(0, 10, "Speaker 2", ""), turn(10, 20, "Speaker 3", ""), turn(20, 30, "Speaker 1", "")]
        result = ev.speaker_error(self.ref(), hyp)
        self.assertEqual(result["rate"], 0.0)

    def test_confusion_and_missing_are_time_weighted(self):
        hyp = [turn(0, 10, "s1", ""), turn(10, 15, "s2", ""), turn(15, 20, "s1", ""), turn(20, 25, "s3", "")]
        # best mapping: s1->A (10 s) and s1 also covers B's 5 s but is used once; s2->B 5 s, s3->C 5 s.
        result = ev.speaker_error(self.ref(), hyp)
        self.assertAlmostEqual(result["total_s"], 30.0)
        self.assertAlmostEqual(result["missed_s"], 5.0)      # 25-30 has no hypothesis speaker
        self.assertAlmostEqual(result["confused_s"], 5.0)    # 15-20 labelled s1 but is B
        self.assertAlmostEqual(result["rate"], 10 / 30)

    def test_oversplit_speakers_still_map_one_to_one(self):
        ref = [turn(0, 20, "A", "x")]
        hyp = [turn(0, 12, "s1", ""), turn(12, 20, "s2", "")]
        result = ev.speaker_error(ref, hyp)
        self.assertAlmostEqual(result["rate"], 8 / 20)
        self.assertEqual((result["ref_speakers"], result["hyp_speakers"]), (1, 2))

    def test_eight_speakers_is_fast_and_correct(self):
        ref = [turn(i * 5, i * 5 + 5, f"R{i}", "x") for i in range(8)]
        hyp = [turn(i * 5, i * 5 + 5, f"H{(i + 3) % 8}", "") for i in range(8)]
        self.assertEqual(ev.speaker_error(ref, hyp)["rate"], 0.0)

    def test_no_labelled_speech(self):
        self.assertIsNone(ev.speaker_error([], [turn(0, 5, "s1", "")])["rate"])


class MatchingTests(unittest.TestCase):
    def test_token_set_ratio(self):
        self.assertGreaterEqual(ev.token_set_ratio("Send the vendor quote to finance", "send vendor quotes to the finance team"), 0.6)
        self.assertLess(ev.token_set_ratio("Book the venue", "Update the budget sheet"), 0.6)
        self.assertEqual(ev.token_set_ratio("", "anything"), 0.0)

    def test_cross_script_match(self):
        self.assertGreaterEqual(ev.token_set_ratio("meeting " + NAHIN + " launch", "miting nahin launch"), 0.6)

    def test_matching_is_one_to_one(self):
        matches = ev.match_items(["send budget report"], ["send budget report", "send budget report now"])
        self.assertEqual(len(matches), 1)
        self.assertEqual(matches[0][1], 0)

    def test_prf_edges(self):
        self.assertEqual(ev.prf(0, 0, 0), (1.0, 1.0, 1.0))
        self.assertEqual(ev.prf(0, 0, 2), (1.0, 0.0, 0.0))
        p, r, f = ev.prf(1, 2, 4)
        self.assertEqual((p, r), (0.5, 0.25))
        self.assertAlmostEqual(f, 1 / 3)

    def test_owner_and_deadline_on_matched_tasks(self):
        ref = [{"title": "Send the presentation to the client", "owner": "Neha", "deadline": "tomorrow"},
               {"title": "Prepare the agenda", "owner": "Pawan", "deadline": "Friday"},
               {"title": "Call the vendor", "owner": None, "deadline": None}]
        pred = [{"title": "Send presentation to client", "owner": "Neha Sharma", "deadlineText": "by tomorrow"},
                {"title": "Prepare agenda", "owner": "Neha", "deadlineText": "Friday"},
                {"title": "Order catering for lunch", "owner": "Pawan", "deadlineText": None}]
        counts = ev.score_tasks(ref, pred)
        self.assertEqual((counts["tp"], counts["predicted"], counts["expected"]), (2, 3, 3))
        self.assertEqual(counts["owner_ok"], 1)
        self.assertEqual(counts["deadline_ok"], 2)

    def test_deadline_accepts_resolved_date(self):
        self.assertTrue(ev.deadline_matches("2025-11-20", "20 November", "2025-11-20"))
        self.assertFalse(ev.deadline_matches("Friday", None))
        self.assertTrue(ev.deadline_matches(None, None))
        self.assertFalse(ev.deadline_matches(None, "Friday"))


def labels_fixture():
    return {
        "id": "m1", "languages": ["en", "hinglish"],
        "speakers": [{"label": "A", "name": "Neha"}, {"label": "B", "name": "Pawan"}],
        "turns": [turn(0, 5, "A", "Pawan please send the budget by Friday", "en"),
                  turn(5, 10, "B", "haan " + HAI + " main bhej dunga", "hinglish")],
        "tasks": [{"title": "Send the budget", "owner": "Pawan", "deadline": "Friday"}],
        "decisions": ["Launch on 20 November"], "openIssues": [], "participants": ["Neha", "Pawan"], "agenda": ["Budget"],
    }


def result_fixture(commit="abc1234", budget_ms=60000):
    return {
        "schema": 1, "id": "m1", "commit": commit, "device": "iPhone15,4", "osVersion": "17", "model": "qwen-1.7b",
        "promptVersion": "v9", "audioSeconds": 10.0,
        "turns": [{"id": "t1", "start": 0, "end": 5, "speaker": "Speaker 1", "text": "Pawan please send the budget by Friday"},
                  {"id": "t2", "start": 5, "end": 10, "speaker": "Speaker 2", "text": "haan " + HAI + " main bhej dunga"}],
        "tasks": [{"title": "Send budget", "owner": "Pawan", "deadlineText": "Friday", "dueDate": None}],
        "rawTasks": [], "decisions": ["Launch on 20 November"], "openIssues": [], "summary": "",
        "timings": {"totalMs": budget_ms, "transcribeMs": 30000, "speakersMs": 10000, "minutesMs": 20000,
                    "modelLoadMs": 2000, "fallbackChunks": 0},
        "peakFootprintMB": 2500,
    }


class EndToEndTests(unittest.TestCase):
    def test_perfect_meeting(self):
        meeting = ev.score_meeting(labels_fixture(), result_fixture())
        metrics = ev.aggregate([meeting])
        self.assertEqual(metrics["wer_latin.all"]["value"], 0.0)
        self.assertEqual(metrics["speaker_error"]["value"], 0.0)
        self.assertEqual(metrics["tasks_f1"]["value"], 1.0)
        self.assertEqual(metrics["decisions_f1"]["value"], 1.0)
        self.assertEqual(metrics["owner_accuracy"]["value"], 1.0)
        self.assertEqual(metrics["deadline_accuracy"]["value"], 1.0)
        self.assertAlmostEqual(metrics["rtf_mean"]["value"], 6.0)
        self.assertEqual(metrics["peak_mb_max"]["value"], 2500)

    def test_cli_writes_report_and_compare_flags_regression(self):
        with tempfile.TemporaryDirectory() as tmp:
            golden, runs, out = (os.path.join(tmp, n) for n in ("golden", "runs", "out"))
            for root in (golden, runs):
                os.makedirs(os.path.join(root, "m1"))
            with open(os.path.join(golden, "m1", "labels.json"), "w", encoding="utf-8") as handle:
                json.dump(labels_fixture(), handle)
            summaries = []
            for commit, ms in (("old1111", 60000), ("new2222", 120000)):
                with open(os.path.join(runs, "m1", "result.json"), "w", encoding="utf-8") as handle:
                    json.dump(result_fixture(commit, ms), handle)
                self.assertEqual(ev.main(["--golden", golden, "--results", runs, "--out", out]), 0)
                self.assertTrue(os.path.isfile(os.path.join(out, f"report-{commit}.md")))
                with open(os.path.join(out, f"summary-{commit}.json"), encoding="utf-8") as handle:
                    summaries.append(json.load(handle))
            with open(os.path.join(out, "report-new2222.md"), encoding="utf-8") as handle:
                report = handle.read()
            self.assertIn("## Time and memory", report)
            lines = []
            regressions = ev.compare(summaries[0], summaries[1], out=lines.append)
            self.assertGreaterEqual(regressions, 1)
            self.assertTrue(any(line.startswith("rtf_mean") and "WORSE" in line for line in lines))
            self.assertTrue(any(line.startswith("tasks_f1") and "same" in line for line in lines))

    def test_missing_result_is_reported_not_fatal(self):
        with tempfile.TemporaryDirectory() as tmp:
            golden = os.path.join(tmp, "golden")
            os.makedirs(os.path.join(golden, "m1"))
            with open(os.path.join(golden, "m1", "labels.json"), "w", encoding="utf-8") as handle:
                json.dump(labels_fixture(), handle)
            _, results, missing = ev.collect(golden, os.path.join(tmp, "none"))
            self.assertEqual((results, missing), ({}, ["m1"]))


class LabelsToolTests(unittest.TestCase):
    def test_skeleton_from_transcript(self):
        lines = ["# comment", "[00:00] Neha: Hi Pawan, let's start.", "[00:12] Pawan: haan theek hai, kal bhej dunga",
                 "continued words", "[1:00:05] Neha: " + MEETING + " " + HAI + " launch"]
        turns = labels_tool.parse_transcript(lines)
        labels = labels_tool.build_labels(turns, "demo", duration=3700)
        self.assertEqual([s["label"] for s in labels["speakers"]], ["S1", "S2"])
        self.assertEqual(labels["turns"][0]["end"], 12.0)
        self.assertEqual(labels["turns"][1]["end"], 3605.0)
        self.assertIn("continued words", labels["turns"][1]["text"])
        self.assertEqual(labels["turns"][2]["end"], 3700)
        self.assertEqual([t["lang"] for t in labels["turns"]], ["en", "hinglish", "hinglish"])
        self.assertEqual(labels["participants"], ["Neha", "Pawan"])
        self.assertEqual(labels["tasks"], [])


if __name__ == "__main__":
    unittest.main()
