import copy
import unittest

from evaluate_offline import edit_distance, qualify, tokens


def synthetic_report():
    """Fabricated scorer input, never a model-quality result."""
    case = {
        "id": "fixture", "split": "held_out", "consented": True,
        "scenarios": ["code_switching", "names_numbers", "room_noise", "overlap", "negation",
                      "reassignment", "cancellation", "relative_dates", "ambiguous_owner"],
        "human_reviewed": True, "duration_seconds": 3600, "participants": 6,
        "reference_text": "कल estimate भेज देना", "predicted_text": "कल estimate भेज देना",
        "reference_task_ids": ["r1"], "turns": {"t1": "कल estimate भेज देना"},
        "tasks": [{"id": "p1", "matched_reference_id": "r1", "supported": True,
                   "owner": "Rahul", "owner_correct": True,
                   "date": "2026-11-19", "date_correct": True,
                   "evidence": [{"turn_id": "t1", "quote": "estimate भेज देना"}]}],
        "decisions": [], "summary_factual": True, "summary_readable_english": True,
        "diarization_error_seconds": 1, "diarization_reference_seconds": 100,
        "processing_seconds": 100, "peak_memory_bytes": 1_000_000, "crashed": False,
    }
    cases = []
    for i in range(20):
        item = copy.deepcopy(case)
        item["id"] = str(i)
        cases.append(item)
    cases[-1]["scenarios"] = ["no_tasks", "no_decisions"]
    cases[-1]["tasks"] = []
    cases[-1]["reference_task_ids"] = []
    return {"schema_version": 1, "device": "iPhone15,4", "airplane_mode": True,
            "reviewer": "Synthetic unit test",
            "engines": {k: {"revision": "synthetic", "sha256": "a" * 64}
                        for k in ("asr", "diarization", "analysis")}, "cases": cases}


class EvaluationTests(unittest.TestCase):
    def test_devanagari_vowels_preserved(self):
        self.assertEqual(tokens("भेज देना!", {}), ["भेज", "देना"])

    def test_explicit_aliases(self):
        self.assertEqual(tokens("Kal, ESTIMATE", {"kal": "कल"}), ["कल", "estimate"])

    def test_edit_distance(self):
        self.assertEqual(edit_distance(["a", "b"], ["a", "c", "d"]), 2)

    def test_synthetic_perfect_input(self):
        self.assertTrue(qualify(synthetic_report())["qualified"])

    def test_missing_measurements_fail(self):
        report = synthetic_report()
        del report["cases"][0]["peak_memory_bytes"]
        self.assertFalse(qualify(report)["qualified"])

    def test_duplicate_match_fails(self):
        report = synthetic_report()
        task = copy.deepcopy(report["cases"][0]["tasks"][0])
        task["id"] = "p2"
        report["cases"][0]["tasks"].append(task)
        self.assertFalse(qualify(report)["qualified"])

    def test_nonexistent_evidence_fails(self):
        report = synthetic_report()
        report["cases"][0]["tasks"][0]["evidence"][0]["turn_id"] = "missing"
        self.assertFalse(qualify(report)["qualified"])

    def test_invented_decision_fails(self):
        report = synthetic_report()
        report["cases"][0]["decisions"] = [{"supported": False, "evidence": []}]
        self.assertFalse(qualify(report)["qualified"])

    def test_development_recording_fails(self):
        report = synthetic_report()
        report["cases"][0]["split"] = "development"
        self.assertFalse(qualify(report)["qualified"])

    def test_no_tasks_cannot_claim_perfect_quality(self):
        report = synthetic_report()
        for case in report["cases"]:
            case["tasks"] = []
            case["reference_task_ids"] = []
        self.assertFalse(qualify(report)["qualified"])

    def test_nan_memory_fails(self):
        report = synthetic_report()
        report["cases"][0]["peak_memory_bytes"] = float("nan")
        self.assertFalse(qualify(report)["qualified"])

    def test_missing_scenarios_fail(self):
        report = synthetic_report()
        for case in report["cases"]:
            case["scenarios"] = []
        self.assertFalse(qualify(report)["qualified"])

    def test_hallucination_on_no_task_case_fails(self):
        report = synthetic_report()
        report["cases"][-1]["tasks"] = copy.deepcopy(report["cases"][0]["tasks"])
        self.assertFalse(qualify(report)["qualified"])


if __name__ == "__main__":
    unittest.main()
