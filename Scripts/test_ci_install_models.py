"""Tests for Scripts/ci_install_models.py and the log parsing in Scripts/ci_sim_eval.py (no network, no simulator)."""
import hashlib
import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ci_install_models as installer  # noqa: E402
import ci_sim_eval as sim  # noqa: E402


def make_profile(directory, files):
    """Profile whose assets are local file:// URLs so downloads need no network."""
    assets = []
    for relative, payload in files.items():
        source = os.path.join(directory, "remote", *relative.split("/"))
        os.makedirs(os.path.dirname(source), exist_ok=True)
        with open(source, "wb") as handle:
            handle.write(payload)
        assets.append({"path": relative, "url": "file:///" + source.replace("\\", "/").lstrip("/"),
                       "sha256": hashlib.sha256(payload).hexdigest(), "bytes": len(payload)})
    return {"id": "demo", "name": "Demo model", "revision": "r1", "files": assets}


class DigestTests(unittest.TestCase):
    def test_canonical_encoding_matches_swift_sorted_keys(self):
        profile = {"id": "m", "name": "n", "revision": "r",
                   "files": [{"path": "a/b.bin", "url": "https://huggingface.co/x/y", "sha256": "ab", "bytes": 3}]}
        expected = ('{"files":[{"bytes":3,"path":"a\\/b.bin","sha256":"ab","url":"https:\\/\\/huggingface.co\\/x\\/y"}],'
                    '"id":"m","name":"n","revision":"r"}')
        self.assertEqual(installer.swift_sorted_json(profile), expected)
        self.assertEqual(installer.profile_digest(profile), hashlib.sha256(expected.encode()).hexdigest())
        self.assertEqual(installer.folder_name(profile), "m-" + hashlib.sha256(expected.encode()).hexdigest()[:12])

    def test_extra_keys_do_not_change_the_digest(self):
        profile = {"id": "m", "name": "n", "revision": "r", "files": [], "note": "ignored"}
        plain = {"id": "m", "name": "n", "revision": "r", "files": []}
        self.assertEqual(installer.profile_digest(profile), installer.profile_digest(plain))

    def test_real_manifest_names_are_stable_and_distinct(self):
        manifest = installer.load_manifest()
        profiles = installer.select_profiles(manifest, installer.DEFAULT_IDS)
        names = [installer.folder_name(p) for p in profiles]
        self.assertEqual(len(set(names)), 3)
        for profile, name in zip(profiles, names):
            self.assertRegex(name, r"^" + profile["id"] + r"-[0-9a-f]{12}$")
            for asset in profile["files"]:
                installer.validate_asset(asset)
        with self.assertRaises(KeyError):
            installer.select_profiles(manifest, ["nope"])

    def test_asset_validation(self):
        good = {"path": "a/b", "url": "https://huggingface.co/x"}
        installer.validate_asset(good)
        for bad in ({"path": "../x", "url": good["url"]}, {"path": "/x", "url": good["url"]},
                    {"path": "", "url": good["url"]}, {"path": "a", "url": "https://example.com/x"},
                    {"path": "a", "url": "http://huggingface.co/x"}):
            with self.assertRaises(ValueError):
                installer.validate_asset(bad)


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.profile = make_profile(self.tmp, {"weights/w.bin": b"x" * 5000, "config.json": b"{}"})
        self.logs = []

    def cache(self):
        return os.path.join(self.tmp, "cache")

    def test_download_verify_install_layout(self):
        folder = installer.ensure_cached(self.profile, self.cache(), allow_any_url=True, log=self.logs.append)
        self.assertEqual(os.path.basename(folder), installer.folder_name(self.profile))
        self.assertTrue(installer.folder_complete(folder, self.profile))
        container = os.path.join(self.tmp, "container")
        root = installer.app_models_root(container)
        os.makedirs(root)
        destination = installer.install_into(root, self.profile, folder, log=self.logs.append)
        self.assertEqual(destination, os.path.join(container, "Library", "Application Support",
                                                    "OfflineIntelligence", "Models", installer.folder_name(self.profile)))
        for asset in self.profile["files"]:
            installed = os.path.join(destination, *asset["path"].split("/"))
            self.assertEqual(installer.sha256_file(installed), asset["sha256"])
        with open(os.path.join(destination, "verified.json"), encoding="utf-8") as handle:
            self.assertEqual(installer.profile_digest(json.load(handle)), installer.profile_digest(self.profile))
        self.assertFalse(os.path.exists(destination + ".download"))

    def test_second_run_is_idempotent(self):
        folder = installer.ensure_cached(self.profile, self.cache(), allow_any_url=True, log=self.logs.append)
        root = os.path.join(self.tmp, "models")
        os.makedirs(root)
        installer.install_into(root, self.profile, folder, log=self.logs.append)
        marker = os.path.join(root, installer.folder_name(self.profile), "verified.json")
        before = os.stat(marker).st_mtime_ns
        self.logs.clear()
        installer.ensure_cached(self.profile, self.cache(), allow_any_url=True, log=self.logs.append)
        installer.install_into(root, self.profile, folder, log=self.logs.append)
        self.assertEqual(os.stat(marker).st_mtime_ns, before)
        self.assertTrue(any("cache complete" in line for line in self.logs))
        self.assertTrue(any("already installed" in line for line in self.logs))

    def test_corrupt_download_is_rejected_and_not_kept(self):
        broken = json.loads(json.dumps(self.profile))
        broken["files"][0]["sha256"] = "0" * 64
        with self.assertRaises(RuntimeError):
            installer.download_asset(broken["files"][0], os.path.join(self.tmp, "t", "w.bin"), retries=1,
                                     log=self.logs.append)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "t", "w.bin")))
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "t", "w.bin.partial")))

    def test_truncated_cache_file_triggers_redownload(self):
        folder = installer.ensure_cached(self.profile, self.cache(), allow_any_url=True, log=self.logs.append)
        victim = os.path.join(folder, "weights", "w.bin")
        with open(victim, "wb") as handle:
            handle.write(b"short")
        self.assertFalse(installer.folder_complete(folder, self.profile))
        installer.ensure_cached(self.profile, self.cache(), allow_any_url=True, log=self.logs.append)
        self.assertEqual(installer.sha256_file(victim), self.profile["files"][0]["sha256"])

    def test_changed_profile_gets_a_new_folder(self):
        newer = json.loads(json.dumps(self.profile))
        newer["revision"] = "r2"
        self.assertNotEqual(installer.folder_name(self.profile), installer.folder_name(newer))
        self.assertFalse(installer.folder_complete(os.path.join(self.cache(), installer.folder_name(self.profile)), newer))

    def test_partial_file_resumes_from_its_size(self):
        payload = b"abcdefghij" * 1000
        asset = {"path": "p.bin", "url": "http://example.invalid/p.bin", "sha256": hashlib.sha256(payload).hexdigest(),
                 "bytes": len(payload)}
        target = os.path.join(self.tmp, "resume", "p.bin")
        os.makedirs(os.path.dirname(target))
        with open(target + ".partial", "wb") as handle:
            handle.write(payload[:4000])
        seen = {}

        class Response:
            status = 206

            def __init__(self, data):
                self.data = data

            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def read(self, n):
                chunk, self.data = self.data[:n], self.data[n:]
                return chunk

        class Opener:
            def open(self, request, timeout=0):
                seen["range"] = request.get_header("Range")
                return Response(payload[4000:])

        self.assertEqual(installer.download_asset(asset, target, opener=Opener(), log=self.logs.append), "downloaded")
        self.assertEqual(seen["range"], "bytes=4000-")
        self.assertEqual(open(target, "rb").read(), payload)


class LogParsingTests(unittest.TestCase):
    LINES = [
        "2025 noise MEETMIND_EVAL start folders=2 commit=abc1234 device=arm64",
        "MEETMIND_EVAL env simulator=1 available_mb=2048",
        "MEETMIND_EVAL model id=whisper-large state=ready dir=whisper-large-0123456789ab",
        "MEETMIND_EVAL model id=diarization state=absent dir=diarization-aaaaaaaaaaaa",
        "MEETMIND_EVAL meeting id=a state=running",
        'MEETMIND_EVAL meeting id=a state=failed type="X.Y" message="Not enough memory, retry"',
        "MEETMIND_EVAL completed ok=1 failed=1",
        "unrelated line",
    ]

    def test_parse_and_fold(self):
        events = [e for e in map(sim.parse_line, self.LINES) if e]
        self.assertEqual(len(events), 7)
        state = sim.summarize_events(events)
        self.assertTrue(state["completed"])
        self.assertEqual((state["ok"], state["failed"], state["commit"]), (1, 1, "abc1234"))
        self.assertEqual(state["meetings"]["a"], "failed")
        self.assertEqual(state["messages"]["a"], "Not enough memory, retry")
        self.assertEqual(state["models"]["diarization"]["state"], "absent")

    def test_preflight_problems(self):
        events = [e for e in map(sim.parse_line, self.LINES) if e]
        problems = sim.preflight_problems(sim.summarize_events(events))
        self.assertEqual(len(problems), 2)
        self.assertIn("diarization-aaaaaaaaaaaa", " ".join(problems))
        self.assertIn("qwen-3.5-0.8b", " ".join(problems))

    def test_zero_available_memory_on_simulator_is_not_a_problem(self):
        lines = ["MEETMIND_EVAL env simulator=1 available_mb=0"] + [
            f"MEETMIND_EVAL model id={m} state=ready dir={m}-x" for m in sim.REQUIRED_MODELS]
        problems = sim.preflight_problems(sim.summarize_events([sim.parse_line(x) for x in lines]))
        # The model loader skips the memory reading on the simulator, so 0 is fine there.
        self.assertEqual(problems, [])

    def test_follower_reads_only_complete_lines(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "log")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("MEETMIND_EVAL start folders=1 commit=c device=d\nMEETMIND_EVAL compl")
            follower = sim.LogFollower(path)
            self.assertEqual(len(follower.poll(echo=False)), 1)
            with open(path, "a", encoding="utf-8") as handle:
                handle.write("eted ok=1 failed=0\n")
            self.assertEqual(follower.poll(echo=False)[0][0], "completed")

    def test_summary_banners(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIn("No evaluation result", sim.render_summary(tmp, "failure"))
            status = {"commit": "abc", "meetings": ["a", "b"], "scored": ["a"], "failed": ["b"], "reason": "ok",
                      "elapsedSeconds": 125, "env": {}, "messages": {"b": "boom"}}
            with open(os.path.join(tmp, "status.json"), "w", encoding="utf-8") as handle:
                json.dump(status, handle)
            with open(os.path.join(tmp, "report-abc.md"), "w", encoding="utf-8") as handle:
                handle.write("REPORT BODY\n")
            text = sim.render_summary(tmp)
            self.assertIn("1 of 2 meetings scored", text)
            self.assertIn("`b`: boom", text)
            self.assertIn("REPORT BODY", text)
            status.update(failed=[], scored=["a", "b"])
            with open(os.path.join(tmp, "status.json"), "w", encoding="utf-8") as handle:
                json.dump(status, handle)
            self.assertIn("All 2 meetings scored", sim.render_summary(tmp))

    def test_stage_and_collect(self):
        with tempfile.TemporaryDirectory() as tmp:
            golden = os.path.join(tmp, "golden")
            for name in ("one", "two"):
                os.makedirs(os.path.join(golden, name))
                for file in ("audio.wav", "labels.json"):
                    with open(os.path.join(golden, name, file), "wb") as handle:
                        handle.write(b"1")
            open(os.path.join(golden, "voices.json"), "w").write("{}")
            container = os.path.join(tmp, "container")
            os.makedirs(os.path.join(container, "Documents", "Evaluation", "stale"))
            root, names = sim.stage_golden(container, golden)
            self.assertEqual(names, ["one", "two"])
            self.assertFalse(os.path.exists(os.path.join(root, "stale")))
            open(os.path.join(root, "one", "result.json"), "w").write("{}")
            got = sim.collect_results(root, names, os.path.join(tmp, "runs"))
            self.assertEqual(got, ["one"])


if __name__ == "__main__":
    unittest.main()
