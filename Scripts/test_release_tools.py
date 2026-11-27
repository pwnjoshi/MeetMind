import argparse
import hashlib
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import release_tools


class PlaceholderTests(unittest.TestCase):
    def test_upload_fails_and_names_each_file_with_placeholder(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            privacy = root / "privacy.md"
            support = root / "support.md"
            privacy.write_text("Effective: <DATE>\nOwner: <YOUR NAME OR COMPANY>\n", encoding="utf-8")
            support.write_text("Contact <SUPPORT EMAIL>\n", encoding="utf-8")
            findings = release_tools.find_placeholders([root])
            self.assertEqual(set(findings), {str(privacy), str(support)})
            self.assertEqual(release_tools.check_placeholders([root], upload=True), 1)

    def test_dry_run_warns_but_succeeds(self):
        with tempfile.TemporaryDirectory() as directory:
            document = Path(directory) / "privacy.md"
            document.write_text("Contact <support email>\n", encoding="utf-8")
            self.assertEqual(release_tools.check_placeholders([document], upload=False), 0)


class SummaryTests(unittest.TestCase):
    def test_parses_xcresult_summary(self):
        counts = release_tools.parse_xcresult_summary({
            "totalTestCount": 5,
            "devicesAndConfigurations": [
                {"passedTests": 3, "failedTests": 1, "skippedTests": 1}
            ],
        })
        self.assertEqual(counts, {"total": 5, "passed": 3, "failed": 1, "skipped": 1})

    @mock.patch.object(release_tools, "xcresult_counts")
    def test_summary_contains_required_non_secret_fields(self, counts):
        counts.return_value = {"total": 5, "passed": 5, "failed": 0, "skipped": 0}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ipa = root / "Manent.ipa"
            ipa.write_bytes(b"signed ipa fixture")
            info = root / "Info.plist"
            with info.open("wb") as destination:
                plistlib.dump({
                    "CFBundleShortVersionString": "1.2.3",
                    "CFBundleVersion": "456",
                    "CFBundleIdentifier": "com.meetmind.app",
                    "ManentBuildCommit": "a" * 40,
                }, destination)
            for name, value in {
                "python.log": "Ran 12 tests in 0.1s\nOK\n",
                "engine.log": "Executed 8 tests, with 0 failures\n",
                "python.status": "PASS\n",
                "engine.status": "PASS\n",
                "app.status": "PASS\n",
                "smoke.status": "PASS\n",
                "privacy.status": "PASS: privacy manifest and signature verified\n",
            }.items():
                (root / name).write_text(value, encoding="utf-8")
            output = root / "summary.md"
            args = argparse.Namespace(
                sha="a" * 40,
                bundle_id="com.meetmind.app",
                signing_identity="Apple Distribution: Example (TEAM)",
                profile_uuid="00000000-0000-0000-0000-000000000000",
                profile_expiry="2030-01-01T00:00:00Z",
                ipa=ipa,
                info_plist=info,
                xcresult=root / "tests.xcresult",
                python_log=root / "python.log",
                engine_log=root / "engine.log",
                python_status=root / "python.status",
                engine_status=root / "engine.status",
                app_status=root / "app.status",
                smoke_status=root / "smoke.status",
                privacy_status=root / "privacy.status",
                output=output,
            )
            release_tools.create_summary(args)
            text = output.read_text(encoding="utf-8")
            self.assertIn("Marketing version: `1.2.3`", text)
            self.assertIn("Python: 12 (PASS)", text)
            self.assertIn("OfflineEngineKit Swift: 8 (PASS)", text)
            self.assertIn(hashlib.sha256(ipa.read_bytes()).hexdigest(), text)
            self.assertNotIn("PRIVATE KEY", text)


if __name__ == "__main__":
    unittest.main()
